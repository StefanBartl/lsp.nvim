---@module 'lsp.languages.documentation.markdown_words'
--- nvim-cmp source that provides project-wide word completions for Markdown files.
---
--- How it works:
---   1. Scans all .md / .mdx files under a configurable root directory (defaults to cwd).
---   2. Tokenises every file into words, deduplicates them, and caches the result.
---   3. Registers itself as a cmp source named "md_words".
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

local Autocmd = require("lib.nvim.autocmd")
local notify = require("lib.nvim.notify").create("[lsp.languages.documentation.markdown_words]")
local usercmd = require("lib.nvim.usercmd")
local debounce = require("lib.nvim.debounce")

-- ============================================================================
-- Guard: prevent double-setup
-- ============================================================================

local _initialized = false

-- ============================================================================
-- Internal state  (module-private, no _G)
-- ============================================================================

---@class MdWords.State
---@field root       string|nil
---@field words      table<string,true>
---@field items      table[]|nil
---@field building   boolean
---@field _user_root string|nil

---@type MdWords.State
local state = {
  root = nil,
  words = {},
  items = nil,
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

--- Convert a word set to a sorted list of cmp completion items.
--- Items are built once and cached; call only after a successful scan.
---@param word_set table<string,true>
---@return table[]
local function words_to_items(word_set)
  -- Pre-count for preallocation
  local n = 0
  for _ in pairs(word_set) do
    n = n + 1
  end

  ---@type {label:string, kind:integer, filterText:string, insertText:string, documentation:{kind:string,value:string}}[]
  local items = {}
  local i = 0
  for w in pairs(word_set) do
    i = i + 1
    ---@diagnostic disable-next-line: assign-type-mismatch
    items[i] = {
      label = w,
      kind = 1, -- CompletionItemKind.Text
      filterText = w,
      insertText = w,
      documentation = { kind = "plaintext", value = "(md_words)" },
    }
  end

  table.sort(items, function(a, b)
    return tostring(a.label) < tostring(b.label)
  end)
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

--- Return cached cmp items, triggering a background build if not ready yet.
---@return table[]
local function get_items()
  if state.items then
    return state.items
  end
  local root = state.root or (uv.cwd and uv.cwd()) or vim.fn.getcwd()
  if not state.building then
    rebuild_async(root, nil)
  end
  return {} -- Return empty while building; cmp will re-query on next keystroke
end

-- ============================================================================
-- nvim-cmp source
-- ============================================================================

---@class MdWords.Source
local Source = {}
Source.__index = Source

---@return MdWords.Source
function Source.new()
  return setmetatable({}, Source)
end

---@return boolean
function Source:is_available()
  local ft = vim.bo.filetype
  return ft == "markdown" or ft == "mdx" or ft == "markdown.mdx"
end

---@return string
function Source:get_debug_name()
  return "md_words"
end

---@return string
function Source:get_keyword_pattern()
  return [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]]
end

---@param _ table
---@param callback fun(result: table)
---@return nil
function Source:complete(_, callback)
  callback({ items = get_items(), isIncomplete = false })
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
  -- Register nvim-cmp source
  -- -------------------------------------------------------------------------
  -- `require("cmp")` happens inside the FileType handler, never at setup time.
  -- setup() runs on the synchronous startup path (via lsp.languages.documentation
  -- .markdown), and a top-level require here force-loaded nvim-cmp despite its
  -- `lazy = true` spec — 469 ms, plus LuaSnip (272 ms) and nvim-autopairs (79 ms)
  -- pulled in as its dependencies. Deferring to the first markdown buffer keeps
  -- cmp lazy for sessions that never open one.
  local source_registered = false
  local warned_missing = false

  -- Inject our source into buffer-local cmp config for markdown files.
  -- Uses `once = false` so every new markdown buffer picks it up,
  -- but the duplicate-guard inside prevents double-appending.
  Autocmd.create("FileType", function()
    local ok_cmp, cmp = pcall(require, "cmp")
    if not ok_cmp then
      if not warned_missing then
        warned_missing = true
        notify.warn("[md_words] nvim-cmp not found – source will not appear in completions.")
      end
      return
    end

    -- Registration is global, so it must happen exactly once — but only now
    -- that we know cmp is actually loaded.
    if not source_registered then
      source_registered = true
      cmp.register_source("md_words", Source.new())
    end

    -- Read the *buffer-local* config so we see what's already active here
    local bufcfg = cmp.get_config()
    if not bufcfg then
      return
    end

    local sources = bufcfg.sources or {}
    for _, s in ipairs(sources) do
      if s.name == "md_words" then
        return
      end -- already present
    end

    -- Build new list with md_words appended at low priority
    local new_sources = {}
    for i, s in ipairs(sources) do
      new_sources[i] = s
    end
    new_sources[#sources + 1] = { name = "md_words", priority = 100 }

    cmp.setup.buffer({ sources = new_sources })
  end, {
    group = Autocmd.group("MdWordsCmpSource", true),
    pattern = { "markdown", "mdx" },
    desc = "[md_words] Inject cmp source into markdown buffer",
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
