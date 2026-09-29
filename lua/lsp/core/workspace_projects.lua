---@module 'lsp.core.workspace_projects'
---@brief Per-project overrides for workspace-wide diagnostics.
---@description
--- `lsp.core.workspace_diagnostics` has one global switch, but the question it
--- answers is not global: a 900-file Markdown vault and a 40-file plugin want
--- different answers in the same session, and the vault only grows. Raising
--- `max_files` is a postponement, not an answer. A project override says "for
--- anything under this folder, ignore the global switch".
---
--- An override does two things, because "workspace diagnostics" has two halves:
---
---   * **populate** -- what `lsp.core.workspace_diagnostics` does: `didOpen`
---     for every file of the workspace. Skipped for a project that is OFF,
---     *before* the walk starts, so the `max_files` warning cannot fire for it
---     either.
---   * **publish** -- what a server does on its own. marksman, measured on a
---     897-file vault, pushes diagnostics for every file it indexed whether or
---     not anyone sent it a `didOpen` -- ten warnings in ten files with one
---     buffer open, identical with and without the populate. Switching the
---     populate off alone therefore left the workspace-wide noise exactly where
---     it was. `hold_push` (called first thing by the `publishDiagnostics`
---     wrapper in `lsp.core.handlers`) holds back a push for a file nobody has
---     open, and `release` replays what was held when the project is switched
---     back on.
---
--- Files you have open are never held: this is about the ones you have not.
---
--- Overrides come from `attach.workspace_diagnostics_projects` at startup and
--- from `:Lsp workspace <action> <project>` at runtime. The runtime one wins
--- and is not persisted -- same contract as the global switch.
---
--- ## Two kinds of path, two kinds of normalization
---
--- A *project* string comes from a person or a config file and may say `~` or
--- `$REPOS_DIR/x`: it is expanded. A *file* path comes from a buffer name or a
--- URI and is taken literally: `vim.fs.normalize` expands `$VAR` in whatever it
--- is given, so a file that happens to live under a folder literally named
--- `$HOME` would otherwise be matched against the wrong project.
---
---@see lsp.core.workspace_diagnostics
---@see lsp.core.handlers

local M = {}

local IS_WIN = vim.fn.has("win32") == 1

--- How many held pushes a replay delivers per event-loop tick. A vault of 900
--- files replayed in one go is one long stall; the first chunk is synchronous
--- (so a small project is fully replayed when the call returns), the rest
--- follows on `vim.schedule`.
---@type integer
M.REPLAY_CHUNK = 100

---@class LspNvim.WorkspaceProjects.Override
---@field path string # Normalized project folder, original casing.
---@field enabled boolean

---@class LspNvim.WorkspaceProjects.Held
---@field err any
---@field result table
---@field ctx table
---@field conf table|nil

--- Overrides keyed by the case-folded path (see `fold`).
---@type table<string, LspNvim.WorkspaceProjects.Override>
local overrides = {}
---@type boolean
local seeded = false

--- Pushes held back for a project that is OFF: `uri -> client id -> push`,
--- newest per (client, file). Keyed by URI first so that a new push can drop
--- the entries of clients that are gone (a restarted server gets a new id and
--- would otherwise leave its old ones behind for the session).
---@type table<string, table<integer, LspNvim.WorkspaceProjects.Held>>
local held = {}

---@internal
--- Unify separators and drop a trailing slash. `expand` also expands `~` and
--- `$VAR` -- only ever for a string a person or a config file wrote.
---@param path string
---@param expand? boolean
---@return string
local function norm(path, expand)
  local p = vim.fs.normalize(path, { expand_env = expand == true })
  if #p > 1 and p:sub(-1) == "/" and not p:match("^%a:/$") then
    p = p:sub(1, -2)
  end
  return p
end

---@internal
--- Windows paths compare case-insensitively.
---@param path string
---@return string
local function fold(path)
  return IS_WIN and path:lower() or path
end

---@internal
--- Whether `path` is `dir` or lies below it. Both must already be folded. A
--- `dir` that ends in a slash (`/`, `C:/`) is a root: everything is below it.
---@param path string
---@param dir string
---@return boolean
local function within(path, dir)
  if path == dir then
    return true
  end
  local prefix = dir:sub(-1) == "/" and dir or dir .. "/"
  return path:sub(1, #prefix) == prefix
end

--- Whether `path` is `dir` or lies below it, ignoring separator style and, on
--- Windows, case. Neither is expanded: `dir` is a project as `resolve` or
--- `list` returned it, `path` is a file.
---@param dir string
---@param path string
---@return boolean
function M.contains(dir, path)
  return within(fold(norm(path)), fold(norm(dir)))
end

---@internal
---@return boolean
local function has_closed()
  for _, o in pairs(overrides) do
    if not o.enabled then
      return true
    end
  end
  return false
end

-- --------------------------------------------------------------------------
-- State
-- --------------------------------------------------------------------------

--- Seed the overrides from config. Once, like `workspace_diagnostics.seed`: a
--- runtime change must not be clobbered by a later re-entry into setup.
---@param map table<string, boolean>|nil
---@return nil
function M.seed(map)
  if seeded then
    return
  end
  seeded = true
  for path, enabled in pairs(map or {}) do
    if type(path) == "string" and path ~= "" and type(enabled) == "boolean" then
      local p = norm(path, true)
      overrides[fold(p)] = { path = p, enabled = enabled }
    end
  end
end

---@internal
--- `state_of` for a path that is already normalized and folded.
---@param folded string
---@return boolean|nil enabled
---@return string|nil project
local function state_of_folded(folded)
  local best ---@type string|nil
  for key in pairs(overrides) do
    if within(folded, key) and (best == nil or #key > #best) then
      best = key
    end
  end
  if best == nil then
    return nil, nil
  end
  return overrides[best].enabled, overrides[best].path
end

--- The override that governs the file or folder `path`: the most specific
--- project folder that contains it.
---@param path string
---@return boolean|nil enabled # nil when no override covers it.
---@return string|nil project # The governing project folder.
function M.state_of(path)
  if next(overrides) == nil or type(path) ~= "string" or path == "" then
    return nil, nil
  end
  return state_of_folded(fold(norm(path)))
end

--- Whether workspace diagnostics apply to `path`: the override if there is
--- one, the global switch otherwise.
---@param path string
---@param global boolean # The global switch.
---@return boolean enabled
---@return "project"|"global" source
function M.effective(path, global)
  local enabled = M.state_of(path)
  if enabled ~= nil then
    return enabled, "project"
  end
  return global, "global"
end

--- Whether any override turns a project ON. With the global switch off this is
--- the only way an attach could still populate something.
---@return boolean
function M.any_enabled()
  for _, o in pairs(overrides) do
    if o.enabled then
      return true
    end
  end
  return false
end

--- All overrides, sorted by path.
---@return LspNvim.WorkspaceProjects.Override[]
function M.list()
  local out = {}
  for _, o in pairs(overrides) do
    out[#out + 1] = { path = o.path, enabled = o.enabled }
  end
  table.sort(out, function(a, b)
    return a.path < b.path
  end)
  return out
end

--- Turn a user-typed project into an absolute folder.
---
--- Accepts `.` (the project root of the cwd: the nearest `.git` ancestor, else
--- the cwd itself), a bare name (a folder under `$REPOS_DIR`, else one under the
--- cwd), or any path with `~` and `$VAR` expanded. Refuses anything that is not
--- an existing directory, so a typo cannot silently create an override that
--- matches nothing. The result is always absolute: a relative key would never
--- equal a buffer's absolute name and the override would do nothing.
---@param arg string|nil
---@return string|nil path
---@return string|nil err
function M.resolve(arg)
  if type(arg) ~= "string" or arg == "" then
    return nil, "no project given"
  end

  local candidate ---@type string|nil
  if arg == "." then
    local cwd = vim.uv.cwd() or vim.fn.getcwd()
    local finder = require("lib.nvim.fs.find_root")({ markers = { ".git" } })
    candidate = finder.find(cwd) or cwd
  else
    local expanded = norm(arg, true)
    local repos = vim.env.REPOS_DIR
    if not expanded:find("/", 1, true) and repos and repos ~= "" then
      local under = norm(repos, true) .. "/" .. expanded
      if vim.fn.isdirectory(under) == 1 then
        candidate = under
      end
    end
    candidate = candidate or expanded
  end

  if vim.fn.isdirectory(candidate) ~= 1 then
    return nil, ("not a directory: %s"):format(candidate)
  end
  return norm(vim.fn.fnamemodify(candidate, ":p")), nil
end

--- The folders `resolve` would accept by bare name: the directories directly
--- under `$REPOS_DIR` (a symlink or junction to one counts), dot-directories
--- excluded.
---@return string[]
function M.repo_names()
  local repos = vim.env.REPOS_DIR
  if not repos or repos == "" then
    return {}
  end
  local base = norm(repos, true)
  local names = {}
  local ok, iter = pcall(vim.fs.dir, base)
  if not ok then
    return {}
  end
  for name, kind in iter do
    if name:sub(1, 1) ~= "." then
      if
        kind == "directory" or (kind == "link" and vim.fn.isdirectory(base .. "/" .. name) == 1)
      then
        names[#names + 1] = name
      end
    end
  end
  table.sort(names)
  return names
end

---@param project string
---@param value boolean
---@return nil
function M.set(project, value)
  local p = norm(project, true)
  overrides[fold(p)] = { path = p, enabled = value and true or false }
  -- Every file under `p` is governed by this override or a more specific one,
  -- so the global switch cannot matter for what is released or purged here.
  if value then
    M.release(p, true)
  else
    M.purge(p, true)
  end
end

--- Drop a project's override, so the global switch governs it again.
---
--- Both directions run: what is now allowed is replayed, what is now gated (by
--- a broader override, or by the global switch being off) is cleared.
---@param project string
---@param global boolean # The global switch.
---@return boolean removed
function M.clear(project, global)
  local p = norm(project, true)
  local key = fold(p)
  if overrides[key] == nil then
    return false
  end
  overrides[key] = nil
  M.release(p, global)
  M.purge(p, global)
  return true
end

-- --------------------------------------------------------------------------
-- Publish gate
-- --------------------------------------------------------------------------

---@internal
--- Whether a loaded buffer holds the file `folded` (normalized and folded).
--- Compared by name rather than resolved through `vim.uri_to_bufnr`, which
--- would *create* the buffer.
---@param folded string
---@return boolean
local function buffer_loaded(folded)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" and fold(norm(name)) == folded then
        return true
      end
    end
  end
  return false
end

--- Called by the `publishDiagnostics` wrapper before anything else. Holds a
--- push back when its file belongs to a project that is OFF and nobody has the
--- file open.
---
--- An empty push always passes: it only ever clears, and holding it would
--- leave stale diagnostics on a buffer that was unloaded since.
---@param err any
---@param result table|nil
---@param ctx table|nil
---@param conf table|nil
---@return boolean held # true: the caller must not forward this push.
function M.hold_push(err, result, ctx, conf)
  if not has_closed() then
    return false
  end
  if type(result) ~= "table" or type(result.uri) ~= "string" or type(ctx) ~= "table" then
    return false
  end
  if type(result.diagnostics) ~= "table" or #result.diagnostics == 0 then
    return false
  end

  local ok, fname = pcall(vim.uri_to_fname, result.uri)
  if not ok or type(fname) ~= "string" then
    return false
  end
  local folded = fold(norm(fname))
  if state_of_folded(folded) ~= false then
    return false
  end
  if buffer_loaded(folded) then
    return false
  end

  local by_client = held[result.uri]
  if by_client == nil then
    by_client = {}
    held[result.uri] = by_client
  end
  -- A server that was restarted has a new id; its old push for this file can
  -- never be replayed (`replay` needs the client) and would sit here forever.
  for id in pairs(by_client) do
    if id ~= ctx.client_id and vim.lsp.get_client_by_id(id) == nil then
      by_client[id] = nil
    end
  end
  by_client[ctx.client_id] = { err = err, result = result, ctx = ctx, conf = conf }
  return true
end

---@internal
---@param p LspNvim.WorkspaceProjects.Held
---@return nil
local function replay(p)
  if vim.lsp.get_client_by_id(p.ctx.client_id) == nil then
    return
  end
  local handler = vim.lsp.handlers["textDocument/publishDiagnostics"]
  if type(handler) == "function" then
    -- Through the wrapper on purpose: if the file has been gated again since,
    -- `hold_push` simply holds it again.
    pcall(handler, p.err, p.result, p.ctx, p.conf)
  end
end

---@internal
--- Deliver `batch` in chunks: `M.REPLAY_CHUNK` now, the rest a tick at a time.
---@param batch LspNvim.WorkspaceProjects.Held[]
---@param from integer
---@return nil
local function replay_chunked(batch, from)
  local last = math.min(from + M.REPLAY_CHUNK - 1, #batch)
  for i = from, last do
    replay(batch[i])
  end
  if last < #batch then
    vim.schedule(function()
      replay_chunked(batch, last + 1)
    end)
  end
end

--- Deliver what was held for `project`, for every file that is now allowed.
---@param project string
---@param global boolean # The global switch.
---@return integer count # Pushes handed over (the rest of a large batch follows).
function M.release(project, global)
  ---@type LspNvim.WorkspaceProjects.Held[]
  local batch = {}
  for uri, by_client in pairs(held) do
    local ok, fname = pcall(vim.uri_to_fname, uri)
    if ok and M.contains(project, fname) and M.effective(fname, global) then
      for id, p in pairs(by_client) do
        batch[#batch + 1] = p
        by_client[id] = nil
      end
      held[uri] = nil
    end
  end
  replay_chunked(batch, 1)
  return #batch
end

--- Deliver the held push for a buffer that has just been opened, so a file
--- opened inside a gated project shows its diagnostics without waiting for the
--- server's next push.
---@param client vim.lsp.Client
---@param bufnr integer
---@return nil
function M.release_buffer(client, bufnr)
  if next(held) == nil then
    return
  end
  local ok, uri = pcall(vim.uri_from_bufnr, bufnr)
  if not ok then
    return
  end
  local by_client = held[uri]
  local p = by_client and by_client[client.id]
  if p then
    by_client[client.id] = nil
    if next(by_client) == nil then
      held[uri] = nil
    end
    replay(p)
  end
end

--- Clear the diagnostics already showing for `project`'s files that have no
--- loaded buffer and are now gated -- the leftovers of a workspace scan, which
--- is what switching a project OFF is meant to get rid of. Open files keep
--- theirs, and so does a more specific project that is still ON.
---@param project string
---@param global boolean # The global switch.
---@return integer count # Buffers cleared.
function M.purge(project, global)
  local count = 0
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if not vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if
        name ~= ""
        and M.contains(project, name)
        and not M.effective(name, global)
        and #vim.diagnostic.get(bufnr) > 0
      then
        vim.diagnostic.reset(nil, bufnr)
        count = count + 1
      end
    end
  end
  return count
end

--- Number of pushes currently held. For status and tests.
---@return integer
function M.held_count()
  local n = 0
  for _, by_client in pairs(held) do
    for _ in pairs(by_client) do
      n = n + 1
    end
  end
  return n
end

return M
