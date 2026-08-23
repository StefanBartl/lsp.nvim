---@module 'lsp.integrations.blink'
---@brief blink.cmp completion capabilities.
---@description
--- The alternative completion engine. Contributes after nvim-cmp so that a
--- setup running both ends up with blink's view of the protocol -- which is
--- the order the original single capabilities function used.
---
--- Silent when absent, unlike the nvim-cmp adapter: blink is the alternative,
--- not the default, so its absence is not evidence of anything. Roadmap
--- section 15 leaves the choice between the two open; when it is made,
--- `completion.engine` belongs here.
---
---@see lsp.integrations
---@see lsp.integrations.cmp

local M = {}

---@type string
M.plugin = "blink.cmp"

---@type boolean
M.hard = false

---@type string
M.note = "completion capabilities (alternative to nvim-cmp)"

---@internal
---@return table|nil
local function blink()
  local ok, mod = pcall(require, "blink.cmp")
  if ok and type(mod) == "table" and type(mod.get_lsp_capabilities) == "function" then
    return mod
  end
  return nil
end

---@return boolean
function M.available()
  return blink() ~= nil
end

--- Merge blink.cmp's capabilities in.
---@param caps table
---@return table|nil caps
---@return LspCaps.Warning[]|nil warnings
function M.capabilities(caps)
  local mod = blink()
  if mod == nil then
    return nil, nil
  end
  return vim.tbl_deep_extend("force", caps, mod.get_lsp_capabilities(caps)), nil
end

return M
