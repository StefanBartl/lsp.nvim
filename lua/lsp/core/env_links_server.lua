---@module 'lsp.core.env_links_server'
---@brief Definition, hover, diagnostics and path completion for `$VAR/...` and `~/...` Markdown links.
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
--- **Completion.** marksman completes relative paths in a link, never an env
--- one. While a target is typed -- `[x]($REPOS_DIR/no`, `[x](${VAR}/`,
--- `[x](~/`, `![i](...`, `[l]: ...` -- the client answers `textDocument/completion`
--- with the entries of the directory typed so far (folders first, dotfiles only
--- when a dot is typed, a blank or parenthesis percent-encoded in a bare target
--- and left alone inside `<...>`), and for a `$` or `${` with the variables that
--- name a directory (never a secret, never a network share). Everywhere else it
--- answers `nil`, in code blocks and code spans too. Any completion engine that
--- asks the LSP clients (blink, cmp, `omnifunc`) gets it with no wiring.
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
--- The loaded buffer, the line (0-based number and text) and the byte column
--- (1-based) an LSP position names; nil for a position that names none.
---
--- LSP columns are UTF-16 code units and the scanners work in bytes; a German
--- document has an umlaut before the link often enough that mixing the two
--- would miss it.
---@param params table
---@return integer|nil bufnr
---@return integer|nil lnum
---@return string|nil line
---@return integer|nil col
local function buffer_position(params)
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
    return nil
  end

  local bufnr = loaded_buffer(uri)
  if not bufnr then
    return nil
  end
  local line = api.nvim_buf_get_lines(bufnr, pos.line, pos.line + 1, false)[1]
  if not line then
    return nil
  end

  local ok, byte = pcall(vim.str_byteindex, line, "utf-16", pos.character)
  return bufnr, pos.line, line, (ok and byte or pos.character) + 1
end

---@internal
--- The env link at an LSP position, resolved.
---@param params table
---@return string|nil target
---@return LspNvim.EnvLink.Resolved|nil resolved
local function link_at(params)
  local bufnr, _, line, col = buffer_position(params)
  if not bufnr or not line or not col then
    return nil, nil
  end
  local target = links.target_at(line, col)
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
    "",
  }
  -- "Where it leads" is the one thing a hover is for; the path is shown only
  -- when it is one (see `links.displayable_path`), and "not checked" when the
  -- disk was not asked (a network path).
  local arrow = resolved.exists == nil and "-> (not checked)"
    or resolved.exists and "->"
    or "-> (missing)"
  local shown = links.displayable_path(resolved.path)
  lines[3] = shown and ("%s `%s`"):format(arrow, code_safe(shown)) or arrow
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

--- Time one pull may spend on `fs_stat`, in nanoseconds. Past it the links not
--- yet looked at are "cannot tell" until the next pull.
---@type integer
local STAT_BUDGET_NS = 50 * 1000 * 1000

--- How many different files one pull builds a heading index for.
---@type integer
M.MAX_INDEXED_FILES = 32

--- How many different files one pull looks at for a heading at all: a lookup
--- costs a `realpath` and a `stat` even when the cache answers.
---@type integer
M.MAX_LOOKED_UP_FILES = 128

--- Time one pull may spend building heading indexes, in nanoseconds. Past it a
--- file is answered from the cache or not at all, until the next pull. It stops
--- the pull from *starting* builds, it does not interrupt one. (One build
--- is up to about half a second for a 2 MB file; the cap on files alone let 32
--- of them run in one synchronous pull.)
---@type integer
M.INDEX_BUDGET_NS = 250 * 1000 * 1000

---@internal
--- A `stat` for `links.resolve` that looks at each path once per pull, spends at
--- most `STAT_BUDGET_NS` in `fs_stat` itself (not on scanning or indexing), and
--- does not touch a network path (`//host/share`,
--- `\\host\share`) at all. A stat on one that does not answer blocks Neovim
--- for the OS connect timeout (21 s measured) and no budget interrupts a call
--- that is already blocked; it would also come back "not there" and be reported
--- as a broken link. nil from it means "not looked at".
---@return fun(path: string): boolean|nil
local function pull_stat()
  local seen = {} ---@type table<string, boolean|"unknown">
  local spent = 0 -- nanoseconds spent inside fs_stat so far
  return function(path)
    local known = seen[path]
    if known == "unknown" then
      return nil
    elseif known ~= nil then
      return known --[[@as boolean]]
    end
    if links.is_network_path(path) or spent > STAT_BUDGET_NS then
      seen[path] = "unknown"
      return nil
    end
    local t0 = vim.uv.hrtime()
    local on_disk = vim.uv.fs_stat(path) ~= nil
    spent = spent + (vim.uv.hrtime() - t0)
    seen[path] = on_disk
    return on_disk
  end
end

local quoted = links.quoted

---@internal
--- The problem with one env link, if it has one: a message and a code.
---
--- Nothing is said when the variable is not defined or the file cannot be
--- judged (not Markdown, too large, unreadable, not looked at): "cannot tell"
--- is not "broken".
---@param resolved LspNvim.EnvLink.Resolved
---@param target string
---@param indexes table # `{ files, looked, spent }` and one index (or `false`) per path.
---@param stat? fun(path: string): boolean|nil
---@return string|nil message
---@return string|nil code
local function problem(resolved, target, indexes, stat)
  if resolved.exists == nil then
    return nil, nil
  end
  if not resolved.exists then
    return ("Link to non-existent document '%s'%s"):format(
      quoted(target),
      links.looked_up_at(resolved.path, stat)
    ),
      "missing-file"
  end
  if not resolved.fragment or resolved.fragment == "" or not links.is_markdown(resolved.path) then
    return nil, nil
  end
  -- One look per file, however many links point at it (and `heading_index`
  -- keeps what it built for the next pull).
  local index = indexes[resolved.path]
  if index == nil then
    -- Only a read and a parse costs: past the cap a file is answered from the
    -- cache or not at all, and a cache hit is not charged.
    if indexes.looked >= M.MAX_LOOKED_UP_FILES then
      return nil, nil -- cannot tell
    end
    indexes.looked = indexes.looked + 1
    local over = indexes.files >= M.MAX_INDEXED_FILES or indexes.spent > M.INDEX_BUDGET_NS
    local t0 = vim.uv.hrtime()
    local built, cached = links.heading_index(resolved.path, over)
    if built and not cached then
      indexes.files = indexes.files + 1
      indexes.spent = indexes.spent + (vim.uv.hrtime() - t0)
    end
    index = built or false
    indexes[resolved.path] = index
  end
  if index and not links.heading_lookup(index, resolved.fragment) then
    return ("Link to non-existent heading '#%s' in %s"):format(
      quoted(resolved.fragment),
      quoted(resolved.path)
    ),
      "missing-heading"
  end
  return nil, nil
end

--- `textDocument/diagnostic`: the env links of the buffer that lead nowhere.
---@param params table
---@return table report # A full `DocumentDiagnosticReport`.
function M.diagnostics(params)
  local items = {}
  local failure ---@type string|nil
  local uri = params and params.textDocument and params.textDocument.uri
  local bufnr = type(uri) == "string" and loaded_buffer(uri) or nil
  if bufnr then
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local indexes = { files = 0, looked = 0, spent = 0 }
    local opts = { stat = pull_stat() }
    for _, link in ipairs(links.scan(lines)) do
      -- One link that makes the code raise must not take the report of every
      -- other link with it.
      local ok, message, code = pcall(function()
        local resolved = links.resolve(link.target, opts)
        if resolved then
          return problem(resolved, link.target, indexes, opts.stat)
        end
      end)
      if not ok then
        failure = failure or ("%s: %s"):format(quoted(link.target), tostring(message))
      elseif message then
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
  if failure then
    -- The links that failed are skipped, not hidden: the first error is in
    -- `:LspLog`.
    pcall(vim.lsp.log.error, M.NAME .. ": env link check failed: " .. failure)
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

--- Most items one completion answers with. Past it the answer says it is
--- incomplete, and the editor asks again with more typed.
---@type integer
M.MAX_COMPLETION_ITEMS = 300

--- Most directory entries one completion looks at.
---@type integer
M.MAX_COMPLETION_SCAN = 5000

---@type integer
local KIND_VARIABLE, KIND_FILE, KIND_FOLDER = 6, 17, 19

---@internal
--- `name` as it goes into a link target: a bare target ends at a blank or an
--- unbalanced parenthesis and `#` starts a fragment, so those are
--- percent-encoded (the resolver decodes them). In `<...>` nothing is.
---@param name string
---@param angled boolean
---@return string
local function target_text(name, angled)
  if angled then
    return name
  end
  return (name:gsub("[%s()#%%<>]", function(c)
    return ("%%%02X"):format(c:byte())
  end))
end

---@internal
--- Is `path` a directory that may be looked at: not a network path (a stat on
--- one that does not answer blocks Neovim), and there.
---@param path string
---@return boolean
local function is_directory(path)
  if links.is_network_path(path) then
    return false
  end
  local st = vim.uv.fs_stat(path)
  return st ~= nil and st.type == "directory"
end

---@internal
--- The environment variables that name a directory, as completion items, for a
--- `$` or `${` and the letters typed after it. Only names whose value is an
--- existing directory are offered (a secret in the environment is not one), and
--- `$NVIM_CONFIG_DIR`, which has no real variable behind it.
---@param typing LspNvim.EnvLink.Typing
---@param lnum integer
---@param line string
---@param col integer
---@return table[]|nil
local function variable_items(typing, lnum, line, col)
  local braced = typing.text:sub(2, 2) == "{"
  local prefix = (braced and typing.text:sub(3) or typing.text:sub(2)):lower()

  local names = {} ---@type table<string, string>
  for name, value in pairs(vim.fn.environ()) do
    if name:lower():find(prefix, 1, true) == 1 then
      names[name] = value
    end
  end
  if ("nvim_config_dir"):find(prefix, 1, true) == 1 and names.NVIM_CONFIG_DIR == nil then
    names.NVIM_CONFIG_DIR = vim.fn.stdpath("config")
  end

  local range = {
    start = { line = lnum, character = lsp_column(line, typing.start - 1) },
    ["end"] = { line = lnum, character = lsp_column(line, col - 1) },
  }
  local items = {}
  for name, value in pairs(names) do
    if is_directory(value) then
      local label = braced and ("${" .. name .. "}") or ("$" .. name)
      items[#items + 1] = {
        label = label,
        kind = KIND_VARIABLE,
        detail = (value:gsub("\\", "/")),
        sortText = name:lower(),
        filterText = label,
        textEdit = { newText = label .. "/", range = range },
      }
    end
  end
  table.sort(items, function(a, b)
    return a.sortText < b.sortText
  end)
  return items
end

---@internal
--- The entries of the directory a `$VAR/dir/` target names, as completion items,
--- for what is typed after its last slash.
---@param typing LspNvim.EnvLink.Typing
---@param lnum integer
---@param line string
---@param col integer
---@return table[]|nil items
---@return boolean|nil incomplete
local function path_items(typing, lnum, line, col)
  local dir, partial = typing.text:match("^(.*/)([^/]*)$")
  if not dir or typing.text:find("#", 1, true) then
    return nil, nil -- no slash yet, or a fragment: headings are not completed here
  end
  local resolved = links.resolve(dir)
  if not resolved or not resolved.exists or not is_directory(resolved.path) then
    return nil, nil
  end

  local handle = vim.uv.fs_scandir(resolved.path)
  if not handle then
    return nil, nil
  end
  local want = vim.uri_decode(partial):lower()
  local show_hidden = want:sub(1, 1) == "."
  local range = {
    start = { line = lnum, character = lsp_column(line, typing.start - 1 + #dir) },
    ["end"] = { line = lnum, character = lsp_column(line, col - 1) },
  }

  local items, scanned, incomplete = {}, 0, false
  while true do
    local name, kind = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    scanned = scanned + 1
    if scanned > M.MAX_COMPLETION_SCAN or #items >= M.MAX_COMPLETION_ITEMS then
      incomplete = true
      break
    end
    if
      (show_hidden or name:sub(1, 1) ~= ".")
      and name:lower():find(want, 1, true) == 1
      and not name:find("[%c]")
    then
      local is_dir = kind == "directory"
      if kind == "link" then
        is_dir = is_directory(resolved.path .. "/" .. name)
      end
      local text = target_text(name, typing.angled) .. (is_dir and "/" or "")
      items[#items + 1] = {
        label = name .. (is_dir and "/" or ""),
        kind = is_dir and KIND_FOLDER or KIND_FILE,
        sortText = (is_dir and "0" or "1") .. name:lower(),
        filterText = target_text(name, typing.angled),
        textEdit = { newText = text, range = range },
      }
    end
  end
  -- Folders first, then by name: the order the directory happens to be read in
  -- is the file system's.
  table.sort(items, function(a, b)
    return a.sortText < b.sortText
  end)
  return items, incomplete
end

--- `textDocument/completion`: the directories a `$VAR/`, `${VAR}/` or `~/` link
--- target names -- marksman completes relative paths only -- and, for a `$` or
--- `${`, the variables that name one. nil everywhere else (in code too), so for
--- an ordinary link marksman's answer stands alone.
---@param params table
---@return table|nil
function M.completion(params)
  local bufnr, lnum, line, col = buffer_position(params)
  if not bufnr or not lnum or not line or not col then
    return nil
  end
  local typing = links.typing_at(line, col)
  if not typing then
    return nil
  end
  -- Not in a code span or a code block: there it is text.
  if links.mask_code_spans(line):sub(typing.start, col - 1) ~= line:sub(typing.start, col - 1) then
    return nil
  end
  if links.fenced_at(api.nvim_buf_get_lines(bufnr, 0, -1, false), lnum + 1) then
    return nil
  end

  local items, incomplete
  if typing.text:match("^%$[%w_]*$") or typing.text:match("^%${[%w_]*$") then
    items = variable_items(typing, lnum, line, col)
  elseif links.is_env_target(typing.text) then
    items, incomplete = path_items(typing, lnum, line, col)
  end
  if not items or #items == 0 then
    return nil
  end
  return { isIncomplete = incomplete == true, items = items }
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
      or method == "textDocument/completion" and M.completion
      or nil
    if method == "initialize" then
      callback(nil, {
        capabilities = {
          definitionProvider = true,
          hoverProvider = true,
          completionProvider = { triggerCharacters = { "/", "$", "{" }, resolveProvider = false },
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
  -- Neovim pulls after a change only for buffers that are shown (`LspNotify`
  -- -> `_refresh` with `only_visible`), and marksman's own message about a
  -- broken env link is dropped for a buffer this client is attached to: a
  -- loaded buffer that is first shown later has to be pulled once then. (The
  -- refresh request is the one way to ask that does not disturb Neovim's own
  -- pull bookkeeping: a `client:request` of ours here left stale diagnostics.)
  autocmd.create("BufWinEnter", function(args)
    if #vim.lsp.get_clients({ bufnr = args.buf, name = M.NAME }) > 0 then
      refresh_diagnostics()
    end
  end, {
    group = group,
    -- No name pattern: `attach` decides by filetype, and so does the check above.
    desc = "lsp.nvim: pull env-link diagnostics when a loaded Markdown buffer is first shown",
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
    -- Neovim clears a client's pulled diagnostics when the last pull-capable
    -- client leaves a buffer; with another one attached they would stay.
    local ok, ns = pcall(vim.lsp.diagnostic.get_namespace, client.id, true, M.NAME)
    if ok then
      for bufnr in pairs(client.attached_buffers or {}) do
        vim.diagnostic.reset(ns, bufnr)
      end
    end
    client:stop()
  end
  links.clear_cache()
end

return M
