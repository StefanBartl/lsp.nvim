---@module 'lsp.usercmds.recovery'
--- LSP error recovery and retry strategies

local M = {}

local lsp = vim.lsp
local notify = require("lib.nvim.notify").create("[LSP.Recovery] ")

---@class RecoveryState
---@field attempts table<string, integer> -- server_name -> attempt count
---@field last_error table<string, string> -- server_name -> error message
local state = {
  attempts = {},
  last_error = {},
}

--- Reset recovery state for a server
---@param name string
local function reset_state(name)
  state.attempts[name] = 0
  state.last_error[name] = nil
end

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

  -- Initialize state
  if not state.attempts[name] then
    state.attempts[name] = 0
  end

  -- Check if max attempts reached
  if state.attempts[name] >= max_attempts then
    notify.error(
      string.format(
        "Max retry attempts (%d) reached for '%s'. Last error: %s",
        max_attempts,
        name,
        state.last_error[name] or "unknown"
      )
    )
    return false
  end

  -- Increment attempt counter
  state.attempts[name] = state.attempts[name] + 1

  notify.info(
    string.format(
      "Attempting to start '%s' (attempt %d/%d)...",
      name,
      state.attempts[name],
      max_attempts
    )
  )

  -- Try to start
  local ok, err = pcall(lsp.enable, { name })

  if not ok then
    state.last_error[name] = tostring(err)

    -- Retry after delay if not max attempts
    if state.attempts[name] < max_attempts then
      vim.defer_fn(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end
        M.retry_start(name, bufnr, max_attempts)
      end, 2000 * state.attempts[name]) -- Progressive delay: 2s, 4s, 6s
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
        string.format("✓ '%s' started successfully on attempt %d", name, state.attempts[name])
      )
      reset_state(name)
    else
      -- Retry if not attached
      if state.attempts[name] < max_attempts then
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
      lsp.stop_client(c.id, true)
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
    reset_state(name) -- Reset retry counter
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
    M.retry_start(name, bufnr, 2) -- Max 2 attempts for auto-recovery
  end
end

return M
