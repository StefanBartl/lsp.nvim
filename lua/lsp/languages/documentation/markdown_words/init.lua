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
local expand_path = require("lib.nvim.cross.fs.expand_path")

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
---@field max_dirs     integer
---@field slice_ms     integer
---@field max_filesize integer
---@field min_word_len integer
---@field max_word_len integer
---@field filetypes    string[]
---@field debounce_ms  integer

---@type MdWords.Config
local cfg = {
  max_files = 500,
  -- Directories opened per scan. `max_files` only counts *matching* files, so a
  -- tree with few Markdown files (a home directory, %TEMP%) is walked to the
  -- last directory: measured 7176 directories / 32 000 entries for 501 files.
  max_dirs = 3000,
  -- Longest stretch the scan holds the editor before it yields to the event loop.
  slice_ms = 8,
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

---@type table<string,true>
local IGNORE = {
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

--- A directory walk that can be put down and picked up again.
---
--- One `walk_step` call does at most `cfg.slice_ms` of work, so the editor is
--- never held for the length of the tree. Three bounds end a walk: `max_files`
--- (matching files), `max_dirs` (directories opened -- the one that matters
--- when a tree holds few Markdown files) and running out of directories.
---@class MdWords.Walk
---@field stack   string[]            # directories still to list
---@field handle  userdata|nil        # the directory being drained, if any
---@field dir     string|nil          # its path
---@field files   string[]            # matches so far
---@field dirs    integer             # directories opened so far
---@field ext_set table<string,true>

---@param root string
---@return MdWords.Walk
local function walk_new(root)
  local ext_set = {}
  for _, e in ipairs(cfg.filetypes) do
    ext_set[e] = true
  end
  return { stack = { root }, files = {}, dirs = 0, ext_set = ext_set }
end

--- Advance `walk` until it is finished or `deadline` (a `uv.hrtime()` value)
--- has passed, whichever comes first.
---@param walk     MdWords.Walk
---@param deadline integer
---@return boolean done
local function walk_step(walk, deadline)
  local files, stack, ext_set = walk.files, walk.stack, walk.ext_set
  local seen = 0

  while true do
    local opened = false
    if not walk.handle then
      if #stack == 0 or #files >= cfg.max_files or walk.dirs >= cfg.max_dirs then
        return true
      end
      walk.dir = table.remove(stack)
      walk.dirs = walk.dirs + 1
      walk.handle = uv.fs_scandir(walk.dir) -- nil when unreadable: next pass moves on
      opened = true
    else
      local name, kind = uv.fs_scandir_next(walk.handle)
      if not name then
        walk.handle = nil
      elseif name:sub(1, 1) ~= "." or name == ".config" then -- hidden entries skipped
        local full = walk.dir .. "/" .. name
        if kind == "directory" then
          if not IGNORE[name] then
            stack[#stack + 1] = full
          end
        elseif kind == "file" then
          local ext = name:match("%.([^.]+)$")
          if ext and ext_set[ext] then
            local stat = uv.fs_stat(full)
            if stat and stat.size <= cfg.max_filesize then
              files[#files + 1] = full
              if #files >= cfg.max_files then
                -- Per file, not per directory: see the max_files spec.
                walk.handle = nil
              end
            end
          end
        end
      end
    end

    -- After every directory opened (one cold directory can cost 100+ ms on its
    -- own, so 32 of them in a row would not be a "slice"), and every 32 entries
    -- otherwise (uv.hrtime() is cheap, but not free per entry).
    seen = seen + 1
    if (opened or seen % 32 == 0) and uv.hrtime() > deadline then
      return false
    end
  end
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

--- Read one file and add its words to `word_set`.
---@param path     string
---@param word_set table<string,true>
---@return nil
local function read_words(path, word_set)
  local fd = uv.fs_open(path, "r", 438)
  if not fd then
    return
  end
  local stat = uv.fs_fstat(fd)
  if stat then
    local data = uv.fs_read(fd, stat.size, 0)
    if data then
      extract_words(data, word_set)
    end
  end
  uv.fs_close(fd)
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

--- Id of the newest rebuild. A rebuild that finds it changed has been
--- superseded (the root moved on) and stops without touching `state`.
local build_id = 0

--- Rebuild the cache in slices of at most `cfg.slice_ms`.
---
--- The walk and the file reads are cut into slices and handed back to the event
--- loop between them, so a large tree costs wall-clock time but no freeze. Every
--- bound that used to keep the scan short still applies (`max_files`,
--- `max_filesize`), plus `max_dirs`, because a tree with few Markdown files was
--- walked to its last directory.
---
--- A rebuild now spans many ticks, so asking for another root while one runs
--- *replaces* it. Dropping the request (the old `state.building` guard) was only
--- harmless while a rebuild fitted into one tick: it would leave the cache on
--- the old root with nothing left to trigger the new one.
---@param root    string
---@param on_done fun()|nil
---@return nil
local function rebuild_async(root, on_done)
  build_id = build_id + 1
  local id = build_id
  state.building = true

  local walk = walk_new(root)
  local word_set = {}
  local files, next_file = nil, 1

  local function slice()
    if id ~= build_id then
      return
    end
    local deadline = uv.hrtime() + cfg.slice_ms * 1e6

    local ok, done = pcall(function()
      if not files then
        if not walk_step(walk, deadline) then
          return false
        end
        files = walk.files
      end
      while next_file <= #files do
        read_words(files[next_file], word_set)
        next_file = next_file + 1
        if uv.hrtime() > deadline then
          return next_file > #files
        end
      end
      return true
    end)

    if ok and not done then
      vim.defer_fn(slice, 1)
      return
    end
    if ok then
      state.words = word_set
      state.items = words_to_items(word_set)
      state.root = root
    end
    state.building = false
    if on_done then
      on_done()
    end
  end

  vim.defer_fn(slice, 0)
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
  -- Not `vim.fn.expand()`: that is Vim's filename expansion, which reads a
  -- backtick span as a command substitution over `&shell` and treats `%`,
  -- `#`, `<cfile>`/`<cword>` as Vim specials -- all live on `:MdSetRoot`'s
  -- argument. Only `~` and environment variables are wanted here.
  root = expand_path(root)
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
