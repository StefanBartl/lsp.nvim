---@module 'lsp.config.unknown'
---@brief Finds option keys in a user layer that `DEFAULTS` does not know.
---@description
--- `config/init.lua` merges layers with `vim.tbl_deep_extend`, which keeps
--- every key it is handed, so a misspelled option (`mason.ensure_installing`
--- for `mason.ensure_install`) sits in the resolved config looking as if it
--- took while doing nothing. The value validators in `config/init.lua` only
--- judge *known* keys; this module covers the other half.
---
--- The walk is driven off `DEFAULTS` rather than a hand-written list, for the
--- reason `config_spec.lua` asserts the set of numeric options instead of
--- spelling it: a list written by hand drifts. It descends only where
--- `DEFAULTS` holds a *struct* (a table with named fields). It stops, and
--- reports nothing below, at
---
--- * a list (`servers`, `lightbulb.kinds`, `workspace.markers`, ...),
--- * an empty default table (`inlay_hints.filetypes`, `keymaps.map`, ...) --
---   an empty default is how a free-form map is spelled,
--- * the paths in `FREE_FORM`, which are maps whose defaults are not empty.
---
--- Pure: no `vim.notify`, no state. The caller decides what a finding costs.
---
---@see lsp.config
---@see lsp.config.DEFAULTS

local M = {}

--- Maps with a non-empty default, where the user may add keys of their own.
---@type table<string, true>
local FREE_FORM = {
  ["winbar.max_symbols"] = true,
  ["implement.kinds"] = true,
  ["peek.keys"] = true,
  ["mason.overrides"] = true,
}

--- Fields whose default is `nil`, so they are absent from `DEFAULTS` although
--- they are real options.
---@type table<string, true>
local NIL_DEFAULT = {
  ["completion.personal_names.labels"] = true,
}

--- Levenshtein distance, bounded: gives up above `limit`.
---@param a string
---@param b string
---@param limit integer
---@return integer
local function distance(a, b, limit)
  if math.abs(#a - #b) > limit then
    return limit + 1
  end
  local prev = {}
  for j = 0, #b do
    prev[j] = j
  end
  for i = 1, #a do
    local cur = { [0] = i }
    local row_min = i
    for j = 1, #b do
      local cost = a:sub(i, i) == b:sub(j, j) and 0 or 1
      cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
      row_min = math.min(row_min, cur[j])
    end
    if row_min > limit then
      return limit + 1
    end
    prev = cur
  end
  return prev[#b]
end

--- The nearest known key within a small edit distance, or nil.
---@param key string
---@param known string[]
---@return string|nil
local function suggest(key, known)
  local limit = math.max(1, math.floor(#key / 3))
  local best, best_d = nil, limit + 1
  for _, candidate in ipairs(known) do
    local d = distance(key, candidate, limit)
    if d < best_d then
      best, best_d = candidate, d
    end
  end
  return best
end

---@param tbl table
---@return boolean
local function is_struct(tbl)
  return type(tbl) == "table" and next(tbl) ~= nil and not vim.islist(tbl)
end

---@param defaults table
---@param path string # Dotted path of `defaults`, "" at the root.
---@return string[]
local function known_keys(defaults, path)
  local out = {}
  for k in pairs(defaults) do
    out[#out + 1] = tostring(k)
  end
  for nil_path in pairs(NIL_DEFAULT) do
    local prefix, leaf = nil_path:match("^(.*)%.([^.]+)$")
    if prefix == path then
      out[#out + 1] = leaf
    end
  end
  table.sort(out)
  return out
end

---@param layer table
---@param defaults table
---@param path string
---@param found { path: string, suggestion: string|nil }[]
local function walk(layer, defaults, path, found)
  local known = known_keys(defaults, path)
  local keys = {}
  for k in pairs(layer) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  for _, key in ipairs(keys) do
    local name = tostring(key)
    local full = path == "" and name or (path .. "." .. name)
    local default = defaults[key]
    if default == nil and not NIL_DEFAULT[full] then
      found[#found + 1] = { path = full, suggestion = suggest(name, known) }
    elseif type(layer[key]) == "table" and is_struct(default) and not FREE_FORM[full] then
      walk(layer[key], default, full, found)
    end
  end
end

--- Unknown keys of one layer, sorted by path.
---@param layer table|nil # A user layer: the `setup()` options or a project file's data.
---@param defaults table # `lsp.config.DEFAULTS`.
---@return { path: string, suggestion: string|nil }[]
function M.scan(layer, defaults)
  local found = {}
  if type(layer) == "table" then
    walk(layer, defaults, "", found)
  end
  return found
end

--- The warning text for one finding.
---@param finding { path: string, suggestion: string|nil }
---@param label string # Layer label, as in `source_of`.
---@return string
function M.message(finding, label)
  local hint = finding.suggestion ~= nil and (' -- did you mean "%s"?'):format(finding.suggestion)
    or ""
  return ("%s: unknown option, ignored by every consumer%s (from %s)"):format(
    finding.path,
    hint,
    label
  )
end

return M
