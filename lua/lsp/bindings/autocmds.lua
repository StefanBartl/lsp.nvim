---@module 'lsp.bindings.autocmds'
---@brief Autocommand groups owned by lsp.nvim.
---@description
--- The plugin registers no autocommands yet. `LspAttach` wiring, the
--- format-on-save group and the diagnostics refresh all arrive with roadmap
--- phases 2 and 3; they belong here, not scattered across the modules that
--- happen to need them.
---
--- What already exists is the group name and `clear()`, so the group is
--- reloadable from the first handler onward -- a group created ad hoc by
--- whoever registers first is the thing that later cannot be cleanly reset.
---
---@see lsp.bindings

local M = {}

--- Augroup every autocommand of this plugin is registered under. One group, so
--- `clear()` really removes all of them.
---@type string
M.GROUP = "lsp_nvim"

--- Create (or reset) the augroup and register the handlers.
---@param _cfg LspNvim.Config
---@return integer count # Autocommands registered.
function M.setup(_cfg)
  return 0
end

--- Remove every autocommand this plugin registered.
---@return nil
function M.clear()
  pcall(vim.api.nvim_del_augroup_by_name, M.GROUP)
end

return M
