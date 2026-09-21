---@module 'lsp.usercmds.stop'
--- LspStopHere command implementation

local M = {}

local notify = require("lib.nvim.notify").create("[LSP.Stop] ")
local supervisor = require("lsp.core.supervisor")
local util = require("lsp.core.util")
local lsp = vim.lsp

--- Language servers attached to buffer. lsp.nvim's own in-process clients are
--- not among them: "stop everything" counted a client the user never asked
--- about, and it re-attaches by itself on the next gitsigns update anyway.
---@param bufnr integer|nil
---@return vim.lsp.Client[]
local function get_buffer_clients(bufnr)
  return util.server_clients(bufnr or 0)
end

--- Gracefully stop a client, then force-stop it if it does not go down.
---
--- Fully asynchronous: the graceful shutdown request is fired immediately and a
--- libuv timer polls for the client to disappear. The previous implementation
--- polled with `vim.wait(100)` inside a `while` loop, which blocked the UI
--- thread for up to `timeout_ms` (3s) per client — with several clients
--- attached that froze Neovim for multiple seconds.
---
--- Everything here goes through the client object rather than
--- `vim.lsp.stop_client()` and `client.is_stopped()`, both deprecated on
--- Neovim 0.12. The poll is why it mattered more than tidiness: the dot-call
--- sat in a 50ms timer, so stopping one client printed the deprecation notice
--- on a loop. `Client:stop()` and `Client:is_stopped()` are methods since
--- 0.11, which is this plugin's minimum.
---
--- What the poll asks is `lsp.get_client_by_id(id) == nil`, not
--- `client:is_stopped()`. `is_stopped()` means "shutdown has been requested",
--- not "the process is gone": measured on 0.12.2 against a stub server that
--- never answers `shutdown`, `is_stopped()` flipped to true in the same tick
--- as `client:stop(false)` and stayed true, while the client was still in
--- `get_clients()` six seconds later. Asking it here made the first 50ms tick
--- report success for every client, which made the deadline and the
--- force-stop below unreachable code -- a server that ignores `shutdown` was
--- left attached forever and `:Lsp stop` said it had stopped it.
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

  local client = lsp.get_client_by_id(client_id)
  if client == nil then
    -- Already gone. `vim.lsp.stop_client` swallowed an unknown id silently and
    -- the poll below would have reported success on its first tick; say so
    -- directly rather than spending a timer to discover it.
    finish(true)
    return
  end

  -- Request graceful shutdown
  local ok = pcall(function()
    client:stop(false) -- false = graceful
  end)

  if not ok then
    -- Force stop if graceful fails
    pcall(function()
      client:stop(true)
    end)
    finish(false)
    return
  end

  local deadline = vim.uv.now() + timeout_ms
  local timer = vim.uv.new_timer()
  if not timer then
    -- No timer handle available: fall back to a single deferred force-stop.
    vim.defer_fn(function()
      -- Re-read rather than closing over the handle above: the client may have
      -- gone in the meantime, and a stale object is not something to call.
      local live = lsp.get_client_by_id(client_id)
      if live then
        pcall(function()
          live:stop(true)
        end)
      end
      finish(live == nil)
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

      local live = lsp.get_client_by_id(client_id)

      if not live then
        close_timer()
        finish(true)
      elseif vim.uv.now() >= deadline then
        close_timer()
        pcall(function()
          live:stop(true)
        end)
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

  if util.is_internal_name(args.args) then
    notify.info(
      string.format(
        "'%s' is lsp.nvim's own in-process client, not a language server; turn it off with code_actions.gitsigns = false",
        args.args
      )
    )
    return
  end

  if args.args and args.args ~= "" then
    -- Stop specific server -- every client carrying that name, not the first
    -- one found. A name is not unique: two clients can share it (a second root
    -- directory, a config reloaded while the old client was still attached).
    -- The loop used to `break`, so with two `dup` clients on one buffer the
    -- command reported "Stopped LSP: dup" and left the second one attached
    -- (measured: `dup#1 dup#2` before, `dup#2` after).
    local stopped = 0

    for _, c in ipairs(get_buffer_clients(bufnr)) do
      if c.name == args.args then
        graceful_stop(c.id)
        stopped = stopped + 1
      end
    end

    if stopped == 0 then
      notify.warn(string.format("LSP '%s' not running", args.args))
    elseif stopped == 1 then
      notify.info(string.format("Stopped LSP: %s", args.args))
    else
      notify.info(string.format("Stopped %d instance(s) of LSP: %s", stopped, args.args))
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
