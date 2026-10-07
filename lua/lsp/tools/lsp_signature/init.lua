---@module 'lsp.tools.lsp_signature'
--- LSP signature help / hover preview, toggled with <C-b> in Insert and Normal
--- mode. The key is the `signature_toggle` entry of `config/KEYMAPS.lua`
--- (bound by `bindings/keymaps.lua`, so it follows `keymaps.enable`, the
--- presets and `keymaps.map`); this module only owns what it opens.
--- - Normal mode: the popup opens and takes focus, so it can be scrolled and
---   copied from.
--- - Insert mode: the popup opens but focus stays in the buffer, so typing
---   continues uninterrupted.
--- - The popup is persistent; the same mapping closes it again.

local M = {}

--- Kept for the caller in `lsp.init`; the key itself is bound by the keymap
--- catalogue, so there is nothing to register here.
---@return nil
function M.setup() end

return M
