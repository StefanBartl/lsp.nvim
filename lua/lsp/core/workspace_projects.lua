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
---@see lsp.core.workspace_diagnostics
---@see lsp.core.handlers

local M = {}

local IS_WIN = vim.fn.has("win32") == 1

---@class LspNvim.WorkspaceProjects.Override
---@field path string # Normalized project folder, original casing.
---@field enabled boolean

--- Overrides keyed by the case-folded path (see `fold`).
---@type table<string, LspNvim.WorkspaceProjects.Override>
local overrides = {}
---@type boolean
local seeded = false

--- Pushes held back for a project that is OFF, newest per (client, file).
---@type table<string, { err: any, result: table, ctx: table, conf: table|nil }>
local held = {}

---@internal
--- Expand `~` and `$VAR`, unify separators, drop a trailing slash.
---@param path string
---@return string
local function norm(path)
  local p = vim.fs.normalize(path)
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
--- Whether `path` is `dir` or lies below it. Both must already be folded.
---@param path string
---@param dir string
---@return boolean
local function within(path, dir)
  return path == dir or path:sub(1, #dir + 1) == dir .. "/"
end

--- Whether `path` is `dir` or lies below it, spelling-insensitively (`~`,
--- `$VAR`, separators, and case on Windows).
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
      local p = norm(path)
      overrides[fold(p)] = { path = p, enabled = enabled }
    end
  end
end

--- The override that governs `path`: the most specific project folder that
--- contains it.
---@param path string
---@return boolean|nil enabled # nil when no override covers it.
---@return string|nil project # The governing project folder.
function M.state_of(path)
  if next(overrides) == nil or type(path) ~= "string" or path == "" then
    return nil, nil
  end
  local p = fold(norm(path))
  local best ---@type string|nil
  for key in pairs(overrides) do
    if within(p, key) and (best == nil or #key > #best) then
      best = key
    end
  end
  if best == nil then
    return nil, nil
  end
  return overrides[best].enabled, overrides[best].path
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

--- Turn a user-typed project into a folder.
---
--- Accepts `.` (the project root of the cwd: the nearest `.git` ancestor, else
--- the cwd itself), a bare name (a folder under `$REPOS_DIR`), or any path with
--- `~` and `$VAR` expanded. Refuses anything that is not an existing
--- directory, so a typo cannot silently create an override that matches
--- nothing.
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
    local expanded = norm(arg)
    local repos = vim.env.REPOS_DIR
    if not expanded:find("/", 1, true) and repos and repos ~= "" then
      local under = norm(repos) .. "/" .. expanded
      if vim.fn.isdirectory(under) == 1 then
        candidate = under
      end
    end
    candidate = candidate or expanded
  end

  if vim.fn.isdirectory(candidate) ~= 1 then
    return nil, ("not a directory: %s"):format(candidate)
  end
  return norm(candidate), nil
end

--- The folders `resolve` would accept by bare name: the directories directly
--- under `$REPOS_DIR`, dot-directories excluded.
---@return string[]
function M.repo_names()
  local repos = vim.env.REPOS_DIR
  if not repos or repos == "" then
    return {}
  end
  local names = {}
  local ok, iter = pcall(vim.fs.dir, norm(repos))
  if not ok then
    return {}
  end
  for name, kind in iter do
    if kind == "directory" and name:sub(1, 1) ~= "." then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

---@param project string
---@param value boolean
---@return nil
function M.set(project, value)
  local p = norm(project)
  overrides[fold(p)] = { path = p, enabled = value and true or false }
  if value then
    M.release(p)
  else
    M.purge(p)
  end
end

--- Drop a project's override, so the global switch governs it again.
---@param project string
---@param global boolean # The global switch, which decides release vs purge.
---@return boolean removed
function M.clear(project, global)
  local p = norm(project)
  local key = fold(p)
  if overrides[key] == nil then
    return false
  end
  overrides[key] = nil
  if global then
    M.release(p)
  else
    M.purge(p)
  end
  return true
end

-- --------------------------------------------------------------------------
-- Publish gate
-- --------------------------------------------------------------------------

---@internal
--- Whether a loaded buffer holds `fname`. Compared by name rather than
--- resolved through `vim.uri_to_bufnr`, which would *create* the buffer.
---@param fname string
---@return boolean
local function buffer_loaded(fname)
  local want = fold(norm(fname))
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" and fold(norm(name)) == want then
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
  if M.state_of(fname) ~= false then
    return false
  end
  if buffer_loaded(fname) then
    return false
  end

  held[tostring(ctx.client_id) .. "\0" .. result.uri] = {
    err = err,
    result = result,
    ctx = ctx,
    conf = conf,
  }
  return true
end

---@internal
---@param p { err: any, result: table, ctx: table, conf: table|nil }
---@return nil
local function replay(p)
  if vim.lsp.get_client_by_id(p.ctx.client_id) == nil then
    return
  end
  local handler = vim.lsp.handlers["textDocument/publishDiagnostics"]
  if type(handler) == "function" then
    pcall(handler, p.err, p.result, p.ctx, p.conf)
  end
end

--- Deliver what was held for `project`, for every file that is no longer gated.
---@param project string
---@return integer count
function M.release(project)
  local count = 0
  for key, p in pairs(held) do
    local ok, fname = pcall(vim.uri_to_fname, p.result.uri)
    if ok and M.contains(project, fname) and M.state_of(fname) ~= false then
      held[key] = nil
      count = count + 1
      replay(p)
    end
  end
  return count
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
  local key = tostring(client.id) .. "\0" .. uri
  local p = held[key]
  if p then
    held[key] = nil
    replay(p)
  end
end

--- Clear the diagnostics already showing for `project`'s files that have no
--- loaded buffer -- the leftovers of a workspace scan, which is what switching
--- a project OFF is meant to get rid of. Open files keep theirs.
---@param project string
---@return integer count # Buffers cleared.
function M.purge(project)
  local count = 0
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if not vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" and M.contains(project, name) and #vim.diagnostic.get(bufnr) > 0 then
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
  for _ in pairs(held) do
    n = n + 1
  end
  return n
end

return M
