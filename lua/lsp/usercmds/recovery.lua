---@module 'lsp.usercmds.recovery'
--- LSP error recovery and retry strategies -- starting a server that should be
--- running and is not.
---
--- The counterpart to `lsp.core.supervisor`, which handles the other
--- direction: a server that *was* running and died. The split is by trigger,
--- not by mechanism -- this one is asked (`:Lsp recover`, `:Lsp
--- force-restart`), that one notices.
---
--- The attempt counter lives in the supervisor, not here. It used to live in a
--- file-local table in this module while `lspdoctor/health.lua` read one from
--- `lsp.usercmds.state`, a module that has never existed -- so the "Attempts:
--- N" line in `:LspDoctor startup` was always 0, and the "start failed" hint
--- it gates could never fire. One owner now, and the report reads from it.
---
--- **Starting goes through `supervisor.start`, not `vim.lsp.enable`**, and
--- that distinction is the whole reason `:Lsp force-restart` never worked.
--- `vim.lsp.enable` arms an autocommand: it launches a client the next time a
--- matching buffer event fires. After a force-restart the buffer is already
--- open and no such event is coming, so the client was never created, the
--- attach poll 1500ms later found nothing, and the retry called the same
--- ineffective function two more times before giving up with "Try :edit".
--- `supervisor.start` resolves the registered config and calls
--- `vim.lsp.start(cfg, { bufnr })`, which attaches to the buffer in hand --
--- the same fix that `:Lsp restart` got.

local M = {}

local lsp = vim.lsp
local notify = require("lib.nvim.notify").create("[LSP.Recovery] ")
local supervisor = require("lsp.core.supervisor")

--- Check if server is running
---@param name string
---@param bufnr integer|nil
---@return boolean
local function is_running(name, bufnr)
  for _, c in ipairs(lsp.get_clients({ bufnr = bufnr or 0 })) do
    if c.name == name then
      return true
    end
  end
  return false
end

--- Attempt to start server with retry logic
---@param name string
---@param bufnr integer
---@param max_attempts integer|nil
---@return boolean success
function M.retry_start(name, bufnr, max_attempts)
  max_attempts = max_attempts or 3
  bufnr = bufnr or 0

  -- A name with no registered configuration cannot be started by trying
  -- again. Answered before the counter moves, so a typo costs one message
  -- instead of three attempts and six seconds of delays.
  if supervisor.config_for(name) == nil then
    supervisor.note_error(name, "no registered configuration")
    notify.error(string.format("No registered LSP configuration for '%s'", name))
    return false
  end

  -- Check if max attempts reached
  if supervisor.attempts(name) >= max_attempts then
    notify.error(
      string.format(
        "Max retry attempts (%d) reached for '%s'. Last error: %s",
        max_attempts,
        name,
        supervisor.last_error(name) or "unknown"
      )
    )
    return false
  end

  local attempt = supervisor.note_attempt(name)

  notify.info(
    string.format("Attempting to start '%s' (attempt %d/%d)...", name, attempt, max_attempts)
  )

  -- Start AND attach to this buffer. See the module doc for why it is not
  -- `vim.lsp.enable`.
  if not supervisor.start(name, bufnr) then
    supervisor.note_error(name, "vim.lsp.start refused the configuration")

    -- Retry after delay if not max attempts
    if attempt < max_attempts then
      vim.defer_fn(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end
        M.retry_start(name, bufnr, max_attempts)
      end, 2000 * attempt) -- Progressive delay: 2s, 4s, 6s
    end

    return false
  end

  -- Check if attached
  vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    if is_running(name, bufnr) then
      notify.info(
        string.format(
          "✓ '%s' started successfully on attempt %d",
          name,
          supervisor.attempts(name)
        )
      )
      supervisor.reset(name)
    else
      -- Retry if not attached
      if supervisor.attempts(name) < max_attempts then
        notify.warn(string.format("'%s' not attached, retrying...", name))
        M.retry_start(name, bufnr, max_attempts)
      else
        notify.error(
          string.format(
            "Failed to attach '%s' after %d attempts. Try :edit or check :LspLog",
            name,
            max_attempts
          )
        )
      end
    end
  end, 1500)

  return true
end

--- Force-restart server with cleanup
---@param name string
---@param bufnr integer|nil
---@return boolean success
function M.force_restart(name, bufnr)
  bufnr = bufnr or 0

  -- Find and stop all instances
  local stopped_ids = {}
  for _, c in ipairs(lsp.get_clients({ bufnr = bufnr })) do
    if c.name == name then
      stopped_ids[#stopped_ids + 1] = c.id
      -- Declared before the stop, not after: a force-stop sends SIGTERM, which
      -- on the way out is indistinguishable from a crash. Without this the
      -- supervisor would race this function to restart the same server.
      supervisor.expect_stop(c.id)
      c:stop(true)
    end
  end

  if #stopped_ids == 0 then
    notify.info(string.format("'%s' not running, starting fresh", name))
    return M.retry_start(name, bufnr, 1)
  end

  notify.info(string.format("Stopped %d instance(s) of '%s'", #stopped_ids, name))

  -- Wait for cleanup, then start
  vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    supervisor.reset(name) -- Reset retry counter
    M.retry_start(name, bufnr, 3)
  end, 500)

  return true
end

---- Auto-recover: start all missing servers for current filetype
---@param bufnr integer|nil
function M.auto_recover(bufnr)
  if not bufnr then
    notify.notify("[lsp.usrcmds.recovery] bufnr is nil", vim.log.levels.WARN)
    return nil
  end
  local ok, health = pcall(require, "lsp.lspdoctor.health")
  if not ok then
    notify.error("lsp.lspdoctor.health not available, cannot auto-recover")
    return nil
  end

  local _, results = health.check(bufnr)
  local to_start = {}

  for _, status in ipairs(results) do
    if status.config_exists and not status.running then
      table.insert(to_start, status.name)
    end
  end

  if #to_start == 0 then
    notify.info("All expected LSP servers are running")
    return
  end

  notify.info(string.format("Auto-recovery: starting %d server(s)...", #to_start))

  for _, name in ipairs(to_start) do
    -- Clear the history first, the same way `force_restart` does, and for the
    -- same reason: this is someone asking for a retry *now*. The counter is
    -- shared with `lsp.core.supervisor`, so a server that crash-looped until
    -- the supervisor gave up arrives here well past any cap -- and the guard
    -- in `retry_start` would refuse to make a single attempt, in exactly the
    -- situation this command exists for.
    supervisor.reset(name)
    M.retry_start(name, bufnr, 2) -- Max 2 attempts for auto-recovery
  end
end

return M
