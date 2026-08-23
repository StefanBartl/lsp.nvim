---@module 'lsp.integrations.picker'
---@brief The symbol and diagnostics picker.
---@description
--- Currently fzf-lua, hardwired: the catalogue's four picker entries are
--- `<cmd>FzfLua …<cr>` strings, exactly as the config had them.
---
--- Roadmap section 7 wants this to become a real abstraction over fzf-lua,
--- telescope, snacks and pickers.nvim. It is not one yet, and this adapter does
--- not pretend otherwise -- an indirection with a single implementation behind
--- it buys nothing and hides that the choice has not been made.
---
---@see lsp.config.KEYMAPS
---@see lsp.integrations

local M = {}

---@type string
M.plugin = "fzf-lua"

---@type boolean
M.hard = false

---@type string
M.note = "symbol/diagnostics pickers; not yet abstracted over other backends"

---@return boolean
function M.available()
  return (pcall(require, "fzf-lua"))
end

return M
