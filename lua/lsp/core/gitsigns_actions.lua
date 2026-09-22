---@module 'lsp.core.gitsigns_actions'
---@brief gitsigns' hunk actions, offered in the code-action list.
---@description
--- With the cursor in a changed hunk, `lsa` lists "Stage hunk", "Reset hunk" and
--- "Preview hunk" next to whatever the language servers offer. lspsaga did this
--- with `code_action.extend_gitsigns`; the picker that replaced it (fzf-lua's)
--- has no such hook, so the actions arrive the way every other code action
--- does: from a language server.
---
--- The server is a small **in-process** one -- `cmd` is a Lua function, so
--- there is no process, no stdio and no install -- that answers exactly two
--- requests: `initialize`, and `textDocument/codeAction`, for which it asks
--- gitsigns whether the range touches a hunk. The actions are `Command`s with
--- client-side handlers (`config.commands`), which is where Neovim looks
--- before it would send `workspace/executeCommand` anywhere.
---
--- **Cursor or selection.** At the cursor the actions act on the hunk under it.
--- Over a selection they act on the selection: *Stage* and *Reset* on the lines
--- in it (the range travels in the command's arguments, because the picker runs
--- the command after the selection is gone), *Preview* -- which takes no range --
--- on the first hunk the selection touches.
---
--- **Why the kind is `refactor.gitsigns`.** The code-action indicator
--- (`lsp.core.lightbulb`) lights on `quickfix` and `source` and treats an action
--- with no kind as a match. A hunk action is neither a fix nor a source
--- action, and giving it a kind outside the allowlist keeps the bulb from being
--- lit on every changed line.
---
--- **What it costs.** One more client in `vim.lsp.get_clients()` and in
--- `:Lsp servers`, attached to buffers gitsigns is attached to. That is why it
--- is `code_actions.gitsigns = false` by default. It advertises nothing but
--- `codeActionProvider`, so no other feature sends it anything -- but every
--- feature that asks "is a client attached" sees it, which is what
--- `lsp.core.util.server_clients` is for: it is named `lsp.nvim-*`, and the
--- winbar guard and `:Lsp stop` / `:Lsp restart` look past clients so named.
---
--- **Its exit is its own to report.** A client with no process is never told by
--- a dying process that it has gone; Neovim drops it from `get_clients()` only
--- on `on_exit`. `terminate()` (`Client:stop(true)`, and the fallback after a
--- failed shutdown) therefore reports the exit itself, exactly as the graceful
--- `exit` notification does.
---
---@see lsp.bindings.actions
---@see lsp.core.lightbulb

local autocmd = require("lib.nvim.bindings.autocmd")
local util = require("lsp.core.util")

local api = vim.api

local M = {}

--- The client name, as `:Lsp servers` shows it.
---@type string
M.NAME = util.INTERNAL_PREFIX .. "gitsigns"

---@type string
M.GROUP = "lsp_nvim_gitsigns_actions"

--- What an action is run for. Both fields are nil for a request at the cursor,
--- which is what gitsigns' own actions default to acting on.
---@class LspGitsigns.RunContext
---@field range? integer[] # `{ first, last }`, 1-based: the selection the action was offered for.
---@field bufnr? integer # The buffer it was offered for.

---@class LspGitsigns.Action
---@field id string
---@field title string
---@field run fun(gs: table, ctx: LspGitsigns.RunContext)

---@type boolean
local registered = false

--- `hunk_spans(bufnr)`'s answer as of the last `GitSignsUpdate` for that
--- buffer -- gitsigns fires it exactly when the hunks change, so that is the
--- only moment the spans need rebuilding. A missing entry (not yet updated
--- once, or the buffer is gone) falls back to computing it live.
---@type table<integer, integer[][]|nil>
local hunk_spans_cache = {}

---@internal
---@return table|nil
local function gitsigns()
  local ok, gs = pcall(require, "gitsigns")
  return ok and gs or nil
end

--- The 0-based, inclusive line span of each hunk of a buffer, as gitsigns
--- reports them; `nil` when gitsigns cannot say.
---
--- A hunk covers the lines it added; one that only removed lines covers the
--- single line the removal sits on, which is where gitsigns draws its sign.
---
--- That line is `added.start` -- except at the two ends of the file, where
--- gitsigns' own `find_hunk` and its signs bend the rule and so does this: a
--- deletion above the first line is `start == 0` and belongs to line 1, one
--- after the last is `start == line_count + 1` and belongs to the last line.
---@internal
---@param bufnr integer
---@return integer[][]|nil
local function compute_hunk_spans(bufnr)
  local gs = gitsigns()
  if gs == nil or type(gs.get_hunks) ~= "function" then
    return nil
  end
  local ok, hunks = pcall(gs.get_hunks, bufnr)
  if not ok or type(hunks) ~= "table" then
    return nil
  end
  local line_count = api.nvim_buf_is_valid(bufnr) and api.nvim_buf_line_count(bufnr) or 1
  ---@type integer[][]
  local spans = {}
  for _, hunk in ipairs(hunks) do
    local added = hunk.added
    if added then
      -- 1-based in gitsigns, 0-based here.
      local from = added.start - 1
      if added.count == 0 then
        from = math.min(math.max(from, 0), line_count - 1)
      end
      spans[#spans + 1] = { from, from + math.max(added.count, 1) - 1 }
    end
  end
  return spans
end

---@internal
---@param bufnr integer
---@return integer[][]|nil
local function hunk_spans(bufnr)
  local cached = hunk_spans_cache[bufnr]
  if cached ~= nil then
    return cached
  end
  return compute_hunk_spans(bufnr)
end

--- The 0-based line range `[first, last]`'s first line that lies in a hunk: the
--- hunk's own first line, or `first` when the hunk starts above the range.
--- `nil` when the range touches no hunk.
---@param bufnr integer
---@param first integer
---@param last integer
---@return integer|nil
function M.first_touched(bufnr, first, last)
  for _, span in ipairs(hunk_spans(bufnr) or {}) do
    if last >= span[1] and first <= span[2] then
      return math.max(span[1], first)
    end
  end
  return nil
end

--- Does the 0-based line range `[first, last]` touch a hunk of the buffer?
---@param bufnr integer
---@param first integer
---@param last integer
---@return boolean
function M.touches_hunk(bufnr, first, last)
  return M.first_touched(bufnr, first, last) ~= nil
end

---@type LspGitsigns.Action[]
M.ACTIONS = {
  {
    id = "stage_hunk",
    title = "Stage hunk",
    -- A range stages the lines in it (gitsigns' `:'<,'>Gitsigns stage_hunk`);
    -- none stages the hunk under the cursor.
    run = function(gs, ctx)
      gs.stage_hunk(ctx.range)
    end,
  },
  {
    id = "reset_hunk",
    title = "Reset hunk",
    run = function(gs, ctx)
      gs.reset_hunk(ctx.range)
    end,
  },
  {
    id = "preview_hunk",
    title = "Preview hunk",
    -- Preview takes no range: it shows the hunk under the cursor. For a
    -- selection the cursor is wherever the selection ended, which may be in no
    -- hunk at all, so it goes to the first hunk the selection touches -- but
    -- only in the window that shows the buffer the action was offered for.
    run = function(gs, ctx)
      if ctx.range and ctx.bufnr and api.nvim_get_current_buf() == ctx.bufnr then
        local line = M.first_touched(ctx.bufnr, ctx.range[1] - 1, ctx.range[2] - 1)
        if line then
          pcall(api.nvim_win_set_cursor, 0, { line + 1, 0 })
        end
      end
      gs.preview_hunk()
    end,
  },
}

--- Is this range a selection, as against the cursor? A request at the cursor
--- has the same start and end.
---@internal
---@param range table
---@return boolean
local function is_selection(range)
  return range.start.line ~= range["end"].line or range.start.character ~= range["end"].character
end

--- The `CodeAction`s for a `textDocument/codeAction` request.
---
--- For a selection the commands carry it (`{ first, last }`, 1-based): the
--- picker runs them after it has closed, when the selection is gone and the
--- cursor is wherever the selection ended. A request at the cursor carries
--- nothing, because gitsigns then acts on the hunk under the cursor -- a range
--- of one line would stage that line rather than the hunk.
---@param params table
---@return table[]
function M.code_actions(params)
  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
  local range = params.range
  if not range or not M.touches_hunk(bufnr, range.start.line, range["end"].line) then
    return {}
  end

  ---@type table[]|nil
  local arguments = nil
  if is_selection(range) then
    arguments = { { first = range.start.line + 1, last = range["end"].line + 1 } }
  end

  ---@type table[]
  local out = {}
  for _, action in ipairs(M.ACTIONS) do
    out[#out + 1] = {
      title = "gitsigns: " .. action.title,
      kind = "refactor.gitsigns",
      command = {
        title = action.title,
        command = "lsp_nvim.gitsigns." .. action.id,
        arguments = arguments,
      },
    }
  end
  return out
end

---@internal
--- The client-side handlers for the actions' commands.
---@return table<string, fun(command: table, ctx: table)>
local function commands()
  ---@type table<string, fun(command: table, ctx: table)>
  local out = {}
  for _, action in ipairs(M.ACTIONS) do
    out["lsp_nvim.gitsigns." .. action.id] = function(command, ctx)
      local gs = gitsigns()
      if gs then
        local offered = type(command) == "table"
            and type(command.arguments) == "table"
            and command.arguments[1]
          or nil
        ---@type LspGitsigns.RunContext
        local run_ctx = { bufnr = type(ctx) == "table" and ctx.bufnr or nil }
        if
          type(offered) == "table"
          and type(offered.first) == "number"
          and type(offered.last) == "number"
        then
          run_ctx.range = { offered.first, offered.last }
        end
        -- Scheduled: the picker that ran the action is still closing, and
        -- gitsigns acts on the *current* buffer and cursor.
        vim.schedule(function()
          action.run(gs, run_ctx)
        end)
      end
    end
  end
  return out
end

--- The in-process server, in the shape `vim.lsp.start`'s `cmd` function wants.
---@param dispatchers table
---@return table
function M.server(dispatchers)
  local closing = false
  local exited = false
  local request_id = 0
  local server = {}

  --- Tell Neovim the client is gone, once. The code is 0 with no signal: a clean
  --- exit, which the supervisor does not read as a crash to bring back.
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
  ---@param notify_reply_callback? fun(message_id: integer) # Called once the reply is out.
  ---@return boolean ok
  ---@return integer id
  function server.request(method, params, callback, notify_reply_callback)
    request_id = request_id + 1
    if method == "initialize" then
      callback(nil, {
        capabilities = { codeActionProvider = true },
        serverInfo = { name = M.NAME },
      })
    elseif method == "textDocument/codeAction" then
      callback(nil, M.code_actions(params))
    elseif method == "shutdown" then
      callback(nil, nil)
    else
      -- MethodNotFound. The server advertised one capability; anything else
      -- is somebody assuming too much.
      callback({ code = -32601, message = "method not supported: " .. method }, nil)
    end
    -- Neovim tells a request that was answered before `request` returned from
    -- one still pending by this callback. Without it every request stays
    -- registered as pending on `client.requests` for good -- one per code-action
    -- query, and the code-action indicator asks on every CursorHold.
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
--- Attach the in-process server to a buffer gitsigns is attached to.
---@param bufnr integer
---@return nil
local function attach(bufnr)
  if not registered or not api.nvim_buf_is_valid(bufnr) then
    return
  end
  if vim.bo[bufnr].buftype ~= "" or vim.b[bufnr].gitsigns_status_dict == nil then
    return
  end
  -- A client that has been asked to stop is not "attached": it is on its way
  -- out, and `vim.lsp.start` will not reuse it either.
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = M.NAME })) do
    if not client:is_stopped() then
      return
    end
  end
  vim.lsp.start({
    name = M.NAME,
    cmd = M.server,
    commands = commands(),
    -- No root: one client serves every buffer, found again by name and by an
    -- equal (nil) root.
    root_dir = nil,
  }, { bufnr = bufnr })
end

--- Register the handlers, and attach to the buffers gitsigns already has.
---@param opts LspNvim.CodeActionsOpts|nil
---@return nil
function M.setup(opts)
  M.detach()
  if not (opts and opts.gitsigns) then
    return
  end
  registered = true

  local group = autocmd.group(M.GROUP, true)
  -- gitsigns fires `GitSignsUpdate` whenever it has (re)computed a buffer's
  -- hunks, with the buffer in `data.buffer`; the first one for a buffer is the
  -- moment it becomes attached. Also the only moment the cached spans need
  -- rebuilding -- everything between two updates asks the cache instead of
  -- gitsigns.
  autocmd.create("User", function(args)
    local bufnr = type(args.data) == "table" and args.data.buffer or api.nvim_get_current_buf()
    hunk_spans_cache[bufnr] = compute_hunk_spans(bufnr)
    attach(bufnr)
  end, {
    group = group,
    pattern = "GitSignsUpdate",
    desc = "lsp.nvim: offer gitsigns hunk actions as code actions",
  })

  -- A buffer that is gone will not fire another GitSignsUpdate to replace its
  -- entry, so it would otherwise sit in the cache for the rest of the session.
  autocmd.create({ "BufDelete", "BufWipeout" }, function(args)
    hunk_spans_cache[args.buf] = nil
  end, {
    group = group,
    desc = "lsp.nvim: drop the cached hunk spans of a buffer that is gone",
  })

  vim.schedule(function()
    for _, bufnr in ipairs(api.nvim_list_bufs()) do
      attach(bufnr)
    end
  end)
end

--- Remove the handlers and stop the in-process client.
---@return nil
function M.detach()
  registered = false
  pcall(api.nvim_del_augroup_by_name, M.GROUP)
  hunk_spans_cache = {}
  for _, client in ipairs(vim.lsp.get_clients({ name = M.NAME })) do
    client:stop()
  end
end

return M
