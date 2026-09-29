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
  if type(uri) ~= "string" or type(pos) ~= "table" then
    return nil, nil
  end

  local bufnr = vim.uri_to_bufnr(uri)
  if not api.nvim_buf_is_loaded(bufnr) then
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
    ("**`%s`**"):format(target),
    "",
    ("%s `%s`"):format(resolved.exists and "->" or "-> (missing)", resolved.path),
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

--- The in-process server, in the shape `vim.lsp.start`'s `cmd` function wants.
---@param dispatchers table
---@return table
function M.server(dispatchers)
  local closing = false
  local exited = false
  local request_id = 0
  local server = {}

  ---@return nil
  local function exit()
    closing = true
    if exited then
      return
    end
    exited = true
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
    if method == "initialize" then
      callback(nil, {
        capabilities = { definitionProvider = true, hoverProvider = true },
        serverInfo = { name = M.NAME },
      })
    elseif method == "textDocument/definition" then
      callback(nil, M.definition(params))
    elseif method == "textDocument/hover" then
      callback(nil, M.hover(params))
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
  if vim.bo[bufnr].buftype ~= "" then
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
  pcall(api.nvim_del_augroup_by_name, M.GROUP)
  for _, client in ipairs(vim.lsp.get_clients({ name = M.NAME })) do
    client:stop()
  end
end

return M
