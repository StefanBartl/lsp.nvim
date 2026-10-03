---@module 'lsp.core.env_links_server'
---@brief Definition and hover for `$VAR/...` and `~/...` Markdown links.
---@description
--- marksman answers neither request for a link whose target starts with an
--- environment variable (see `lsp.core.env_links` for the measurement), so
--- `gd`, peek and `K` do nothing on such a link. This is the missing answer,
--- in the same shape as `lsp.core.gitsigns_actions`: a small **in-process**
--- server -- `cmd` is a Lua function, no process, no install -- attached to
--- Markdown buffers.
---
--- **Why a client, not a keymap.** Every feature that asks the language
--- servers about a position (`gd`, the peek float, hover, anything a config
--- adds later) goes through `vim.lsp.buf_request_all` and merges the answers of
--- all clients. One more client makes all of them work with no per-feature
--- wiring; a keymap fallback would fix `gd` and leave the rest.
---
--- **It only speaks up where marksman cannot.** Both handlers answer `nil`
--- unless the position is inside a link whose target is an env/home reference
--- that resolves -- so on every other position, and for every ordinary link,
--- marksman's answer is the only one and nothing changes.
---
--- **Diagnostics.** The client also reports the env links that lead nowhere:
--- the file is not there, or (for a Markdown file) the `#fragment` names no
--- heading. marksman cannot be the source of these: it never reports a link
--- that carries a `#fragment` at all, relative or not (measured), and for the
--- ones it does report it only knows the target as a folder name. They are
--- *pulled* (`textDocument/diagnostic`): Neovim asks on every open and change,
--- and the client answers from the buffer. Documentation that shows a link in a
--- code block or code span is not reported (`lsp.core.env_links.scan`).
---
--- **What it costs.** One more client in `vim.lsp.get_clients()` and in
--- `:Lsp servers`, named `lsp.nvim-envlinks` like the gitsigns one and looked
--- past by `lsp.core.util.server_clients`. `languages.env_links = false` turns
--- this and the diagnostics filter off together.
---
--- The resolution itself -- gopath.nvim first, built-in otherwise -- is
--- `lsp.core.env_links`.
---
---@see lsp.core.env_links
---@see lsp.core.gitsigns_actions

local autocmd = require("lib.nvim.bindings.autocmd")
local links = require("lsp.core.env_links")
local util = require("lsp.core.util")

local api = vim.api

local M = {}

--- The client name, as `:Lsp servers` shows it.
---@type string
M.NAME = util.INTERNAL_PREFIX .. "envlinks"

---@type string
M.GROUP = "lsp_nvim_env_links"

--- How many lines of the target a hover previews.
---@type integer
M.PREVIEW_LINES = 12

---@type boolean
local registered = false

--- The dispatchers of the running in-process server, to ask the client for a
--- diagnostics refresh when a file appears or disappears.
---@type table|nil
local live_dispatchers = nil

---@type boolean
local refresh_pending = false

--- Delay before a refresh is asked for, so a burst of writes is one refresh.
---@type integer
local REFRESH_DELAY_MS = 300

---@internal
--- The loaded buffer holding `uri`, or nil. Looked up by comparing URIs rather
--- than through `vim.uri_to_bufnr`, which *creates* a listed buffer for a name
--- that has none -- a request for a document Neovim does not have open must
--- not make one appear.
---@param uri string
---@return integer|nil
local function loaded_buffer(uri)
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(bufnr) then
      local ok, buf_uri = pcall(vim.uri_from_bufnr, bufnr)
      if ok and buf_uri == uri then
        return bufnr
      end
    end
  end
  return nil
end

---@internal
--- Make text safe to place inside a Markdown code span: a backtick in a link
--- target (which is whatever the document says) would end the span early and
--- let the rest of the hover be formatted by the document's author.
---@param text string
---@return string
local function code_safe(text)
  return (text:gsub("`", "'"))
end

---@internal
--- The env link at an LSP position, resolved.
---
--- LSP columns are UTF-16 code units and `target_at` works in bytes; a German
--- document has an umlaut before the link often enough that mixing the two
--- would miss it.
---@param params table
---@return string|nil target
---@return LspNvim.EnvLink.Resolved|nil resolved
local function link_at(params)
  local uri = params and params.textDocument and params.textDocument.uri
  local pos = params and params.position
  -- A negative line would not be refused by `nvim_buf_get_lines`: -1 is the
  -- last line of the buffer.
  if
    type(uri) ~= "string"
    or type(pos) ~= "table"
    or type(pos.line) ~= "number"
    or pos.line < 0
    or type(pos.character) ~= "number"
    or pos.character < 0
  then
    return nil, nil
  end

  local bufnr = loaded_buffer(uri)
  if not bufnr then
    return nil, nil
  end
  local line = api.nvim_buf_get_lines(bufnr, pos.line, pos.line + 1, false)[1]
  if not line then
    return nil, nil
  end

  local ok, byte = pcall(vim.str_byteindex, line, "utf-16", pos.character)
  local target = links.target_at(line, (ok and byte or pos.character) + 1)
  if not target then
    return nil, nil
  end
  return target, links.resolve(target)
end

--- `textDocument/definition`: the file the link names -- at its heading when
--- the target carries a `#fragment`. nil for anything else, including a link
--- whose file is not there: a location that does not exist is worse than none.
---@param params table
---@return table[]|nil
function M.definition(params)
  local _, resolved = link_at(params)
  if not resolved or not resolved.exists then
    return nil
  end

  local line = 0
  if resolved.fragment and resolved.fragment ~= "" and vim.fn.filereadable(resolved.path) == 1 then
    line = links.heading_line(resolved.path, resolved.fragment) or 0
  end
  local at = { line = line, character = 0 }
  return { { uri = vim.uri_from_fname(resolved.path), range = { start = at, ["end"] = at } } }
end

--- `textDocument/hover`: where the link leads, whether it is there, and the
--- top of the file. Unlike definition it answers for a missing target too --
--- "this is where I looked" is exactly what one hovers a broken link to learn.
---@param params table
---@return table|nil
function M.hover(params)
  local target, resolved = link_at(params)
  if not target or not resolved then
    return nil
  end

  local lines = {
    ("**`%s`**"):format(code_safe(target)),
    "",
    ("%s `%s`"):format(resolved.exists and "->" or "-> (missing)", code_safe(resolved.path)),
  }
  if resolved.exists and vim.fn.isdirectory(resolved.path) == 1 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "_directory_"
  elseif resolved.exists then
    local preview = links.preview(resolved.path, M.PREVIEW_LINES)
    if preview and #preview > 0 then
      lines[#lines + 1] = ""
      lines[#lines + 1] = "---"
      for _, l in ipairs(preview) do
        lines[#lines + 1] = l
      end
    end
  end
  return { contents = { kind = "markdown", value = table.concat(lines, "\n") } }
end

---@internal
--- A byte offset (0-based) in `line` as an LSP column: UTF-16 code units.
---@param line string
---@param byte integer
---@return integer
local function lsp_column(line, byte)
  local ok, col = pcall(vim.str_utfindex, line, "utf-16", byte)
  return ok and col or byte
end

---@internal
--- The problem with one env link, if it has one: a message and a code.
---
--- Nothing is said when the variable is not defined or the file cannot be
--- judged (not Markdown, too large, unreadable): "cannot tell" is not "broken".
---@param resolved LspNvim.EnvLink.Resolved
---@param target string
---@param indexes table<string, LspNvim.EnvLink.HeadingIndex|false>
---@return string|nil message
---@return string|nil code
local function problem(resolved, target, indexes)
  if not resolved.exists then
    return ("Link to non-existent document '%s' (resolved to %s)"):format(target, resolved.path),
      "missing-file"
  end
  if not resolved.fragment or resolved.fragment == "" or not links.is_markdown(resolved.path) then
    return nil, nil
  end
  -- One read per file, however many links point at it.
  local index = indexes[resolved.path]
  if index == nil then
    index = links.heading_index(resolved.path) or false
    indexes[resolved.path] = index
  end
  if index and not links.heading_lookup(index, resolved.fragment) then
    return ("Link to non-existent heading '#%s' in %s"):format(resolved.fragment, resolved.path),
      "missing-heading"
  end
  return nil, nil
end

--- `textDocument/diagnostic`: the env links of the buffer that lead nowhere.
---@param params table
---@return table report # A full `DocumentDiagnosticReport`.
function M.diagnostics(params)
  local items = {}
  local uri = params and params.textDocument and params.textDocument.uri
  local bufnr = type(uri) == "string" and loaded_buffer(uri) or nil
  if bufnr then
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local indexes = {}
    for _, link in ipairs(links.scan(lines)) do
      local resolved = links.resolve(link.target)
      local message, code
      if resolved then
        message, code = problem(resolved, link.target, indexes)
      end
      if message then
        local line = lines[link.lnum + 1]
        items[#items + 1] = {
          range = {
            start = { line = link.lnum, character = lsp_column(line, link.first - 1) },
            ["end"] = { line = link.lnum, character = lsp_column(line, link.last) },
          },
          severity = vim.diagnostic.severity.WARN,
          code = code,
          source = M.NAME,
          message = message,
        }
      end
    end
  end
  return { kind = "full", items = items }
end

--- Is the in-process client running? The marksman diagnostics filter asks:
--- while it is, the client is the one source of env-link diagnostics.
---@return boolean
function M.active()
  for _, client in ipairs(vim.lsp.get_clients({ name = M.NAME })) do
    if not client:is_stopped() then
      return true
    end
  end
  return false
end

---@internal
--- Ask Neovim to pull the diagnostics again (`workspace/diagnostic/refresh`):
--- a link's target can appear or go away without the document changing.
---@return nil
local function refresh_diagnostics()
  if refresh_pending or not live_dispatchers then
    return
  end
  refresh_pending = true
  vim.defer_fn(function()
    refresh_pending = false
    local dispatchers = live_dispatchers
    if dispatchers and dispatchers.server_request then
      pcall(dispatchers.server_request, "workspace/diagnostic/refresh", nil)
    end
  end, REFRESH_DELAY_MS)
end

--- The in-process server, in the shape `vim.lsp.start`'s `cmd` function wants.
---@param dispatchers table
---@return table
function M.server(dispatchers)
  local closing = false
  local exited = false
  local request_id = 0
  local server = {}
  live_dispatchers = dispatchers

  ---@return nil
  local function exit()
    closing = true
    if exited then
      return
    end
    exited = true
    if live_dispatchers == dispatchers then
      live_dispatchers = nil
    end
    dispatchers.on_exit(0, 0)
  end

  ---@param method string
  ---@param params table
  ---@param callback fun(err: table|nil, result: any)
  ---@param notify_reply_callback? fun(message_id: integer)
  ---@return boolean ok
  ---@return integer id
  function server.request(method, params, callback, notify_reply_callback)
    request_id = request_id + 1
    -- A handler that raises would surface as a Lua error in whichever feature
    -- asked -- every `K` and `gd` on that link. Answer it as the LSP error it
    -- is instead.
    local answer = method == "textDocument/definition" and M.definition
      or method == "textDocument/hover" and M.hover
      or method == "textDocument/diagnostic" and M.diagnostics
      or nil
    if method == "initialize" then
      callback(nil, {
        capabilities = {
          definitionProvider = true,
          hoverProvider = true,
          -- Neovim pulls diagnostics after the document was opened or changed
          -- (`LspNotify`), so it must be told about both. The content itself
          -- is read from the buffer, not from the notifications.
          textDocumentSync = { openClose = true, change = 2 },
          diagnosticProvider = {
            identifier = M.NAME,
            interFileDependencies = false,
            workspaceDiagnostics = false,
          },
        },
        serverInfo = { name = M.NAME },
      })
    elseif answer then
      local ok, result = pcall(answer, params)
      if ok then
        callback(nil, result)
      else
        callback({ code = -32603, message = tostring(result) }, nil)
      end
    elseif method == "shutdown" then
      callback(nil, nil)
    else
      callback({ code = -32601, message = "method not supported: " .. method }, nil)
    end
    -- Without this every answered request stays registered as pending on
    -- `client.requests` for good -- one per hover and per `gd`.
    if notify_reply_callback then
      notify_reply_callback(request_id)
    end
    return true, request_id
  end

  ---@param method string
  ---@return boolean
  function server.notify(method)
    if method == "exit" then
      exit()
    end
    return true
  end

  ---@return boolean
  function server.is_closing()
    return closing
  end

  function server.terminate()
    exit()
  end

  return server
end

---@internal
--- Attach the in-process server to a Markdown buffer.
---@param bufnr integer
---@return nil
local function attach(bufnr)
  if not registered or not api.nvim_buf_is_valid(bufnr) then
    return
  end
  -- A scratch/preview buffer has no file whose links could be relative to
  -- anything, and it is the same kind of buffer marksman itself refuses.
  if vim.bo[bufnr].buftype ~= "" or api.nvim_buf_get_name(bufnr) == "" then
    return
  end
  local ft = vim.bo[bufnr].filetype
  if ft ~= "markdown" and ft ~= "markdown.mdx" and ft ~= "mdx" then
    return
  end
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = M.NAME })) do
    if not client:is_stopped() then
      return
    end
  end
  vim.lsp.start({
    name = M.NAME,
    cmd = M.server,
    -- No root: one client serves every Markdown buffer, found again by name
    -- and by an equal (nil) root.
    root_dir = nil,
  }, { bufnr = bufnr })
end

--- Register the autocommand, and attach to the Markdown buffers already open.
---@param opts LspNvim.LanguagesOpts|nil
---@return nil
function M.setup(opts)
  M.detach()
  if opts and opts.env_links == false then
    return
  end
  registered = true

  local group = autocmd.group(M.GROUP, true)
  autocmd.create("FileType", function(args)
    attach(args.buf)
  end, {
    group = group,
    pattern = { "markdown", "markdown.mdx", "mdx" },
    desc = "lsp.nvim: resolve $VAR and ~ Markdown links (definition, hover)",
  })
  -- A link's target can appear or go away without the document changing: a
  -- file written here (`BufWritePost`), or one changed from outside
  -- (`FocusGained`).
  autocmd.create({ "BufWritePost", "FocusGained" }, function()
    refresh_diagnostics()
  end, {
    group = group,
    desc = "lsp.nvim: re-check env links when a file may have appeared or gone",
  })

  vim.schedule(function()
    for _, bufnr in ipairs(api.nvim_list_bufs()) do
      attach(bufnr)
    end
  end)
end

--- Remove the autocommand and stop the in-process client.
---@return nil
function M.detach()
  registered = false
  live_dispatchers = nil
  pcall(api.nvim_del_augroup_by_name, M.GROUP)
  for _, client in ipairs(vim.lsp.get_clients({ name = M.NAME })) do
    client:stop()
  end
end

return M
