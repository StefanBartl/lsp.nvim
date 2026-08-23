---@module 'lsp.tools.deprecated_help.lsp.lua_ls.catch'
--- Diagnostic "catcher" utilities.
--- Responsible for deciding whether a diagnostic is the one of interest,
--- extracting the relevant token/symbol and normalizing detection logic.
---
--- This module is intentionally small and easy to extend (e.g. add
--- additional heuristics, treesitter-based extraction, regex lists, etc.)

local helper = require("lsp.tools.deprecated_help.helper")

local M = {}

---@type string[]
local default_blacklist = {
  [1] = "vim.api.",
  [2] = "vim.fn.",
  [3] = "vim.uv.",
}

--- Escape Lua pattern magic characters
---@param s string
---@return string
local function escape_lua_pattern(s)
  return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

--- Remove all occurrences of blacklist prefixes from a string
---@param s string
---@return string
local function remove_prefix_from_string(s)
  if type(s) ~= "string" then
    return s
  end
  local out = s
  for _, prefix in ipairs(default_blacklist) do
    if prefix ~= "" then
      out = out:gsub(escape_lua_pattern(prefix), "")
    end
  end
  return out
end

-- Try to extract the symbol referenced by the diagnostic.
-- Primary approach: use the diagnostic range text.
-- Secondary: try a small regex inside the message for "Use X instead" patterns.
---@param bufnr number
---@param diag table
---@return string
function M.extract_symbol(bufnr, diag)
  local result = ""

  -- first: try to get text under the diagnostic range
  result = helper.get_text_for_range(bufnr, diag.range)
  if result ~= "" then
    return remove_prefix_from_string(result)
  end

  -- second: try message heuristics, e.g. backticked symbol `foo` or quoted 'foo'
  local msg = diag.message or ""
  result = msg:match("`([^`]+)`") or msg:match("'([^']+)'") or msg:match('"([^"]+)"')
  if result and result ~= "" then
    return remove_prefix_from_string(result)
  end

  -- third: try a simple "use X" pattern
  result = msg:match("[Uu]se%s+([%w%._:]+)")
  if result and result ~= "" then
    return remove_prefix_from_string(result)
  end

  -- nothing useful found
  return ""
end

return M
