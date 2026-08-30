---@module 'lsp.usercmds.stop'
--- LspStopHere command implementation

local M = {}

local notify = require("lib.nvim.notify").create("[LSP.Stop] ")
local supervisor = require("lsp.core.supervisor")
local lsp = vim.lsp

--- Get clients attached to buffer
---@param bufnr integer|nil
---@return vim.lsp.Client[]
local function get_buffer_clients(bufnr)
  return lsp.get_clients({ bufnr = bufnr or 0 })
end

--- Gracefully stop a client, then force-stop it if it does not go down.
---
--- Fully asynchronous: the graceful shutdown request is fired immediately and a
--- libuv timer polls for the client to disappear. The previous implementation
--- polled with `vim.wait(100)` inside a `while` loop, which blocked the UI
--- thread for up to `timeout_ms` (3s) per client — with several clients
--- attached that froze Neovim for multiple seconds.
---@param client_id integer
---@param timeout_ms integer|nil
---@param on_done fun(success: boolean)|nil called on the main loop when settled
---@return nil
local function graceful_stop(client_id, timeout_ms, on_done)
  timeout_ms = timeout_ms or 3000

  -- Declared up front, and it covers both paths below: the graceful shutdown
  -- exits 0, but the force-stop fallback sends SIGTERM, which the supervisor
  -- cannot tell from a crash. Stopping a server must not restart it.
  supervisor.expect_stop(client_id)

  local function finish(success)
    if on_done then
      vim.schedule(function()
        on_done(success)
      end)
    end
  end

  -- Request graceful shutdown
  local ok = pcall(lsp.stop_client, client_id, false) -- false = graceful

  if not ok then
    -- Force stop if graceful fails
    pcall(lsp.stop_client, client_id, true)
    finish(false)
    return
  end

  local deadline = vim.uv.now() + timeout_ms
  local timer = vim.uv.new_timer()
  if not timer then
    -- No timer handle available: fall back to a single deferred force-stop.
    vim.defer_fn(function()
      local client = lsp.get_client_by_id(client_id)
      if client and not client.is_stopped() then
        pcall(lsp.stop_client, client_id, true)
      end
      finish(client == nil)
    end, timeout_ms)
    return
  end

  local done = false

  local function close_timer()
    done = true
    timer:stop()
    if not timer:is_closing() then
      timer:close()
    end
  end

  timer:start(50, 50, function()
    -- lsp.get_client_by_id touches Neovim state: only valid on the main loop,
    -- so the poll body is scheduled. `done` guards against a second scheduled
    -- body running after the timer was already closed.
    vim.schedule(function()
      if done then
        return
      end

      local client = lsp.get_client_by_id(client_id)

      if (not client) or client.is_stopped() then
        close_timer()
        finish(true)
      elseif vim.uv.now() >= deadline then
        close_timer()
        pcall(lsp.stop_client, client_id, true)
        finish(false)
      end
    end)
  end)
end

--- Execute LspStopHere command
---@param args table vim.api.nvim_create_user_command args
---@return nil
function M.execute(args)
  local bufnr = 0

  if args.args and args.args ~= "" then
    -- Stop specific server
    local clients = get_buffer_clients(bufnr)
    local found = false

    for _, c in ipairs(clients) do
      if c.name == args.args then
        graceful_stop(c.id)
        found = true
        notify.info(string.format("Stopped LSP: %s", args.args))
        break
      end
    end

    if not found then
      notify.warn(string.format("LSP '%s' not running", args.args))
    end
  else
    -- Stop all servers
    local ids = {}
    for _, c in ipairs(get_buffer_clients(bufnr)) do
      ids[#ids + 1] = c.id
    end

    if #ids > 0 then
      for _, id in ipairs(ids) do
        graceful_stop(id)
      end
      notify.info(string.format("Stopped %d LSP client(s)", #ids))
    else
      notify.info("No LSP clients running")
    end
  end
end

return M
