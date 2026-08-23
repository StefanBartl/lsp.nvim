---@module 'lsp.integrations.inc_rename'
---@brief inc-rename.nvim, one of the two rename backends.
---@description
--- Which backend the rename action uses is `rename.provider`'s decision, taken
--- in `bindings/actions.lua`; this adapter only answers whether inc-rename is
--- installed, which is what `"auto"` needs to know.
---
--- inc-rename's own `setup()` (including the post_hook that saves the touched
--- buffers) stays in the config for now, together with its plugin spec.
---
---@see lsp.bindings.actions
---@see lsp.integrations

local M = {}

---@type string
M.plugin = "inc-rename.nvim"

---@type boolean
M.hard = false

---@type string
M.note = 'rename backend when rename.provider is "auto" or "inc_rename"'

---@return boolean
function M.available()
  return (pcall(require, "inc_rename"))
end

return M
