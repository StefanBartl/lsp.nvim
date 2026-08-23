---@module 'lsp.core.root_scope'
--- Global switch controlling how LSP servers resolve their project root.
--- Consumed by per-server root resolvers (e.g. lsp.servers.lua_ls.rootresolver)
--- and driven by lsp.core.root_scope_picker / <leader>lsp.

local M = {}

---@alias LspRootScope "cwd"|"git"|"path"

---@type LspRootScope[]
M.SCOPES = { "cwd", "git", "path" }

---@type table<LspRootScope, string>
M.LABELS = {
  cwd = "cwd — aktuelles Arbeitsverzeichnis",
  git = "git — nächstes Repo-Root (.git/.hg/.svn)",
  path = "path — Verzeichnis der aktuellen Datei",
}

---@type { scope: LspRootScope }
local state = {
  scope = "git",
}

--- Currently active root scope.
---@return LspRootScope
function M.get()
  return state.scope
end

--- Human-readable label for a scope (defaults to the active scope).
---@param scope LspRootScope|nil
---@return string
function M.label(scope)
  scope = scope or state.scope
  return M.LABELS[scope] or scope
end

--- Switch the active root scope. Fires `User LspRootScopeChanged` on change
--- so interested servers (lua_ls) can recompute already-attached clients.
---@param scope LspRootScope
---@return boolean ok
function M.set(scope)
  if not vim.tbl_contains(M.SCOPES, scope) then
    return false
  end
  if state.scope == scope then
    return true
  end

  state.scope = scope
  vim.api.nvim_exec_autocmds("User", {
    pattern = "LspRootScopeChanged",
    data = { scope = scope },
  })
  return true
end

return M
