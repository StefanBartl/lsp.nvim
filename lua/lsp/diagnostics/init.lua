---@module 'lsp.diagnostics'
--- Entry point for diagnostics helpers (commands + keymaps).

local commands = require("lsp.diagnostics.commands")
local keymaps = require("lsp.diagnostics.keymaps")

local M = {}

--- Setup diagnostics helpers.
---@return nil
function M.setup()
  commands.enable()
  keymaps.enable()
end

return M
