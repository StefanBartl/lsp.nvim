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
--- **Why the kind is `refactor.gitsigns`.** The code-action indicator
--- (`lsp.core.lightbulb`) lights on `quickfix` and `source` and treats an action
--- with no kind as a match. A hunk action is neither a fix nor a source
--- action, and giving it a kind outside the allowlist keeps the bulb from being
--- lit on every changed line.
---
--- **What it costs.** One more client in `vim.lsp.get_clients()` and in
--- `:Lsp servers`, attached to buffers gitsigns is attached to. That is why it
--- is `code_actions.gitsigns = false` by default. It advertises nothing but
--- `codeActionProvider`, so no other feature sends it anything.
---
---@see lsp.bindings.actions
---@see lsp.core.lightbulb

local autocmd = require("lib.nvim.bindings.autocmd")

local api = vim.api

local M = {}

--- The client name, as `:Lsp servers` shows it.
---@type string
M.NAME = "lsp.nvim-gitsigns"

---@type string
M.GROUP = "lsp_nvim_gitsigns_actions"

---@class LspGitsigns.Action
---@field id string
---@field title string
---@field run fun(gs: table)

---@type LspGitsigns.Action[]
M.ACTIONS = {
  {
    id = "stage_hunk",
    title = "Stage hunk",
    run = function(gs)
      gs.stage_hunk()
    end,
  },
  {
    id = "reset_hunk",
    title = "Reset hunk",
    run = function(gs)
      gs.reset_hunk()
    end,
  },
  {
    id = "preview_hunk",
    title = "Preview hunk",
    run = function(gs)
      gs.preview_hunk()
    end,
  },
}

---@type boolean
local registered = false

---@internal
---@return table|nil
local function gitsigns()
  local ok, gs = pcall(require, "gitsigns")
  return ok and gs or nil
end

--- Does the 0-based line range `[first, last]` touch a hunk of the buffer?
---
--- A hunk covers the lines it added; one that only removed lines covers the
--- single line the removal sits on, which is where gitsigns draws its sign.
---
--- That line is `added.start` -- except at the two ends of the file, where
--- gitsigns' own `find_hunk` and its signs bend the rule and so does this: a
--- deletion above the first line is `start == 0` and belongs to line 1, one
--- after the last is `start == line_count + 1` and belongs to the last line.
---@param bufnr integer
---@param first integer
---@param last integer
---@return boolean
function M.touches_hunk(bufnr, first, last)
  local gs = gitsigns()
  if gs == nil or type(gs.get_hunks) ~= "function" then
    return false
  end
  local ok, hunks = pcall(gs.get_hunks, bufnr)
  if not ok or type(hunks) ~= "table" then
    return false
  end
  local line_count = api.nvim_buf_is_valid(bufnr) and api.nvim_buf_line_count(bufnr) or 1
  for _, hunk in ipairs(hunks) do
    local added = hunk.added
    if added then
      -- 1-based in gitsigns, 0-based here.
      local from = added.start - 1
      if added.count == 0 then
        from = math.min(math.max(from, 0), line_count - 1)
      end
      local to = from + math.max(added.count, 1) - 1
      if last >= from and first <= to then
        return true
      end
    end
  end
  return false
end

--- The `CodeAction`s for a `textDocument/codeAction` request.
---@param params table
---@return table[]
function M.code_actions(params)
  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
  local range = params.range
  if not range or not M.touches_hunk(bufnr, range.start.line, range["end"].line) then
    return {}
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
    out["lsp_nvim.gitsigns." .. action.id] = function()
      local gs = gitsigns()
      if gs then
        -- Scheduled: the picker that ran the action is still closing, and
        -- gitsigns acts on the *current* buffer and cursor.
        vim.schedule(function()
          action.run(gs)
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
  local request_id = 0
  local server = {}

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
      dispatchers.on_exit(0, 0)
    end
    return true
  end

  ---@return boolean
  function server.is_closing()
    return closing
  end

  function server.terminate()
    closing = true
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
  if #vim.lsp.get_clients({ bufnr = bufnr, name = M.NAME }) > 0 then
    return
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
  -- moment it becomes attached.
  autocmd.create("User", function(args)
    local bufnr = type(args.data) == "table" and args.data.buffer or api.nvim_get_current_buf()
    attach(bufnr)
  end, {
    group = group,
    pattern = "GitSignsUpdate",
    desc = "lsp.nvim: offer gitsigns hunk actions as code actions",
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
  for _, client in ipairs(vim.lsp.get_clients({ name = M.NAME })) do
    client:stop()
  end
end

return M
