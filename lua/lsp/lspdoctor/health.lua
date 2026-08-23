---@module 'lsp.lspdoctor.health'
---@brief Health check for LSP servers

local M = {}

local lsp = vim.lsp

---@param opts table
function M.setup(opts)
  Opts = opts or {}
end

--- Check if server is running for buffer
---@param name string
---@param bufnr integer
---@return boolean
local function is_running(name, bufnr)
  local clients = lsp.get_clients({ bufnr = bufnr, name = name })
  return #clients > 0
end

--- Get expected servers for buffer
---@param bufnr integer
---@return string[]
local function get_expected_servers(bufnr)
  local ok, start_mod = pcall(require, "lsp.usercmds.start")
  if not ok then
    return {}
  end

  if type(start_mod.get_servers_for_buffer) == "function" then
    return start_mod.get_servers_for_buffer(bufnr)
  end

  return {}
end

--- Check if config exists
---@param name string
---@return boolean
local function config_exists(name)
  if type(lsp.config) ~= "table" or not lsp.config.get then
    return false
  end

  local configs = lsp.config.get() or {}
  for _, cfg in pairs(configs) do
    if cfg.name == name then
      return true
    end
  end
  return false
end

--- Get server state/attempts
---@param name string
---@return integer attempts, string|nil last_error
local function get_server_state(name)
  local ok, state_mod = pcall(require, "lsp.usercmds.state")
  if not ok or type(state_mod.state) ~= "table" then
    return 0, nil
  end

  local state = state_mod.state
  local attempts = (state.attempts and state.attempts[name]) or 0
  local last_error = (state.last_error and state.last_error[name]) or nil

  return attempts, last_error
end

--- Perform health check
---@param bufnr integer
---@return string[] lines, table results
function M.check(bufnr)
  local lines = {}
  local results = {}

  local expected = get_expected_servers(bufnr)

  if #expected == 0 then
    table.insert(lines, "⚠️  No LSP servers configured for this buffer")
    table.insert(lines, "   Filetype: " .. vim.bo[bufnr].filetype)
    return lines, results
  end

  for _, name in ipairs(expected) do
    local running = is_running(name, bufnr)
    local has_config = config_exists(name)
    local attempts, last_error = get_server_state(name)

    table.insert(results, {
      name = name,
      running = running,
      config_exists = has_config,
      attempts = attempts,
      last_error = last_error,
    })

    -- Build status line
    table.insert(lines, "")
    table.insert(lines, string.format("**%s**", name))
    table.insert(lines, string.format("  Running: %s", running and "✅ Yes" or "❌ No"))
    table.insert(lines, string.format("  Config: %s", has_config and "✅ Yes" or "❌ No"))
    table.insert(lines, string.format("  Attempts: %d", attempts))

    if last_error then
      table.insert(lines, string.format("  Error: `%s`", last_error))
    end

    -- Diagnostic hints
    if not running then
      if not has_config then
        table.insert(
          lines,
          "  💡 **Action**: Server not configured - check `lsp.config` or registry"
        )
      elseif attempts > 0 then
        table.insert(lines, "  💡 **Action**: Start failed - check `:LspLog` or `:messages`")
      else
        table.insert(lines, "  💡 **Action**: Not started - use `:LspStart " .. name .. "`")
      end
    end
  end

  -- Summary
  local running_count = 0
  for _, r in ipairs(results) do
    if r.running then
      running_count = running_count + 1
    end
  end

  table.insert(lines, 1, "")
  table.insert(lines, 1, string.format("Summary: %d/%d servers running", running_count, #expected))
  table.insert(lines, 1, string.rep("─", 50))

  return lines, results
end

return M
