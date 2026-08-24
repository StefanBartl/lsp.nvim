---@module 'lsp.completion.personal_names'
--- Completion source for this config's ~30 dotted personal-plugin names
--- (e.g. "documentation.nvim", "markdown.nvim", see plugins.personal.list) as
--- one atomic candidate each. The default cmp keyword pattern splits words at
--- ".", so typing "do" would otherwise only ever surface "documentation" (a
--- plain buffer word), never the full plugin name.
---
--- Ranking is `lsp.completion.usage`'s job: an engine already ranks a better
--- textual match above a worse one and remembers this session's picks, but
--- forgets across restarts. That module closes the gap and is shared with
--- md_words.
---
--- Engine-neutral since 2026-08-23. It builds items and nothing else; getting
--- them in front of the user is `lsp.completion.register`'s problem, so this
--- file no longer knows whether nvim-cmp or blink is running. Measured before
--- porting: blink's fuzzy matcher does *not* make this source redundant —
--- typing "do" there still does not surface "documentation.nvim".
---
--- Anything beyond the personal-plugin list — filenames, module paths,
--- whatever comes up — goes in `extra.lua`, a plain hand-edited string list
--- merged in and deduplicated. `:CmpReloadWords` picks up edits to it (and
--- any change to the resolved plugin list) without a restart.
---
---@see lsp.completion.register
---@see lsp.completion.usage

local M = {}

local notify = require("lib.nvim.notify").create("[lsp.completion.personal_names]")
local register = require("lsp.completion.register")
local usage = require("lsp.completion.usage")

local SOURCE_NAME = "personal_names"

--- Reader supplied by the host through `setup({ labels = fn })`, returning the
--- entries whose names should be completed. Each entry may be a string or a
--- table with a `name` field. nil until `setup()` provides one.
---@type (fun(): (string|{name: string})[])|nil
local label_source = nil

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

---Rebuild `items` from `collect_labels()`, with the picked names carrying a
---`sortText` rank and the rest sorted by their own label.
---
---Rebuilt whole on every pick rather than re-stamped in place the way md_words
---does it: thirty labels, so the machinery that saves the dictionary 31 ms
---would only cost clarity here.
local function build_items()
  items = {}

  ---@type table<string, table>
  local by_label = {}

  for _, label in ipairs(collect_labels()) do
    local item = {
      label = label,
      kind = 1, -- CompletionItemKind.Text
      sortText = usage.sort_text_unranked(label),
      filterText = label,
      insertText = label,
      documentation = {
        kind = "plaintext",
        value = "(personal_names)",
      },
    }
    items[#items + 1] = item
    by_label[label] = item
  end

  for i, label in ipairs(usage.ranked(SOURCE_NAME)) do
    local item = by_label[label]
    -- A name that was picked before it was removed from the plugin list.
    if item ~= nil then
      item.sortText = usage.sort_text(i)
      item.documentation.value = ("(personal_names) used %d×"):format(
        usage.count(SOURCE_NAME, label)
      )
    end
  end
end

---Every item, rebuilt on demand. The engine adapter calls this.
---@return table[]
local function get_items()
  if not items then
    build_items()
  end
  return items
end

-- ============================================================================
-- Setup
-- ============================================================================

local _initialized = false

---Register the source with whichever engine is configured.
---
---Call once. Under nvim-cmp this belongs in cmp's own `opts` function, where
---cmp is already loading; under blink the call can happen any time before the
---first completion request, since blink resolves its providers lazily.
---@param opts? { labels?: fun(): (string|{name: string})[] }
function M.setup(opts)
  if _initialized then
    return
  end
  _initialized = true

  if type(opts) == "table" and type(opts.labels) == "function" then
    label_source = opts.labels
  end

  register.source({
    name = SOURCE_NAME,
    namespace = SOURCE_NAME,
    items = get_items,
    -- Includes "." (alongside md_words' "-") so the pattern spans a whole name
    -- like "documentation.nvim" once part of it has been typed -- matching a
    -- bare "do" still resolves to just "do", since no dot has been typed yet.
    keyword_pattern = [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%([-.]\w*\)*\)]],
    -- Drop the cache so the next request re-sorts with the fresh count.
    on_pick = function()
      items = nil
    end,
  })

  require("lib.nvim.usercmd").create("CmpReloadWords", function()
    package.loaded["lsp.completion.personal_names.extra"] = nil
    items = nil
    notify.info(("Reloaded — %d word(s)."):format(#collect_labels()))
  end, {
    desc = "[lsp.completion.personal_names] Reload extra.lua and the personal-plugin list without restarting",
  })
end

return M
