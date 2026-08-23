---@module 'lsp.integrations.cmp'
---@brief nvim-cmp completion capabilities.
---@description
--- The completion capabilities are the single most consequential contribution
--- in this layer: without them servers advertise a far poorer completion
--- protocol and the editor quietly feels worse, with nothing pointing at the
--- cause. That is what roadmap finding B1 was -- a broken merge that silently
--- fell back.
---
--- Silent when absent, like `lsp.integrations.blink`: since `pack.completion`
--- made both engines genuinely selectable (2026-08-23), an absent nvim-cmp is
--- no longer evidence of anything -- it may just mean the user chose blink.
--- `core.capabilities.get()` still raises its own loud error if *no*
--- contributor produced completion capabilities at all, which is where B1
--- stays caught.
---
---@see lsp.integrations
---@see lsp.core.capabilities

local M = {}

---@type string
M.plugin = "nvim-cmp"

---@type boolean
M.hard = false

---@type string
M.note = "completion capabilities (cmp_nvim_lsp)"

---@internal
---@return table|nil
local function cmp_lsp()
  local ok, mod = pcall(require, "cmp_nvim_lsp")
  if ok and type(mod) == "table" and type(mod.default_capabilities) == "function" then
    return mod
  end
  return nil
end

---@return boolean
function M.available()
  return cmp_lsp() ~= nil
end

--- Merge nvim-cmp's capabilities in.
---@param caps table
---@return table|nil caps
---@return LspCaps.Warning[]|nil warnings
function M.capabilities(caps)
  local mod = cmp_lsp()
  if mod == nil then
    return nil, nil
  end

  local merged = vim.tbl_deep_extend("force", caps, mod.default_capabilities())
  if not (merged.textDocument and merged.textDocument.completion) then
    return merged,
      { { level = "warn", msg = "nvim-cmp loaded but contributed no completion capabilities!" } }
  end
  return merged, nil
end

return M
