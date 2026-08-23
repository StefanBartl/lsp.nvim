---@module 'lsp.integrations.mason'
---@brief mason.nvim package management.
---@description
--- The `ensure_install` machinery lives in `lsp/integrations/mason/` (roadmap
--- decision E2: package management for language tooling is what an LSP
--- umbrella owns, not lib.nvim). This file is the adapter face of it: presence
--- for the health report, and the registration API other plugins call.
---
--- Roadmap decision E2 also designs a `register(kind, packages)` entry point so
--- `dap.nvim` can have its adapters installed through the same dedup pass
--- instead of the two racing each other into "Package is already installing".
--- That does not exist yet: `ensure_install` has `enable_lsp`/`enable_dap`/
--- `enable_linters`/`enable_formatters` and its DAP defaults still ship here.
--- Writing the entry point before anything calls it would be an API with no
--- caller, so it waits until dap.nvim is ready to use it.
---
---@see lsp.integrations.mason.ensure_install
---@see lsp.integrations

local M = {}

---@type string
M.plugin = "mason.nvim"

---@type boolean
M.hard = false

---@type string
M.note = "package management; only needed when mason.ensure_install is on"

---@return boolean
function M.available()
  return (pcall(require, "mason"))
end

return M
