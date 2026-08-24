---@module 'lsp.completion.usage'
---@brief Persistent per-label use counts, shared by the hand-written sources.
---@description
--- Both completion engines rank a better textual match above a worse one, and
--- both remember what was picked *this session*. Neither remembers across
--- restarts. This closes that gap: a small on-disk counter per label, turned
--- into a `sortText` rank.
---
--- `sortText` is the right lever precisely because it is weak. In nvim-cmp it
--- sits behind `compare.offset/exact/score/recently_used`, in blink behind
--- `score` (default `fuzzy.sorts = { "score", "sort_text" }`). So a frequently
--- picked label only ever wins a tie between equally good textual matches --
--- it never drags a bad match to the top. Boosting the score itself would.
---
--- Only the labels that carry a count get a rank; everything else is stamped
--- from its own label (see `sort_text_unranked`). That split is what keeps a
--- pick cheap: re-ranking after an accepted word touches the few dozen counted
--- labels rather than re-sorting and rebuilding all ~25000 dictionary items,
--- which measured 31 ms *per accepted word* when it did.
---
--- Namespaced because two sources share the file and their label spaces
--- overlap: a Markdown word and a plugin name can be spelled the same without
--- meaning the same, and merging their counts would let writing prose reorder
--- your plugin names.
---
---@see lsp.completion.register
---@see lsp.completion.personal_names
---@see lsp.languages.documentation.markdown_words

local json = require("lib.nvim.fs.json")

local M = {}

---@type string
local STATE_FILE = vim.fs.joinpath(vim.fn.stdpath("state"), "lsp_completion_usage.json")

--- The file `personal_names` wrote before the counter was shared. Read once and
--- folded in, so an existing history survives the move rather than silently
--- resetting to zero -- these counts are the user's, accumulated over months.
---@type string
local LEGACY_FILE = vim.fs.joinpath(vim.fn.stdpath("state"), "personal_names_usage.json")

---@type table<string, table<string, integer>>|nil # namespace -> label -> count
local counts = nil

---@internal
---@return nil
local function load()
  if counts ~= nil then
    return
  end

  local decoded = json.read(STATE_FILE)
  counts = type(decoded) == "table" and decoded or {}

  -- One-time migration. Guarded on the namespace being absent rather than on
  -- the legacy file being present: re-running it after the user has picked
  -- something new would overwrite fresh counts with stale ones.
  if counts.personal_names == nil then
    local legacy = json.read(LEGACY_FILE)
    if type(legacy) == "table" and next(legacy) ~= nil then
      counts.personal_names = legacy
      json.write(STATE_FILE, counts)
    end
  end
end

--- Record one use of `label` in `ns` and persist immediately.
---
--- Picking a completion is a human-paced event, so a write per pick is free --
--- and it means a crash never costs the history.
---@param ns string # Namespace, e.g. "personal_names".
---@param label string
---@return nil
function M.bump(ns, label)
  if type(ns) ~= "string" or type(label) ~= "string" or label == "" then
    return
  end
  load()
  counts[ns] = counts[ns] or {}
  counts[ns][label] = (counts[ns][label] or 0) + 1
  json.write(STATE_FILE, counts)
end

--- How often `label` has been picked in `ns`.
---@param ns string
---@param label string
---@return integer
function M.count(ns, label)
  load()
  local bucket = counts[ns]
  return (bucket and bucket[label]) or 0
end

--- Every label in `ns` that carries a count, most-used first, alphabetical
--- among ties.
---
--- Deliberately driven by the counter rather than by the caller's label list:
--- the Markdown dictionary holds ~25000 words of which a few dozen have ever
--- been picked, so ordering the *counted* ones is a sort over dozens instead of
--- over the whole dictionary. Labels that are no longer offered simply find no
--- item to stamp.
---@param ns string
---@return string[]
function M.ranked(ns)
  load()
  local bucket = counts[ns] or {}

  ---@type string[]
  local labels = {}
  for label in pairs(bucket) do
    labels[#labels + 1] = label
  end

  table.sort(labels, function(a, b)
    if bucket[a] ~= bucket[b] then
      return bucket[a] > bucket[b]
    end
    return a < b
  end)

  return labels
end

--- The `sortText` for rank `i`, where 1 is the most-used.
---
--- Zero-padded because `sortText` compares as a *string* in both engines: eight
--- digits keeps the ordering correct for dictionaries far larger than any real
--- word list, where `"10"` would otherwise sort before `"9"`.
---@param i integer
---@return string
function M.sort_text(i)
  return ("%08d"):format(i)
end

--- The `sortText` for a label that has never been picked.
---
--- Not `nil`: both engines read a missing `sortText` as *no opinion* and hand
--- the pair to the next comparator (`fuzzy/sort.lua`, `compare.sort_text`),
--- which would drop the one thing this module exists for -- a used label
--- beating an unused one on an otherwise equal match.
---
--- The label itself, so the unpicked bulk stays alphabetical in both engines.
--- The obvious alternative -- build the item list in alphabetical order and let
--- that stand -- only works under nvim-cmp: blink sorts with `table.sort`,
--- which is unstable, so array order survives nothing there.
---
--- `"~"` (0x7E) is the last printable ASCII character, so an unpicked
--- dictionary word also loses a `sortText` tie against a real LSP item, whose
--- servers overwhelmingly emit digits or letters. That matches the standing
--- these sources already have (`score_offset = -3` under blink, `priority` 100
--- under cmp) instead of quietly contradicting it.
---@param label string
---@return string
function M.sort_text_unranked(label)
  return "~" .. label
end

--- Where the counts live. For `:checkhealth` and tests.
---@return string
function M.state_file()
  return STATE_FILE
end

return M
