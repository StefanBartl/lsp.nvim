---@module 'lsp.integrations.lspsaga'
---@brief lspsaga.nvim, breadcrumbs.
---@description
--- Presence reporting only. Everything but the breadcrumb is switched off in
--- this setup, nothing in the core touches lspsaga, and its configuration is a
--- lazy spec in the config -- moving that is the pack layer's job (roadmap
--- section 6, phase 5), not this one.
---
--- It has an adapter anyway so the health report has one row per plugin the
--- umbrella claims to cover. A plugin the umbrella names but cannot report on
--- is a gap in exactly the place someone looks when something is missing.
---
---@see lsp.integrations

local M = {}

---@type string
M.plugin = "lspsaga.nvim"

---@type boolean
M.hard = false

---@type string
M.note = "breadcrumbs; configured in the config's plugin spec"

---@return boolean
function M.available()
  return (pcall(require, "lspsaga"))
end

return M
