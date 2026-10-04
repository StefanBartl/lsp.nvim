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
--- * the paths in `FREE_FORM`, which are maps whose defaults are not empty, or
---   (`diagnostics`) tables that are only partly ours: the rest is handed to
---   `vim.diagnostic.config()` and is a legitimate, documented override.
---
--- A key that `DEFAULTS` cannot list because its default is `nil`
--- (`completion.personal_names.labels`) is carved out in `NIL_DEFAULT`. Any
--- option a consumer reads must be in `DEFAULTS` or in one of those two tables,
--- or a valid config is blamed for it.
---
--- The key text comes from the user's layers, and a `.nvim-lsp.json` in a
--- cloned repository is one of them, so it is data, not a message: `message()`
--- escapes control characters and truncates, and `messages()` caps how many
--- findings one layer can turn into warnings.
---
--- Pure: no `vim.notify`, no state. The caller decides what a finding costs.
---
---@see lsp.config
---@see lsp.config.DEFAULTS

local M = {}

--- How many findings of one layer become warnings; the rest is one summary line.
M.MAX_PER_LAYER = 20

--- Longest key path echoed into a warning.
local MAX_PATH = 80

--- Longest warning that is kept whole. Warnings are built from what a layer
--- supplied (key names, values, paths), so none is allowed to be unbounded.
--- Generous: the longest legitimate warning measured, a refused-key line with
--- a deep checkout path, is well under half of it.
M.MAX_WARNING = 1000

--- Maps with a non-empty default, where the user may add keys of their own.
---@type table<string, true>
local FREE_FORM = {
  ["winbar.max_symbols"] = true,
  ["implement.kinds"] = true,
  ["peek.keys"] = true,
  ["mason.overrides"] = true,
  -- Only `ui` and `debounce_ms` are ours; everything else is a
  -- `vim.diagnostic.config()` option that `core.diagnostics.apply` merges last.
  ["diagnostics"] = true,
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
  -- A suggestion costs a bounded edit distance against every known key, and
  -- `messages()` only ever prints the first `MAX_PER_LAYER` findings, so the
  -- rest is not worth computing -- a file of 100k junk keys stays cheap.
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
      found[#found + 1] = {
        path = full,
        suggestion = #found < M.MAX_PER_LAYER and suggest(name, known) or nil,
      }
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

--- Make text of unknown origin safe to put in a warning: control characters
--- (a newline breaks the scratch buffer `:Lsp status` writes into, an escape
--- sequence reaches the terminal through `:checkhealth`) become `\xNN`, and
--- anything longer than `max` bytes is cut, on a character boundary.
---@param text string
---@param max integer
---@return string
function M.sanitize(text, max)
  -- Cut before escaping: escaping never shortens, so `max + 1` raw bytes are
  -- enough to decide the cut, and a multi-megabyte key is not walked in full.
  if #text > max + 1 then
    text = text:sub(1, max + 1)
  end
  text = text:gsub("%c", function(c)
    return ("\\x%02x"):format(c:byte())
  end)
  if #text > max then
    local cut = max - 3
    -- Never inside a multi-byte character: step back while the first dropped
    -- byte is a continuation byte.
    while cut > 0 do
      local byte = text:byte(cut + 1)
      if byte ~= nil and byte >= 0x80 and byte < 0xC0 then
        cut = cut - 1
      else
        break
      end
    end
    text = text:sub(1, cut) .. "..."
  end
  return text
end

--- The warning text for one finding.
---@param finding { path: string, suggestion: string|nil }
---@param label string # Layer label, as in `source_of`.
---@return string
function M.message(finding, label)
  local hint = finding.suggestion ~= nil
      and (' -- did you mean "%s"?'):format(M.sanitize(finding.suggestion, MAX_PATH))
    or ""
  return ("%s: unknown option (not in the documented option tree)%s (from %s)"):format(
    M.sanitize(finding.path, MAX_PATH),
    hint,
    label
  )
end

--- The warnings for one layer's findings, capped at `M.MAX_PER_LAYER` plus one
--- summary line, so a file full of junk keys cannot flood `:checkhealth lsp`.
---@param findings { path: string, suggestion: string|nil }[]
---@param label string
---@return string[]
function M.messages(findings, label)
  local out = {}
  for i = 1, math.min(#findings, M.MAX_PER_LAYER) do
    out[i] = M.message(findings[i], label)
  end
  if #findings > M.MAX_PER_LAYER then
    out[#out + 1] = ("... and %d more unknown options (from %s)"):format(
      #findings - M.MAX_PER_LAYER,
      label
    )
  end
  return out
end

return M
