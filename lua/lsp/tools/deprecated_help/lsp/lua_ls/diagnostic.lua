---@module 'lsp.tools.deprecated_help.lsp.lua_ls.diagnostic'
--- `is_deprecated_warning(diag)`: heuristic check whether an LSP diagnostic
--- is lua_ls's own "deprecated" warning -- WARN severity plus the message
--- text containing "deprecated", case-insensitive.

local M = {}

-- Lowercase helper
---@param s string|nil
local function lc(s)
  if not s then
    return ""
  end
  return string.lower(s)
end

-- Determine whether a diagnostic message should be considered a "deprecated" warning.
-- Heuristics:
--  - severity is WARN (or diagnostic.severity == 4 in some servers)
--  - message contains 'deprecated' (case-insensitive)
---@param diag table LSP diagnostic
---@return boolean
function M.is_deprecated_warning(diag)
  if not diag or type(diag.message) ~= "string" then
    return false
  end

  -- accept both numeric and enum-style severities (compatibility)
  local warn_ok = (diag.severity == vim.diagnostic.severity.WARN)
  if not warn_ok then
    return false
  end

  local msg = lc(diag.message)
  if msg:match("deprecated") or msg:match("is deprecated") then
    return true
  end
  return false
end

-- Original
-- Determine if a diagnostic is deprecated
---@param diagnostic table
---@return boolean
function M.is_deprecated(diagnostic)
  if diagnostic.tags ~= nil then
    for _, tag in ipairs(diagnostic.tags) do
      if tag == 1 then
        return true
      end
    end
  end
  if diagnostic.message and string.match(string.lower(diagnostic.message), "deprecated") then
    return true
  end
  return false
end

return M
