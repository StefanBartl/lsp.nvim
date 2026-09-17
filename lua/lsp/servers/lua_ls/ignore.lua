---@module 'lsp.servers.lua_ls.ignore'
--- Shared ignore configuration for filesystem scanning and LSP workspace settings.
--- This module centralizes ignore entries so multiple consumers (e.g. scan/prune
--- routines and language-server configuration) reuse the same canonical list.
---
--- The module exposes:
--- 1. `names()` -> string[] : raw directory basenames for path-level checks (fast set style).
--- 2. `as_set()` -> table<string, boolean> : a set keyed by basename for O(1) membership tests.
--- 3. `as_luals_patterns()` -> string[] : converted glob patterns suitable for `Lua.workspace.ignoreDir`.
--- 4. `normalize_for_platform(str)` helper to normalize separators / case if needed.
---
--- Notes:
--- - Comments in code are in English as requested.
--- - This module does textual normalization only; it does not perform IO.

local sys_env = require("lib.nvim.system.env")

local M = {}

--- Raw list of directory names commonly ignored.
--- These are loaded from a centralized ignore list module.
---
--- `basenames`, not `as_luals_patterns()`. The shared list's
--- `as_luals_patterns()` already returns both spellings of every entry --
--- `.git` *and* `**/.git`, 62 strings for 31 directories -- and this module
--- treated that output as if it were raw basenames. Measured consequences:
--- `names()` returned 62 entries, 31 of them globs, against a docstring that
--- promises "raw directory basenames"; `as_set()` carried 31 dead `**/name`
--- keys that no basename can ever equal; and `as_luals_patterns()` below
--- doubled the list again into 124 patterns -- 31 exact duplicates and 31
--- `**/**/name`. `basenames` is the 31-entry array those spellings are
--- derived from.
---
--- Copied rather than aliased so `names()`'s promise that callers cannot
--- mutate the internal list also covers the shared module's table.
--- @type string[]
M._names = (function()
  local list = require("lib.nvim.fs.ignore.list")
  local out = {}

  if type(list.basenames) == "table" then
    for i = 1, #list.basenames do
      out[i] = list.basenames[i]
    end
    return out
  end

  -- Fallback for an older shared list that exposes only the pattern form:
  -- strip the `**/` prefix and drop the duplicate each name then produces.
  local seen = {}
  for _, p in ipairs(list.as_luals_patterns and list.as_luals_patterns() or {}) do
    local name = p:gsub("^%*%*/", "")
    if not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  return out
end)()

--- Platform-normalize a name for consistent comparisons (no filesystem IO).
--- On Windows this lower-cases strings for case-insensitive comparison.
--- On Unix-like systems, names are compared case-sensitively.
--- Also strips trailing slashes and collapses repeated separators.
--- @param s string String to normalize
--- @return string Normalized string
local function normalize_for_platform(s)
  -- Guard against non-string input
  if type(s) ~= "string" then
    return s
  end

  -- Remove trailing path separators (both / and \)
  s = s:gsub("[/\\]+$", "")

  -- On Windows, lower-case for case-insensitive comparison
  if sys_env.get().is_windows then
    s = s:lower()
  end

  return s
end

--- Return a copy of the base names list.
--- Creates a new array so callers can't accidentally mutate the internal list.
--- @return string[] Array of ignore directory names
function M.names()
  local out = {}
  -- Copy each entry to a new table
  for i = 1, #M._names do
    out[i] = M._names[i]
  end
  return out
end

--- Return a set keyed by normalized basename for fast membership checks.
--- This enables O(1) lookups like: if ignore_set["node_modules"] then ... end
--- Example: set["node_modules"] == true
--- @return table<string, boolean> Set of ignore directory names
function M.as_set()
  local t = {}
  -- Convert each name to normalized form and add to set
  for _, n in ipairs(M._names) do
    t[normalize_for_platform(n)] = true
  end
  return t
end

--- Convert base names into glob patterns for lua_ls workspace.ignoreDir.
--- lua_ls expects patterns like "**/node_modules" to ignore any nested occurrences.
--- We produce two patterns per name for robustness:
---   1. "**/name" - matches the directory at any depth
---   2. "name" - matches the directory at root level
--- This ensures both root-level and nested directories are ignored.
--- @return string[] Array of glob patterns for lua_ls
function M.as_luals_patterns()
  local out = {}

  -- Convert each ignore name to lua_ls glob patterns
  for _, n in ipairs(M._names) do
    local norm = normalize_for_platform(n)

    -- Pattern 1: Ignore at any depth in the project
    out[#out + 1] = "**/" .. norm

    -- Pattern 2: Also explicitly ignore at root level
    -- Some configurations interpret patterns root-relatively
    out[#out + 1] = norm
  end

  return out
end

return M
