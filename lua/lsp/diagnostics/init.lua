---@module 'lsp.diagnostics'
--- Entry point for diagnostics helpers (commands + keymaps).

local commands = require("lsp.diagnostics.commands")

local M = {}

--- Setup diagnostics helpers.
---
--- Commands only. The diagnostics keymaps (`<leader>wq`, `<leader>lq`,
--- `]d`/`[d`, `]q`/`[q`) moved into `config/KEYMAPS.lua` in migration phase 3 --
--- this module used to bind them here while `bindings/mappings/trouble.lua` in
--- the config bound two of the same keys, which is the duplication the
--- catalogue removes.
---@return nil
function M.setup()
  commands.enable()
end

return M
