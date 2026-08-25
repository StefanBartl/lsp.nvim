---@module 'lsp.diagnostics.util'
--- Shared helper utilities for diagnostics modules.

local M = {}

--- The severity words offered as completion candidates.
---
--- Canonical spellings only. `to_severity` also accepts the short aliases
--- (`err`/`e`, `warning`/`w`, `i`, `h`) and still will -- they stay typeable,
--- they just don't clutter a five-item completion list with eleven entries.
---@type string[]
M.SEVERITY_TOKENS = { "all", "error", "warn", "info", "hint" }

--- Convert user-facing severity input into vim.diagnostic.severity.
---
--- Lenient by design: this is the internal coercion used by `to_loc`/`to_qf`,
--- which accept `severity` from Lua callers as a string, an integer, or nil.
--- Unknown input maps to nil, i.e. "no filter". Command-line input goes
--- through `parse_severity` first so that a typo is reported rather than
--- silently widened to every severity.
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

--- Validate command-line severity input.
---
--- Distinct from `to_severity` because the two failure modes differ. For a
--- Lua caller, "unknown severity" and "no severity" can reasonably collapse
--- into nil. On the command line they must not: `:DiagLoc eror` would
--- otherwise list *every* diagnostic and look like it worked, which is the
--- opposite of what the typo asked for.
---@param s string|nil
---@return integer|nil severity # nil means "all severities", not "invalid"
---@return string|nil err # set when `s` is not a recognized severity word
function M.parse_severity(s)
  if s == nil or s == "" then
    return nil, nil
  end
  local sev = M.to_severity(s)
  if sev == nil and s:lower() ~= "all" then
    return nil, ("unknown severity '%s' (expected one of: %s)"):format(s, table.concat(M.SEVERITY_TOKENS, ", "))
  end
  return sev, nil
end

--- Completion for a severity argument.
---@param arg_lead string
---@return string[]
function M.complete_severity(arg_lead)
  return vim.tbl_filter(function(tok)
    return tok:sub(1, #arg_lead) == arg_lead
  end, M.SEVERITY_TOKENS)
end

return M
