---@module 'lsp.integrations.picker'
---@brief The symbol and diagnostics picker.
---@description
--- Currently fzf-lua, hardwired: the catalogue's four picker entries are
--- `<cmd>FzfLua …<cr>` strings, exactly as the config had them, and
--- `:TypeDefPick` calls `fzf_lua.lsp_workspace_symbols` directly
--- (`lsp.tools.ts_type_lookup.symbol_picker`).
---
--- Roadmap section 7 wants this to become a real abstraction over fzf-lua,
--- telescope, snacks and pickers.nvim. It is not one yet, and this adapter does
--- not pretend otherwise -- an indirection with a single implementation behind
--- it buys nothing and hides that the choice has not been made.
---
--- Roadmap M4a removed the one place that used a *different* backend: the
--- symbol picker behind `:TypeDefPick` was hand-rolled Telescope. That is the
--- cheaper half of the same trade -- one backend everywhere beats an
--- abstraction over two.
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
