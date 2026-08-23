---@module 'lsp.tools.deprecated_help.defaults'
--- The one default this feature has: `M.keymap = "<leader>oh"`, open help
--- for the last detected deprecated symbol in the current buffer.

local M = {}

-- Default mapping (can be overridden via setup opts)
---@type string
M.keymap = "<leader>oh" -- open help for last detected symbol in the current buffer

return M
