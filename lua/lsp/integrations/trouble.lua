---@module 'lsp.integrations.trouble'
---@brief trouble.nvim, the diagnostics UI.
---@description
--- Presence reporting only, deliberately. Trouble is driven entirely through
--- the keymap catalogue's `<cmd>Trouble …<cr>` entries, which stay inert until
--- pressed so the plugin manager can keep loading it on demand -- probing here
--- with `require` would force-load it at startup and undo that.
---
--- The Trouble *setup block* (preview split, index formatter) still lives in
--- the config's `plugins/trouble.lua`. Moving it means moving a lazy spec,
--- which is the pack layer's job (roadmap section 6, phase 5), not this one.
---
---@see lsp.config.KEYMAPS
---@see lsp.integrations

local M = {}

---@type string
M.plugin = "trouble.nvim"

---@type boolean
M.hard = false

---@type string
M.note = "diagnostics UI; driven from the keymap catalogue, setup still in the config's spec"

---@return boolean
function M.available()
  return (pcall(require, "trouble"))
end

return M
