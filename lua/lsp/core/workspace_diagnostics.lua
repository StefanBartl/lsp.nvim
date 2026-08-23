---@module 'lsp.core.workspace_diagnostics'
---@brief Runtime-toggleable gate for workspace-diagnostics.nvim's populate on LSP attach.
---@description
--- workspace-diagnostics.nvim loads every file of the current repo into
--- buffers on LSP attach (`git ls-files`) to populate diagnostics
--- workspace-wide. That is expensive in large repos — see lsp/init.lua for
--- the incident that made this toggleable (a 60-90s startup freeze in a
--- ~600-file non-code repo). The startup default is still gated there by
--- machine role (off on the "workstation"); this module turns the gate into
--- a LIVE switch on top of that default, so it can be flipped without
--- restarting Neovim — e.g. to turn it off during a "just researching/
--- browsing" phase on a dev machine, or on briefly on the workstation for a
--- one-off deep dive into a smaller repo.
---
--- `lsp.core.attach`'s on_attach reads `enabled()` on every attach (not a
--- value captured once at startup), so a toggle takes effect for the NEXT
--- LSP attach (new buffer, `:LspRestartHere`, ...) — it does not
--- retroactively populate/depopulate buffers already attached. Use
--- `populate_now()` for an immediate one-off populate of the current
--- buffer's clients regardless of the toggle state.
---
--- ## Why this module also owns HOW the populate runs
---
--- The upstream plugin's default `workspace_files` is expensive in three
--- separate ways, all of them on the main loop inside `on_attach`:
---
---   1. two synchronous `vim.fn.system` calls (`git rev-parse` + `git
---      ls-files`) -- on Windows with EDR/AV in the loop, that alone is a
---      three-digit millisecond cost;
---   2. `vim.fn.filereadable()` plus `vim.filetype.match()` for EVERY entry
---      the repo returns (~2600 in this config);
---   3. one `vim.defer_fn` per matching file, each doing a synchronous
---      `vim.fn.readfile()` of the whole file to build a `didOpen`.
---
--- Measured effect: a 300-420ms stall right after `LspAttach`, plus a long
--- tail of 1700+ deferred callbacks. See docs/ROADMAP/PERF-Startup-Analyse.md.
---
--- So `schedule_populate()` below replaces the plugin's file discovery with
--- `lib.nvim.fs.collect_recursive.files_async` (no subprocess, prunes ignored
--- subtrees, filters by extension while walking). It also defers the whole
--- thing off the attach path, and refuses to populate at all above
--- `max_files` -- the size gate that the machine-role default in lsp/init.lua
--- could only approximate.
---
--- ## Why the populate itself is no longer the plugin's
---
--- It used to hand that finished list to
--- `workspace-diagnostics.populate_workspace_diagnostics`. It no longer does,
--- because that path threw on every LSP attach once any file in the list had
--- been deleted or renamed:
---
---   E484: Can't open file <path>     (from a vim.schedule callback)
---
--- Two plugin-internal caches cause it, and neither is reachable from here:
--- `_workspace_files` memoizes the file list on first use and is never
--- invalidated, and its per-file `vim.fn.readfile()` is unguarded. So a file
--- removed mid-session stays in the list forever and raises once per missing
--- file, per attach, for the rest of the session. Clearing the plugin's
--- module state (`package.loaded[...] = nil`) would also wipe its
--- `_loaded_clients` guard and re-send every `didOpen` on each attach, so
--- that is not a fix either.
---
--- What the plugin actually contributed at that point was ~20 lines of
--- `didOpen` notifications, which `send_did_open()` below now does directly
--- -- guarded, chunked, and with the list re-checked as it is consumed. That
--- also resolves the multi-client caveat this module used to carry: each
--- client now populates from its own list instead of inheriting whichever
--- one attached first.
---
--- User-facing commands live in lsp.usercmds.workspace_diagnostics.

local notify = require("lib.nvim.notify").create("[lsp.workspace_diagnostics]")

local M = {}

--- Tunables for the populate path. `extensions` is what the workspace walk
--- keeps; the plugin still filters the result against each client's
--- `config.filetypes`, so this only has to be a cheap pre-filter that avoids
--- running `vim.filetype.match` over the whole tree.
---@type { max_files: integer, extensions: table<string, boolean>, delay_ms: integer }
local opts = {
  max_files = 800,
  delay_ms = 1500,
}

--- filetype -> file extensions, for the few cases where they differ. Any
--- filetype not listed here is assumed to equal its extension (lua, go,
--- json, ...), which covers most servers.
---@type table<string, string[]>
local FT_EXTENSIONS = {
  sh = { "sh", "bash", "zsh" },
  bash = { "sh", "bash" },
  python = { "py", "pyi" },
  typescript = { "ts", "mts", "cts" },
  typescriptreact = { "tsx" },
  javascript = { "js", "mjs", "cjs" },
  javascriptreact = { "jsx" },
  markdown = { "md", "markdown" },
  json = { "json" },
  jsonc = { "jsonc", "json" },
  yaml = { "yaml", "yml" },
  rust = { "rs" },
  kotlin = { "kt", "kts" },
  cpp = { "cpp", "cc", "cxx", "hpp", "hh" },
  c = { "c", "h" },
}

--- Build the extension set a given client could possibly diagnose, from its
--- own `config.filetypes`. Scoping the walk per client is what keeps the
--- `max_files` gate meaningful: collecting every extension in the repo would
--- count Markdown and JSON against lua_ls's budget and trip the gate on a
--- workspace it could have handled comfortably.
---@param client vim.lsp.Client
---@return table<string, boolean>|nil  # nil when the client declares no filetypes
local function client_extensions(client)
  local filetypes = vim.tbl_get(client or {}, "config", "filetypes")
  if type(filetypes) ~= "table" or #filetypes == 0 then
    return nil
  end

  local set = {}
  for _, ft in ipairs(filetypes) do
    for _, ext in ipairs(FT_EXTENSIONS[ft] or { ft }) do
      set[ext] = true
    end
  end
  return set
end

---@param o { max_files?: integer, delay_ms?: integer }
---@return nil
function M.configure(o)
  o = o or {}
  if type(o.max_files) == "number" then
    opts.max_files = o.max_files
  end
  if type(o.delay_ms) == "number" then
    opts.delay_ms = o.delay_ms
  end
end

---@type boolean
local state = false
---@type boolean
local seeded = false

--- Seed the live state from the startup default (see lsp/init.lua). Only
--- takes effect once — later calls are no-ops, so a user's runtime toggle
--- can never be silently clobbered by a later re-entry into LSP setup.
---@param default boolean
---@return nil
function M.seed(default)
  if seeded then
    return
  end
  seeded = true
  state = default and true or false
end

---@return boolean
function M.enabled()
  return state
end

---@param value boolean
---@return boolean
function M.set(value)
  state = value and true or false
  notify.info("workspace diagnostics on LSP attach: " .. (state and "ON" or "OFF"))
  return state
end

---@return boolean
function M.toggle()
  return M.set(not state)
end

--- Per-client-shape file lists. Keyed by the sorted extension set, so two
--- clients covering the same filetypes share one walk. A `false` value means
--- "computed, and rejected by the size gate" -- distinct from `nil` ("not
--- computed yet"), so the gate is not re-evaluated on every attach.
---@type table<string, string[]|false>
local files_cache = {}
---@type table<string, fun(files: string[])[]>
local waiters = {}

---@param ext_set table<string, boolean>
---@return string
local function cache_key(ext_set)
  local keys = vim.tbl_keys(ext_set)
  table.sort(keys)
  return table.concat(keys, ",")
end

---@param key string
---@param files string[]
---@return nil
local function flush_waiters(key, files)
  local queued = waiters[key] or {}
  waiters[key] = nil
  for _, fn in ipairs(queued) do
    fn(files)
  end
end

--- Collect the candidate files for one client without blocking the main
--- loop. Calls `cb` with the list, or with an empty list when there is no
--- root or the size gate rejected the workspace. Concurrent calls for the
--- same extension set are queued onto the running walk, not duplicated.
---@param ext_set table<string, boolean>
---@param cb fun(files: string[])
---@return nil
local function collect_files_async(ext_set, cb)
  local key = cache_key(ext_set)

  local cached = files_cache[key]
  if cached ~= nil then
    cb(cached or {})
    return
  end

  if waiters[key] then
    waiters[key][#waiters[key] + 1] = cb
    return
  end
  waiters[key] = { cb }

  local buf_path = vim.api.nvim_buf_get_name(0)
  local finder = require("lib.nvim.fs.find_root")({ markers = { ".git" } })
  local root = finder.find(buf_path ~= "" and buf_path or vim.uv.cwd())
  if not root then
    files_cache[key] = false
    flush_waiters(key, {})
    return
  end

  local ignore_set = require("lib.nvim.fs.ignore.list").as_set()

  require("lib.nvim.fs.collect_recursive").files_async(root, {
    ignore = function(abs_path, is_dir)
      local base = vim.fs.basename(abs_path) or abs_path
      if is_dir then
        return ignore_set[base] == true
      end
      local ext = base:match("%.([%w_]+)$")
      return not (ext and ext_set[ext])
    end,
  }, function(files)
    if #files > opts.max_files then
      notify.warn(
        ("workspace diagnostics skipped: %d files exceed the max_files gate of %d"):format(
          #files,
          opts.max_files
        )
      )
      files_cache[key] = false
      files = {}
    else
      files_cache[key] = files
    end

    flush_waiters(key, files)
  end)
end

--- How many files one `send_did_open` tick reads before yielding. The plugin
--- used one `vim.defer_fn` per file (~1700 callbacks here); a single
--- synchronous loop would instead stall proportionally to the workspace.
--- Chunking bounds both.
local CHUNK_SIZE = 25
local CHUNK_DELAY_MS = 10

--- Clients already populated this session. Replaces the plugin's own
--- `_loaded_clients`, which we no longer go through.
---@type table<integer, boolean>
local populated_clients = {}

---@param client vim.lsp.Client
---@param method string
---@param params table
---@return nil
local function notify_client(client, method, params)
  -- 0.12 made the method form canonical; keep the function form for older
  -- Neovim, matching what the plugin did.
  if vim.fn.has("nvim-0.12") == 1 then
    client:notify(method, params)
  else
    client.notify(client, method, params)
  end
end

--- Send `textDocument/didOpen` for every file in `files` the client can
--- diagnose, in chunks, so the server sees the whole workspace.
---
--- `readfile` is `pcall`-guarded on purpose rather than defensively: the file
--- list is collected once and cached for the session, so a file deleted or
--- renamed since the walk is an expected state, not an exceptional one. That
--- unguarded read is exactly what made the plugin's version throw E484 -- see
--- the module header.
---@param client vim.lsp.Client
---@param bufnr integer
---@param files string[]
---@param force boolean|nil  # skip the once-per-client guard (`populate_now`)
---@return nil
local function send_did_open(client, bufnr, files, force)
  if not force then
    if populated_clients[client.id] then
      return
    end
    populated_clients[client.id] = true
  end

  if not client:supports_method("textDocumentSync/openClose") then
    return
  end

  local wanted = {}
  for _, ft in ipairs(vim.tbl_get(client, "config", "filetypes") or {}) do
    wanted[ft] = true
  end
  if vim.tbl_isempty(wanted) then
    return
  end

  local current = vim.api.nvim_buf_get_name(bufnr)
  local index = 1

  local function send_chunk()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local budget = CHUNK_SIZE
    while index <= #files and budget > 0 do
      local path = files[index]
      index = index + 1
      budget = budget - 1

      if path ~= current then
        -- Filename-only matching, with no buffer-loading fallback: the
        -- extension pre-filter in collect_files_async already narrowed this
        -- to the client's own filetypes, and loading a buffer per file is
        -- precisely the cost this module exists to avoid.
        local ft = vim.filetype.match({ filename = path })
        if ft and wanted[ft] then
          local ok, lines = pcall(vim.fn.readfile, path)
          if ok then
            notify_client(client, "textDocument/didOpen", {
              textDocument = {
                uri = vim.uri_from_fname(path),
                version = 0,
                text = table.concat(lines, "\n"),
                languageId = ft,
              },
            })
          end
        end
      end
    end

    if index <= #files then
      vim.defer_fn(send_chunk, CHUNK_DELAY_MS)
    end
  end

  send_chunk()
end

--- Populate workspace diagnostics for `client`/`bufnr` off the attach path.
---
--- Deliberately NOT synchronous: `on_attach` runs while the client is still
--- processing its first server responses, and anything expensive there lands
--- squarely in the user-visible startup stall. The delay costs nothing real --
--- workspace diagnostics are a background signal, not something needed at the
--- first paint.
---@param client vim.lsp.Client
---@param bufnr integer
---@return nil
function M.schedule_populate(client, bufnr)
  vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    -- The toggle may have been flipped off during the delay.
    if not M.enabled() then
      return
    end

    local ext_set = client_extensions(client)
    if not ext_set then
      return
    end

    collect_files_async(ext_set, function(files)
      if #files == 0 then
        return
      end
      send_did_open(client, bufnr, files)
    end)
  end, opts.delay_ms)
end

--- Force-populate workspace diagnostics for `bufnr`'s attached clients right
--- now, regardless of the toggle state. Useful after switching it ON without
--- wanting to restart/reattach the LSP client just to see it take effect.
---
--- Schedules rather than completes: the file walk is async and the sending is
--- chunked, so the count below is how many clients were *started*, not how
--- many finished. Bypasses the once-per-client guard, so calling it twice
--- really does re-send.
---@param bufnr? integer  # 0 or nil for the current buffer
---@return boolean ok
---@return integer|string count_or_err  # number of clients scheduled, or an error string
function M.populate_now(bufnr)
  bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()

  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  if #clients == 0 then
    return false, "no LSP clients attached to this buffer"
  end

  local scheduled = 0
  for _, client in ipairs(clients) do
    local ext_set = client_extensions(client)
    if ext_set then
      scheduled = scheduled + 1
      collect_files_async(ext_set, function(files)
        if #files > 0 then
          send_did_open(client, bufnr, files, true)
        end
      end)
    end
  end

  if scheduled == 0 then
    return false, "no attached client declares config.filetypes"
  end
  return true, scheduled
end

return M
