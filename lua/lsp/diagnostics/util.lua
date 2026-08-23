---@module 'lsp.diagnostics.util'
--- Shared helper utilities for diagnostics modules.

local M = {}

--- Convert user-facing severity input into vim.diagnostic.severity.
---@param s string|integer|nil
---@return integer|nil
function M.to_severity(s)
  if type(s) == "number" then
    return s
  end
  if type(s) ~= "string" then
    return nil
  end

  local v = s:lower()
  if v == "" or v == "all" then
    return nil
  end
  if v == "error" or v == "err" or v == "e" then
    return vim.diagnostic.severity.ERROR
  end
  if v == "warn" or v == "warning" or v == "w" then
    return vim.diagnostic.severity.WARN
  end
  if v == "info" or v == "i" then
    return vim.diagnostic.severity.INFO
  end
  if v == "hint" or v == "h" then
    return vim.diagnostic.severity.HINT
  end
  return nil
end

return M
