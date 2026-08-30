---@module 'lsp.core.workspace_folders'
---@brief Runtime workspace folders: the multi-root / monorepo switcher.
---@description
--- LSP has a real multi-root mechanism -- a client carries a *list* of
--- workspace folders and accepts `workspace/didChangeWorkspaceFolders` to grow
--- or shrink it while running. Neovim ships `vim.lsp.buf.add_workspace_folder`,
--- `remove_workspace_folder` and `list_workspace_folders` for it, unbound and
--- undiscoverable. This module is the entry point over them.
---
--- It is deliberately *not* a fourth `lsp.core.root_scope` strategy. That
--- switch only reaches servers whose `root_dir` is a function -- `lua_ls` and
--- `marksman` here. `gopls`, `ts_ls`, `clangd` and `csharp` declare
--- `root_markers` and let Neovim resolve the root itself, with no hook to
--- intercept. A pinned root would silently not apply to exactly the servers a
--- monorepo needs it for. Workspace folders reach every server that says it
--- supports them, and reach it without a restart.
---
--- Three things the builtins do not do, and this module does:
---
--- 1. **Capability gate.** `vim.lsp.buf.add_workspace_folder` pushes to every
---    client attached to the buffer, whatever it declared. The LSP spec splits
---    the question in two: `workspace.workspaceFolders.supported` says the
---    server understands folders at all, `changeNotifications` says it wants
---    `didChangeWorkspaceFolders` at runtime. Only the second one licenses
---    what this module does, so both are checked and a client that fails
---    either is reported as skipped rather than notified into the void.
--- 2. **Client attribution.** `list_workspace_folders()` flattens every
---    client's folders into one nameless list. Which client actually holds
---    which folder is the thing one wants to know when a jump does not
---    resolve, so `M.folders()` keeps it.
--- 3. **Honest feedback.** `Client:_add_workspace_folder` `print()`s on a
---    duplicate, and `vim.lsp.buf.remove_workspace_folder` notifies
---    "is not currently part of the workspace" *unconditionally* -- on success
---    too. Duplicates and unknown folders are therefore resolved here, before
---    the builtin is reached.
---
---@see lsp.core.root_scope
---@see lsp.bindings.actions

local uv = vim.uv or vim.loop

local M = {}

---@class LspNvim.WorkspaceFolder
---@field path string # Normalized, for display and comparison.
---@field raw string # Exactly as the client stores it -- what removal must be given.
---@field clients string[] # Names of the clients holding it.

---@class LspNvim.WorkspaceClient
---@field id integer
---@field name string
---@field root string|nil # The client's `root_dir`, normalized.
---@field folders string[] # Its workspace folders, normalized.
---@field switchable boolean # Accepts runtime folder changes.
---@field reason string|nil # Why not, when `switchable` is false.

---@internal
--- Normalize a path for comparison and display. `vim.fs.normalize` settles
--- separators and `~`; the trailing slash has to go separately, because a
--- folder stored as `C:/repo/` and one stored as `C:/repo` are the same place
--- and would otherwise never match.
---@param path string|nil
---@return string|nil
local function norm(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local out = vim.fs.normalize(path)
  -- Keep a bare root (`/`, `C:/`) intact; only strip a separator that has a
  -- path in front of it.
  out = out:gsub("(.)/+$", "%1")
  return out
end

---@internal
--- The buffer's starting directory: its file's parent, or the cwd for a buffer
--- that has no file yet.
---@param bufnr integer
---@return string
local function start_dir(bufnr)
  local name = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) or ""
  if name ~= "" then
    local dir = norm(vim.fs.dirname(name))
    if dir and vim.fn.isdirectory(dir) == 1 then
      return dir
    end
  end
  return norm(uv.cwd() or vim.fn.getcwd()) or "."
end

---@internal
--- Why a client cannot take a runtime folder change, or nil when it can.
---@param client vim.lsp.Client
---@return string|nil reason
local function unswitchable_reason(client)
  local caps = client.server_capabilities or {}
  local wf = caps.workspace and caps.workspace.workspaceFolders or nil
  if wf == nil then
    return "server declares no workspaceFolders support"
  end
  if wf.supported ~= true then
    return "workspaceFolders.supported is not true"
  end
  -- `changeNotifications` is `string|boolean`: a string is a registration id,
  -- `true` a plain yes. Absent or false means the server took its folders at
  -- initialize and does not want to hear about changes.
  if wf.changeNotifications == nil or wf.changeNotifications == false then
    return "server does not accept didChangeWorkspaceFolders"
  end
  return nil
end

--- Every client attached to the buffer, with its root, its folders, and
--- whether it can take a runtime change.
---@param bufnr integer|nil # Defaults to the current buffer.
---@return LspNvim.WorkspaceClient[]
function M.clients(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  ---@type LspNvim.WorkspaceClient[]
  local out = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    ---@type string[]
    local folders = {}
    for _, folder in ipairs(client.workspace_folders or {}) do
      local path = norm(folder.name)
      if path then
        folders[#folders + 1] = path
      end
    end

    local reason = unswitchable_reason(client)
    out[#out + 1] = {
      id = client.id,
      name = client.name,
      root = norm(client.root_dir),
      folders = folders,
      switchable = reason == nil,
      reason = reason,
    }
  end

  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

---@internal
--- The live client objects that accept a runtime folder change.
---@param bufnr integer
---@return vim.lsp.Client[]
local function switchable_clients(bufnr)
  ---@type vim.lsp.Client[]
  local out = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if unswitchable_reason(client) == nil then
      out[#out + 1] = client
    end
  end
  return out
end

--- The workspace folders currently held by the buffer's clients, deduplicated
--- across them and carrying the client names.
---
--- `raw` is kept alongside `path` because removal is a name comparison inside
--- Neovim: `Client:_remove_workspace_folder` matches `folder.name == dir`
--- literally, so handing it the normalized spelling would notify the server
--- and then fail to drop the entry locally.
---@param bufnr integer|nil # Defaults to the current buffer.
---@return LspNvim.WorkspaceFolder[] # Sorted by path.
function M.folders(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  ---@type table<string, LspNvim.WorkspaceFolder>
  local index = {}
  ---@type LspNvim.WorkspaceFolder[]
  local out = {}

  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    for _, folder in ipairs(client.workspace_folders or {}) do
      local path = norm(folder.name)
      if path then
        local entry = index[path]
        if entry == nil then
          entry = { path = path, raw = folder.name, clients = {} }
          index[path] = entry
          out[#out + 1] = entry
        end
        entry.clients[#entry.clients + 1] = client.name
      end
    end
  end

  table.sort(out, function(a, b)
    return a.path < b.path
  end)
  return out
end

---@internal
--- Does `dir` contain any of `markers`?
---@param dir string
---@param markers string[]
---@return boolean
local function has_marker(dir, markers)
  for _, marker in ipairs(markers) do
    if uv.fs_stat(dir .. "/" .. marker) ~= nil then
      return true
    end
  end
  return false
end

---@internal
--- Immediate subdirectories of `dir` that look like projects, plus the same
--- one level down through the conventional container directories.
---
--- This is the half of the search an upward walk cannot do: from
--- `packages/api` the sibling `packages/web` is never above you, and it is the
--- single most common thing one wants to add in a monorepo. Bounded on
--- purpose -- one `readdir` of `dir` and one per container -- because an
--- unbounded descent would stat a whole repository to fill a picker.
---@param dir string
---@param markers string[]
---@param containers string[]
---@param push fun(path: string): nil
---@return nil
local function scan_children(dir, markers, containers, push)
  ---@type table<string, true>
  local is_container = {}
  for _, name in ipairs(containers) do
    is_container[name] = true
  end

  local ok, iter = pcall(vim.fs.dir, dir)
  if not ok or iter == nil then
    return
  end

  ---@type string[]
  local nested = {}
  for name, kind in iter do
    if kind == "directory" and name:sub(1, 1) ~= "." then
      local child = dir .. "/" .. name
      if has_marker(child, markers) then
        push(child)
      end
      if is_container[name] then
        nested[#nested + 1] = child
      end
    end
  end

  for _, container in ipairs(nested) do
    local ok_inner, inner = pcall(vim.fs.dir, container)
    if ok_inner and inner ~= nil then
      for name, kind in inner do
        if kind == "directory" and name:sub(1, 1) ~= "." then
          local child = container .. "/" .. name
          if has_marker(child, markers) then
            push(child)
          end
        end
      end
    end
  end
end

--- Directories worth offering as a workspace folder for this buffer.
---
--- Nearest first: every marker-bearing directory from the buffer's own
--- directory upward, then the sibling projects around the outermost one, then
--- the cwd and the roots the attached clients resolved for themselves.
--- Anything already a workspace folder is left out -- the list is what `add`
--- can still do, not an inventory.
---@param bufnr integer|nil # Defaults to the current buffer.
---@return string[]
function M.candidates(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local cfg = require("lsp.config").get()
  local markers = cfg.workspace.markers
  local containers = cfg.workspace.containers

  ---@type table<string, true>
  local seen = {}
  ---@type string[]
  local out = {}

  -- Already held folders are excluded rather than shown greyed out: the
  -- picker's only verb is "add", and an entry it cannot act on is noise.
  for _, folder in ipairs(M.folders(bufnr)) do
    seen[folder.path] = true
  end

  ---@param path string|nil
  local function push(path)
    local dir = norm(path)
    if dir == nil or seen[dir] then
      return
    end
    seen[dir] = true
    out[#out + 1] = dir
  end

  local from = start_dir(bufnr)

  -- Upward walk. The last marker directory found is the outermost one -- the
  -- monorepo root, when there is one -- and that is where the sibling scan
  -- starts.
  ---@type string|nil
  local outermost = nil
  if has_marker(from, markers) then
    push(from)
    outermost = from
  end
  for parent in vim.fs.parents(from) do
    local dir = norm(parent)
    if dir and has_marker(dir, markers) then
      push(dir)
      outermost = dir
    end
  end

  if outermost then
    scan_children(outermost, markers, containers, push)
  end

  push(uv.cwd() or vim.fn.getcwd())
  for _, entry in ipairs(M.clients(bufnr)) do
    push(entry.root)
  end

  return out
end

--- Add a directory to the workspace folders of every client on the buffer that
--- accepts a runtime change.
---@param dir string
---@param bufnr integer|nil # Defaults to the current buffer.
---@return boolean ok # true when at least one client took it.
---@return string[] added # Client names that took it.
---@return string[] skipped # `"name: reason"` for every client that did not.
function M.add(dir, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local path = norm(dir)
  if path == nil then
    return false, {}, { "no directory given" }
  end
  if vim.fn.isdirectory(path) ~= 1 then
    return false, {}, { ("%s is not a directory"):format(path) }
  end

  ---@type string[]
  local added, skipped = {}, {}

  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    local reason = unswitchable_reason(client)
    if reason then
      skipped[#skipped + 1] = ("%s: %s"):format(client.name, reason)
    else
      -- Checked here rather than left to `Client:_add_workspace_folder`, which
      -- answers a duplicate with a bare `print()` -- a message that lands in
      -- the message history and is attributed to nobody.
      local duplicate = false
      for _, folder in ipairs(client.workspace_folders or {}) do
        if norm(folder.name) == path then
          duplicate = true
          break
        end
      end

      if duplicate then
        skipped[#skipped + 1] = ("%s: already a workspace folder"):format(client.name)
      else
        local ok = pcall(function()
          client:_add_workspace_folder(path)
        end)
        if ok then
          added[#added + 1] = client.name
        else
          skipped[#skipped + 1] = ("%s: the client rejected the folder"):format(client.name)
        end
      end
    end
  end

  return #added > 0, added, skipped
end

--- Remove a directory from the workspace folders of the buffer's clients.
---
--- Takes the *normalized* path and finds each client's own spelling of it, so
--- a folder added under a different separator style still comes off.
---@param dir string
---@param bufnr integer|nil # Defaults to the current buffer.
---@return boolean ok # true when at least one client dropped it.
---@return string[] removed # Client names that dropped it.
---@return string[] skipped # `"name: reason"` for every client that did not.
function M.remove(dir, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local path = norm(dir)
  if path == nil then
    return false, {}, { "no directory given" }
  end

  ---@type string[]
  local removed, skipped = {}, {}

  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    ---@type string|nil
    local raw = nil
    for _, folder in ipairs(client.workspace_folders or {}) do
      if norm(folder.name) == path then
        raw = folder.name
        break
      end
    end

    if raw == nil then
      -- Silent: a client that never held the folder is not a failure, and
      -- listing every unrelated client would bury the ones that matter.
      local reason = unswitchable_reason(client)
      if reason then
        skipped[#skipped + 1] = ("%s: %s"):format(client.name, reason)
      end
    else
      local reason = unswitchable_reason(client)
      if reason then
        skipped[#skipped + 1] = ("%s: %s"):format(client.name, reason)
      else
        local ok = pcall(function()
          client:_remove_workspace_folder(raw)
        end)
        if ok then
          removed[#removed + 1] = client.name
        else
          skipped[#skipped + 1] = ("%s: the client rejected the removal"):format(client.name)
        end
      end
    end
  end

  return #removed > 0, removed, skipped
end

--- Report lines: the active root scope, then every attached client with the
--- root it resolved and the folders it holds.
---@param bufnr integer|nil # Defaults to the current buffer.
---@return string[]
function M.report(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local lines = { "lsp.nvim - roots and workspace folders", "" }

  local ok, root_scope = pcall(require, "lsp.core.root_scope")
  if ok then
    lines[#lines + 1] = ("root scope: %s"):format(root_scope.label(root_scope.get()))
  else
    lines[#lines + 1] = "root scope: (module unavailable)"
  end
  lines[#lines + 1] = ("buffer dir: %s"):format(start_dir(bufnr))
  lines[#lines + 1] = ""

  local clients = M.clients(bufnr)
  if #clients == 0 then
    lines[#lines + 1] = "No LSP client is attached to this buffer."
    return lines
  end

  for _, entry in ipairs(clients) do
    lines[#lines + 1] = ("%s (id %d)"):format(entry.name, entry.id)
    lines[#lines + 1] = ("  root:      %s"):format(entry.root or "-")
    lines[#lines + 1] = ("  switchable: %s"):format(
      entry.switchable and "yes" or ("no (%s)"):format(entry.reason or "?")
    )
    if #entry.folders == 0 then
      lines[#lines + 1] = "  folders:   (none)"
    else
      lines[#lines + 1] = "  folders:"
      for _, folder in ipairs(entry.folders) do
        lines[#lines + 1] = "    " .. folder
      end
    end
  end

  if #switchable_clients(bufnr) == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "No client on this buffer accepts runtime workspace-folder changes;"
    lines[#lines + 1] = "`:Lsp root add` would have nothing to send to."
  end

  return lines
end

--- Report lines: the directories `:Lsp root add` would offer.
---@param bufnr integer|nil # Defaults to the current buffer.
---@return string[]
function M.candidates_report(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local lines = { "lsp.nvim - workspace folder candidates", "" }
  local candidates = M.candidates(bufnr)

  if #candidates == 0 then
    lines[#lines + 1] = "Nothing to add: every candidate is already a workspace folder."
    return lines
  end

  lines[#lines + 1] = "Nearest first. `:Lsp root add` picks from exactly this list."
  lines[#lines + 1] = ""
  for i, dir in ipairs(candidates) do
    lines[#lines + 1] = ("%2d. %s"):format(i, dir)
  end
  return lines
end

return M
