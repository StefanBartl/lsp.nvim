---@module 'lsp.completion.personal_names'
--- nvim-cmp source completing this config's ~30 dotted personal-plugin names
--- (e.g. "documentation.nvim", "markdown.nvim", see plugins.personal.list) as
--- one atomic candidate each. The default cmp keyword pattern splits words at
--- ".", so typing "do" would otherwise only ever surface "documentation" (a
--- plain buffer word), never the full plugin name.
---
--- Ranking: cmp's own default sorting chain (unmodified in this repo, see
--- lua/plugins/lsp.lua) already ranks a better textual match above a worse
--- one (compare.offset/exact/score) and "picked earlier this session" above
--- "never picked" (compare.recently_used) — both apply to this source for
--- free. Missing: *persistent* frequency across restarts, since
--- recently_used's history is an in-memory table that resets every session.
--- This source closes that gap with a tiny disk-persisted per-label use
--- counter, encoded into each item's `sortText` (compare.sort_text is next
--- in cmp's default chain right after recently_used) — so it only ever
--- breaks ties between equally-good textual matches, never overrides a
--- genuinely better one.
---
--- Anything beyond the personal-plugin list — filenames, module paths,
--- whatever comes up — goes in `extra.lua`, a plain hand-edited string list
--- merged in and deduplicated. `:CmpReloadWords` picks up edits to it (and
--- any change to the resolved plugin list) without a restart.

local M = {}

local notify = require("lib.nvim.notify").create("[lsp.completion.personal_names]")
local json = require("lib.nvim.fs.json")

local SOURCE_NAME = "personal_names"
local STATE_FILE = vim.fs.joinpath(vim.fn.stdpath("state"), "personal_names_usage.json")

-- ============================================================================
-- Persistent usage counts
-- ============================================================================

---@type table<string, integer>
local counts = {}
local counts_loaded = false

--- Reader supplied by the host through `setup({ labels = fn })`, returning the
--- entries whose names should be completed. Each entry may be a string or a
--- table with a `name` field. nil until `setup()` provides one.
---@type (fun(): (string|{name: string})[])|nil
local label_source = nil

local function load_counts()
  if counts_loaded then
    return
  end
  counts_loaded = true
  local decoded = json.read(STATE_FILE)
  if type(decoded) == "table" then
    counts = decoded
  end
end

local function save_counts()
  json.write(STATE_FILE, counts)
end

---Bump a label's use count and persist immediately — picking a completion is
---a human-paced, infrequent event, so a write on every bump costs nothing.
---@param label string
local function bump(label)
  load_counts()
  counts[label] = (counts[label] or 0) + 1
  save_counts()
end

-- ============================================================================
-- Items
-- ============================================================================

---@type table[]|nil
local items

---Labels from the live personal-plugin list plus `extra.lua`'s hand-
---maintained words, deduplicated.
---@return string[]
local function collect_labels()
  ---@type table<string, true>
  local seen = {}
  ---@type string[]
  local labels = {}

  -- The plugin list is the host's data, not this plugin's: `setup()` takes a
  -- reader so the config can hand it over instead of this module reaching back
  -- into `plugins.personal.list`. Without one the source simply has no plugin
  -- names and falls back to `extra.lua` alone.
  if label_source ~= nil then
    local ok, entries = pcall(label_source)
    if ok and type(entries) == "table" then
      for _, entry in ipairs(entries) do
        local name = (type(entry) == "table") and entry.name or entry
        if type(name) == "string" and not seen[name] then
          seen[name] = true
          labels[#labels + 1] = name
        end
      end
    end
  end

  local ok_extra, extra = pcall(require, "lsp.completion.personal_names.extra")
  if ok_extra and type(extra) == "table" then
    for _, word in ipairs(extra) do
      if not seen[word] then
        seen[word] = true
        labels[#labels + 1] = word
      end
    end
  end

  return labels
end

---Rebuild `items` from `collect_labels()` plus each label's persisted use
---count, encoded as a zero-padded `sortText` rank (compare.sort_text sorts
---ascending, so the most-used label needs the *smallest* string — rank 1
---wins).
local function build_items()
  local labels = collect_labels()
  load_counts()

  -- Highest count first, alphabetical among ties.
  table.sort(labels, function(a, b)
    local ca, cb = counts[a] or 0, counts[b] or 0
    if ca ~= cb then
      return ca > cb
    end
    return a < b
  end)

  items = {}
  for i, label in ipairs(labels) do
    items[i] = {
      label = label,
      kind = 1, -- CompletionItemKind.Text
      sortText = ("%04d"):format(i),
      filterText = label,
      insertText = label,
      documentation = {
        kind = "plaintext",
        value = ("(personal_names) used %d×"):format(counts[label] or 0),
      },
    }
  end
end

-- ============================================================================
-- nvim-cmp source
-- ============================================================================

---@class PersonalNames.Source
local Source = {}
Source.__index = Source

---@return PersonalNames.Source
function Source.new()
  return setmetatable({}, Source)
end

---@return boolean
function Source:is_available()
  return true
end

---@return string
function Source:get_debug_name()
  return SOURCE_NAME
end

---Includes "." (alongside md_words' "-") so the pattern spans a whole name
---like "documentation.nvim" once part of it has been typed — matching a bare
---"do" still resolves to just "do", since no dot has been typed yet.
---@return string
function Source:get_keyword_pattern()
  return [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%([-.]\w*\)*\)]]
end

---@param _ table
---@param callback fun(result: table)
function Source:complete(_, callback)
  if not items then
    build_items()
  end
  callback({ items = items, isIncomplete = false })
end

-- ============================================================================
-- Setup
-- ============================================================================

local _initialized = false

---Register the source and wire persistent-usage tracking. Call once, from
---nvim-cmp's own `opts` function (lua/plugins/lsp.lua) — cmp is guaranteed
---already loading at that point (this function is part of building its own
---config), so there is no eager-load concern to guard against here, unlike
---md_words' deferred FileType registration.
---@param opts? { labels?: fun(): (string|{name: string})[] }
function M.setup(opts)
  if _initialized then
    return
  end
  _initialized = true

  if type(opts) == "table" and type(opts.labels) == "function" then
    label_source = opts.labels
  end

  local ok, cmp = pcall(require, "cmp")
  if not ok then
    notify.warn("nvim-cmp not found — personal_names source will not appear in completions.")
    return
  end

  cmp.register_source(SOURCE_NAME, Source.new())

  cmp.event:on("confirm_done", function(event)
    local entry = event.entry
    if entry and entry.source and entry.source.name == SOURCE_NAME then
      bump(entry.completion_item.label)
      items = nil -- force a re-sort on the next complete() with the fresh count
    end
  end)

  require("lib.nvim.usercmd").create("CmpReloadWords", function()
    package.loaded["lsp.completion.personal_names.extra"] = nil
    items = nil
    notify.info(("Reloaded — %d word(s)."):format(#collect_labels()))
  end, {
    desc = "[lsp.completion.personal_names] Reload extra.lua and the personal-plugin list without restarting",
  })
end

return M
