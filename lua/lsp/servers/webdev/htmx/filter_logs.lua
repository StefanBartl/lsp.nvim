---@module 'lsp.servers.webdev.htmx.filter_logs'
--- Filtert JSON-Logs aus LSP-Server stderr basierend auf Log-Level.
--- Verhindert, dass INFO/DEBUG-Logs als [ERROR] in Neovim's LSP-Log erscheinen.

local M = {}

---Parse JSON log line and extract level
---@param line string JSON log line
---@return string|nil level "INFO", "DEBUG", "WARN", "ERROR" or nil if not parsable
local function extract_log_level(line)
  if not line or type(line) ~= "string" then
    return nil
  end

  -- Try to extract "level":"LEVEL" from JSON
  local level = line:match('"level"%s*:%s*"(%u+)"')
  return level
end

---Create stderr handler that filters logs by level
---@param opts { ignore_levels?: string[], server_name?: string }|nil
---@return function handler Function compatible with LSP handlers
function M.create_handler(opts)
  opts = opts or {}
  local ignore_levels = opts.ignore_levels or { "INFO", "DEBUG" }
  local server_name = opts.server_name or "LSP"

  -- Convert ignore list to set for O(1) lookup
  local ignore_set = {}
  for _, level in ipairs(ignore_levels) do
    ignore_set[level] = true
  end

  ---@param err any
  ---@param chunk string|nil
  ---@param ctx table|nil
  ---@return nil
  ---@diagnostic disable-next-line: unused-local
  return function(err, chunk, ctx)
    if not chunk or chunk == "" then
      return
    end

    -- Extract log level from JSON
    local level = extract_log_level(chunk)

    -- If we should ignore this level, skip it
    if level and ignore_set[level] then
      return
    end

    -- For non-ignored logs, still log them (but not as popup)
    -- This keeps real errors visible in :messages and LSP log file
    if level == "ERROR" or level == "WARN" then
      -- Log to LSP log file (appears in :lua vim.cmd('e ' .. vim.lsp.get_log_path()))
      vim.schedule(function()
        local msg = string.format("[%s] %s", server_name, chunk:gsub("\\n", " "))
        -- Write to vim messages (accessible via :messages)
        vim.api.nvim_echo({ { msg, "WarningMsg" } }, false, {})
      end)
    end
  end
end

---Create default filter for common JSON-logging LSP servers
---@param server_name string Name for logging context
---@return function handler
function M.create_json_filter(server_name)
  return M.create_handler({
    ignore_levels = { "INFO", "DEBUG" },
    server_name = server_name,
  })
end

---Create strict filter that only shows ERROR
---@param server_name string Name for logging context
---@return function handler
function M.create_strict_filter(server_name)
  return M.create_handler({
    ignore_levels = { "INFO", "DEBUG", "WARN" },
    server_name = server_name,
  })
end

return M
