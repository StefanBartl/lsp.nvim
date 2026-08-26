---@module 'lsp.languages.documentation.markdown_words'
--- Completion source providing project-wide word completions for Markdown files.
---
--- How it works:
---   1. Scans all .md / .mdx files under a configurable root directory (defaults to cwd).
---   2. Tokenises every file into words, deduplicates them, and caches the result.
---   3. Registers itself as a completion source named "md_words", with
---      whichever engine `lsp.completion.register` says is active.
---   4. The cache is rebuilt lazily (once per session unless manually invalidated).
---
--- Integration:
---   Call `require("lsp.languages.documentation.markdown_words").setup()` once.
---
--- User commands (registered in setup()):
---   :MdSetRoot [path]   – change the scan root (omit path = use cwd).
---   :MdRebuildWords     – force a full cache rebuild from the current root.
---   :MdWordStats        – show cached word count and current root.

local M = {}

local Autocmd = require("lib.nvim.bindings.autocmd")
local notify = require("lib.nvim.notify").create("[lsp.languages.documentation.markdown_words]")
local usercmd = require("lib.nvim.bindings.usercmd")
local debounce = require("lib.nvim.debounce")
local register = require("lsp.completion.register")
local usage = require("lsp.completion.usage")

---@type string
local SOURCE_NAME = "md_words"

-- ============================================================================
-- Guard: prevent double-setup
-- ============================================================================

local _initialized = false

-- ============================================================================
-- Internal state  (module-private, no _G)
-- ============================================================================

---@class MdWords.State
---@field root        string|nil
---@field words       table<string,true>
---@field items       table[]|nil
---@field by_label    table<string, table> # label -> the item in `items`
---@field ranks_stale boolean
---@field building    boolean
---@field _user_root  string|nil

---@type MdWords.State
local state = {
  root = nil,
  words = {},
  items = nil,
  --- The same tables `items` holds, keyed by label. A pick re-stamps a handful
  --- of them in place, so it needs to find them without walking the list.
  by_label = {},
  --- Set when a pick changed the ranking. Distinct from `items = nil`, which
  --- means "no word set at all, go scan the project" -- see get_items().
  ranks_stale = false,
  building = false,
  _user_root = nil,
}

-- ============================================================================
-- Configuration
-- ============================================================================

---@class MdWords.Config
---@field max_files    integer
---@field max_filesize integer
---@field min_word_len integer
---@field max_word_len integer
---@field filetypes    string[]
---@field debounce_ms  integer

---@type MdWords.Config
local cfg = {
  max_files = 500,
  max_filesize = 200 * 1024,
  min_word_len = 3,
  max_word_len = 60,
  filetypes = { "md", "mdx" },
  debounce_ms = 3000,
}

-- ============================================================================
-- Filesystem helpers
-- ============================================================================

local uv = vim.uv or vim.loop

--- Collect all matching files under `root` up to `cfg.max_files`.
---@param root string
---@return string[]
local function collect_files(root)
  local files = {}
  local stack = { root }

  local ignore = {
    [".git"] = true,
    ["node_modules"] = true,
    [".cache"] = true,
    [".hg"] = true,
    [".svn"] = true,
    ["dist"] = true,
    ["build"] = true,
    ["target"] = true,
    [".next"] = true,
    [".nuxt"] = true,
    ["vendor"] = true,
  }

  -- Build extension set once from config (O(1) lookup in loop)
  local ext_set = {}
  for _, e in ipairs(cfg.filetypes) do
    ext_set[e] = true
  end

  while #stack > 0 and #files < cfg.max_files do
    local dir = table.remove(stack)
    local handle = uv.fs_scandir(dir)
    if not handle then
      goto continue
    end

    while true do
      local name, kind = uv.fs_scandir_next(handle)
      if not name then
        break
      end

      -- Skip hidden entries (except ".config")
      if name:sub(1, 1) == "." and name ~= ".config" then
        goto inner
      end

      local full = dir .. "/" .. name

      if kind == "directory" then
        if not ignore[name] then
          stack[#stack + 1] = full
        end
      elseif kind == "file" then
        local ext = name:match("%.([^.]+)$")
        if ext and ext_set[ext] then
          local stat = uv.fs_stat(full)
          if stat and stat.size <= cfg.max_filesize then
            files[#files + 1] = full
          end
        end
      end

      ::inner::
    end

    ::continue::
  end

  return files
end

-- ============================================================================
-- Word extraction
-- ============================================================================

--- Extract unique words from `text` into `word_set`.
---@param text     string
---@param word_set table<string,true>
---@return nil
local function extract_words(text, word_set)
  for raw in text:gmatch("[%w][%w%'%-]*[%w]?") do
    local len = #raw
    if len >= cfg.min_word_len and len <= cfg.max_word_len then
      word_set[raw] = true
    end
  end
end

--- Scan every file under `root` and return a deduplicated word set.
---@param root string
---@return table<string,true>
local function build_word_set(root)
  local word_set = {}
  local files = collect_files(root)

  for _, path in ipairs(files) do
    local fd = uv.fs_open(path, "r", 438)
    if fd then
      local stat = uv.fs_fstat(fd)
      if stat then
        local data = uv.fs_read(fd, stat.size, 0)
        if data then
          extract_words(data, word_set)
        end
      end
      uv.fs_close(fd)
    end
  end

  return word_set
end

-- ============================================================================
-- Cache management
-- ============================================================================

--- Stamp the ranked `sortText` onto the items whose word carries a use count.
---
--- Everything else keeps the `sortText` it was built with, so this only ever
--- touches the few dozen words that have actually been picked -- not the ~25000
--- in the dictionary. Rebuilding the whole list instead measured 31 ms, which
--- is what every accepted word would have cost.
---
--- Counts never decrease, so a word that has a rank keeps one: a word overtaken
--- by another is re-stamped by this same pass, and there is nothing to clear.
---@return nil
local function apply_ranks()
  for i, word in ipairs(usage.ranked(SOURCE_NAME)) do
    local item = state.by_label[word]
    -- Absent after a root change that dropped the word from the project.
    if item ~= nil then
      item.sortText = usage.sort_text(i)
      item.documentation.value = ("(md_words) used %d×"):format(usage.count(SOURCE_NAME, word))
    end
  end
end

--- Convert a word set to a list of completion items.
---
--- Ordering used to be plain alphabetical, which meant a word typed fifty times
--- ranked below one seen once in a file you never opened again. The counts come
--- from `lsp.completion.usage`, shared with personal_names but in its own
--- namespace -- a Markdown word and a plugin name can be spelled alike without
--- meaning the same thing.
---
--- The list order itself carries no meaning: both engines re-sort by score and
--- `sortText` before drawing the menu, so sorting 25000 words here would be
--- work neither of them reads.
---
--- Items are built once and cached; call only after a successful scan.
---@param word_set table<string,true>
---@return table[]
local function words_to_items(word_set)
  ---@type table[]
  local items = {}
  state.by_label = {}

  for word in pairs(word_set) do
    local item = {
      label = word,
      kind = 1, -- CompletionItemKind.Text
      sortText = usage.sort_text_unranked(word),
      filterText = word,
      insertText = word,
      documentation = {
        kind = "plaintext",
        value = "(md_words)",
      },
    }
    items[#items + 1] = item
    state.by_label[word] = item
  end

  apply_ranks()
  return items
end

--- Kick off an async rebuild.  Guards against concurrent runs.
---@param root    string
---@param on_done fun()|nil
---@return nil
local function rebuild_async(root, on_done)
  if state.building then
    return
  end
  state.building = true

  vim.defer_fn(function()
    local ok, result = pcall(build_word_set, root)
    if ok then
      state.words = result
      state.items = words_to_items(result)
      state.root = root
    end
    state.building = false
    if on_done then
      on_done()
    end
  end, 0)
end

--- Return cached items, triggering a background build if not ready yet.
---@return table[]
local function get_items()
  -- A pick changes one word's rank, never the word set, so re-stamp the ranked
  -- items in place. Dropping the cache instead would send this back through
  -- rebuild_async and rescan every markdown file in the project -- per accepted
  -- completion -- and since a rebuild in flight returns nothing, the menu would
  -- go empty right after you picked a word.
  if state.ranks_stale then
    apply_ranks()
    state.ranks_stale = false
  end

  if state.items then
    return state.items
  end
  local root = state.root or (uv.cwd and uv.cwd()) or vim.fn.getcwd()
  if not state.building then
    rebuild_async(root, nil)
  end
  return {} -- Empty while building; the engine re-queries on the next keystroke
end

-- ============================================================================
-- Public API
-- ============================================================================

--- Change the scan root and trigger a rebuild.
---@param path string|nil  nil = use cwd
---@return nil
function M.set_root(path)
  local root = path
  if not root or root == "" then
    root = (uv.cwd and uv.cwd()) or vim.fn.getcwd()
  end
  root = vim.fn.expand(root)
  root = root:gsub("[/\\]+$", "")

  if root == state.root and state.items then
    notify.info("[md_words] Root unchanged (" .. root .. "), cache still valid.")
    return
  end

  state.items = nil
  rebuild_async(root, function()
    local count = 0
    for _ in pairs(state.words) do
      count = count + 1
    end
    vim.schedule(function()
      notify.info(string.format("[md_words] Rebuilt: %d unique words from %s", count, root))
    end)
  end)
end

--- Force a full cache rebuild without changing the root.
---@return nil
function M.rebuild()
  state.items = nil
  local root = state.root or (uv.cwd and uv.cwd()) or vim.fn.getcwd()
  M.set_root(root)
end

--- Return diagnostic stats.
---@return { root: string|nil, words: integer, cached: boolean, building: boolean }
function M.stats()
  local count = 0
  for _ in pairs(state.words) do
    count = count + 1
  end
  return {
    root = state.root,
    words = count,
    cached = state.items ~= nil,
    building = state.building,
  }
end

-- ============================================================================
-- Setup
-- ============================================================================

---@param opts MdWords.Config|nil
---@return nil
function M.setup(opts)
  -- Guard: run exactly once per session
  if _initialized then
    return
  end
  _initialized = true

  -- Merge caller options into cfg
  if type(opts) == "table" then
    for k, v in pairs(opts) do
      if cfg[k] ~= nil then
        cfg[k] = v
      end
    end
  end

  -- -------------------------------------------------------------------------
  -- Register the completion source
  -- -------------------------------------------------------------------------
  -- Deferred to the first markdown buffer, not done at setup time. setup() runs
  -- on the synchronous startup path (via lsp.languages.documentation.markdown),
  -- and under nvim-cmp the registrar requires cmp -- which used to force-load it
  -- despite its `lazy = true` spec: 469 ms, plus LuaSnip (272 ms) and
  -- nvim-autopairs (79 ms) as dependencies. Waiting for a markdown buffer keeps
  -- the engine lazy for sessions that never open one.
  --
  -- Which engine gets the source is `lsp.completion.register`'s decision, not
  -- this module's. Before that split this block reached for cmp directly and
  -- warned when it was absent, so choosing blink cost the source *and* printed
  -- a message about nvim-cmp that had nothing to do with the real cause.
  local registered = false

  Autocmd.create("FileType", function()
    if registered then
      return
    end
    registered = true

    register.source({
      name = SOURCE_NAME,
      namespace = SOURCE_NAME,
      items = get_items,
      filetypes = { "markdown", "mdx", "markdown.mdx" },
      keyword_pattern = [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]],
      -- Re-stamp the ranks on the next request, without touching the word set.
      on_pick = function()
        state.ranks_stale = true
      end,
    })
  end, {
    group = Autocmd.group("MdWordsCompletionSource", true),
    pattern = { "markdown", "mdx" },
    desc = "[md_words] Register the completion source on first markdown buffer",
  })

  -- -------------------------------------------------------------------------
  -- Initial word scan: trigger on first markdown FileType event
  -- -------------------------------------------------------------------------
  Autocmd.create("FileType", function()
    if not state.root then
      local root = (uv.cwd and uv.cwd()) or vim.fn.getcwd()
      state.root = root
      rebuild_async(root, nil)
    end
  end, {
    group = Autocmd.group("MdWordsInitialScan", true),
    pattern = { "markdown", "mdx" },
    once = true,
    desc = "[md_words] Initial word-cache build on first markdown open",
  })

  -- -------------------------------------------------------------------------
  -- Debounced rebuild on directory change
  -- -------------------------------------------------------------------------
  local dir_changed_debounce = debounce.new(function()
    -- Respect explicit user-set root
    if state._user_root then
      return
    end

    local new_root = (uv.cwd and uv.cwd()) or vim.fn.getcwd()
    if new_root ~= state.root then
      state.items = nil
      rebuild_async(new_root, nil)
    end
  end, cfg.debounce_ms)

  Autocmd.create("DirChanged", function()
    dir_changed_debounce.call()
  end, {
    group = Autocmd.group("MdWordsDirChanged", true),
    desc = "[md_words] Debounced rebuild on cwd change",
  })

  -- -------------------------------------------------------------------------
  -- User commands
  -- -------------------------------------------------------------------------
  usercmd.create("MdSetRoot", function(cmd_opts)
    local path = cmd_opts.args ~= "" and cmd_opts.args or nil
    state._user_root = path
    M.set_root(path)
  end, {
    nargs = "?",
    complete = "dir",
    desc = "[md_words] Set project root for Markdown word scanning (empty = cwd)",
  })

  usercmd.create("MdRebuildWords", function()
    state.items = nil
    M.rebuild()
  end, {
    desc = "[md_words] Force full rebuild of the project-wide word cache",
  })

  usercmd.create("MdWordStats", function()
    local s = M.stats()
    notify.info(
      string.format(
        "[md_words]\n  root     : %s\n  words    : %d\n  cached   : %s\n  building : %s",
        tostring(s.root),
        s.words,
        tostring(s.cached),
        tostring(s.building)
      )
    )
  end, {
    desc = "[md_words] Show word-cache statistics",
  })
end

return M
