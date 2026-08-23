---@module 'lsp.tools.lsp_signature.show_hover'
--- Request hover from one or multiple LSP clients and display it in a floating preview.
--- Accepts either a single client object or a list (array) of clients.
--- If given multiple clients, it queries them in order and shows the first hover result
--- that yields displayable lines. Operations are asynchronous; the function schedules UI
--- updates and uses an optional callback to notify when a floating preview was created.
---
--- Return value: boolean indicating that at least one request was scheduled (not that a preview was necessarily shown).
local M = {}

local open_floating_preview = require("lsp.tools.lsp_signature.open_floating_preview")
local format_hover = require("lsp.tools.lsp_signature.format_hover")
local state = require("lsp.tools.lsp_signature.state")
local api = vim.api
local schedule = vim.schedule

--- Internal single-client handler creator.
--- Calls the client and invokes `on_result` when result processed (true if preview shown).
---@param client table # Unused
---@param params table # Unused
---@param opts table|nil
---@param on_result fun(shown: boolean)
---@diagnostic disable-next-line: unused-local
local function make_client_request_handler(_client, _params, opts, on_result)
  opts = opts or {}
  local mode = opts.mode
  local callback = opts.callback

  return function(_, result)
    if not result then
      -- no hover result for this client
      schedule(function()
        -- Do not notify here to avoid spamming when multiple clients are queried.
      end)
      on_result(false)
      return
    end

    local lines = format_hover(result)
    if not lines or #lines == 0 then
      schedule(function()
        -- no displayable lines for this client
      end)
      on_result(false)
      return
    end

    schedule(function()
      local buf, win = open_floating_preview(lines)
      state.set(buf, win)
      if mode == "n" and win and api.nvim_win_is_valid(win) then
        api.nvim_set_current_win(win)
      end
      if callback and buf and win then
        callback(buf, win)
      end
      on_result(true)
    end)
  end
end

--- send request to a single client (safely)
---@param client table
---@param params table
---@param opts table|nil
---@param on_result fun(shown: boolean)
local function request_one_client(client, params, opts, on_result)
  local handler = make_client_request_handler(client, params, opts, on_result)
  -- protect the request call; some clients may disconnect
  pcall(
    client.request,
    client,
    "textDocument/hover",
    params,
    handler,
    vim.api.nvim_get_current_buf()
  )
end

--- show_hover accepts either:
---   - client: single client object
---   - clients: table/array of client objects
--- opts:
---   - mode: "n" or nil
---   - callback: fun(buf,win) optional callback
--- Returns true when at least one request was scheduled.
---@param client_or_clients table|table[]
---@param params table
---@param opts table|nil
---@return boolean
function M.show_hover(client_or_clients, params, opts)
  opts = opts or {}
  ---@type table[]
  local clients

  -- normalize to list of clients
  if client_or_clients == nil then
    return false
  end
  if
    type(client_or_clients) == "table"
    and #client_or_clients > 0
    and client_or_clients[1] ~= nil
    and type(client_or_clients[1]) == "table"
  then
    clients = client_or_clients
  else
    clients = { client_or_clients }
  end

  local scheduled_any = false
  local ci = 1

  -- recursive iterator over clients: try next client when current yields nothing
  local function try_next_client()
    local client = clients[ci]
    ci = ci + 1
    if not client then
      -- exhausted clients without showing hover
      return
    end

    scheduled_any = true
    -- on_result will be called with true when a preview was shown, false otherwise
    local function on_result(shown)
      if shown then
        -- stop further attempts
        return
      else
        -- try next client
        try_next_client()
      end
    end

    -- fire request for this client
    request_one_client(client, params, opts, on_result)
  end

  try_next_client()

  return scheduled_any
end

return M
