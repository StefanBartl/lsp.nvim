---@module 'lsp.integrations.noice'
---@brief noice.nvim, cmdline and message UI.
---@description
--- Two touch points, both outside the core: `tools/ts_type_lookup` renders
--- through noice when it is there, and inc-rename's cmdline preview is a noice
--- preset. Presence reporting only here.
---
---@see lsp.integrations
---@see lsp.tools.ts_type_lookup

local M = {}

---@type string
M.plugin = "noice.nvim"

---@type boolean
M.hard = false

---@type string
M.note = "cmdline/message UI used by ts_type_lookup and inc-rename's preview"

---@return boolean
function M.available()
  return (pcall(require, "noice"))
end

return M
