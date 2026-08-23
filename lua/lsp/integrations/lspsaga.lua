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

--- Configure lspsaga. Called from the pack spec's `config`.
---
--- Almost everything is off: the breadcrumb is the reason this plugin is here.
--- Note `lightbulb.enable`, not `enabled` -- lspsaga reads
--- `saga.config.lightbulb.enable`, and the misspelling merged in as a dead
--- extra field while the lightbulb kept running on every cursor move (~214ms
--- in a startup sample, plus permanent load while editing).
---@return boolean ok
function M.configure()
  local ok, lspsaga = pcall(require, "lspsaga")
  if not ok then
    return false
  end

  lspsaga.setup({
    beacon = { enable = false },
    breadcrumb = { enable = true, show_file = true, folder_level = 1 },
    hover = { enable = false },
    lightbulb = { enable = false },
    rename = { enable = false },
    term_toggle = { enable = false },
  })
  return true
end

return M
