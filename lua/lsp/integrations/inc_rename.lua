---@module 'lsp.integrations.inc_rename'
---@brief inc-rename.nvim, one of the two rename backends.
---@description
--- Which backend the rename action uses is `rename.provider`'s decision, taken
--- in `bindings/actions.lua`; this adapter only answers whether inc-rename is
--- installed, which is what `"auto"` needs to know.
---
--- inc-rename's own configuration -- including the post_hook that writes every
--- buffer an LSP rename touched -- lives in `lsp.integrations.inc_rename.setup`
--- and is applied from the pack spec.
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

--- Configure inc-rename. Called from the pack spec's `config`.
---@return boolean ok
function M.configure()
  return require("lsp.integrations.inc_rename.setup").configure()
end

return M
