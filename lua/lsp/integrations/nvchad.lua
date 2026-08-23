---@module 'lsp.integrations.nvchad'
---@brief NvChad's lspconfig bridge.
---@description
--- NvChad ships its own `on_attach`/`on_init`/`capabilities`. The core used to
--- `pcall(require, "nvchad.configs.lspconfig")` in three separate places --
--- twice in `core/attach.lua`, once in `core/capabilities.lua` -- which is
--- exactly the coupling the integration layer exists to remove.
---
--- Contributes first, on purpose: `tbl_deep_extend("force", ...)` lets later
--- contributors win, and the completion engine should win over NvChad's
--- defaults. That was the order in the original single function and it is
--- preserved here.
---
---@see lsp.integrations

local M = {}

--- Plugin this adapter wraps, for the health report.
---@type string
M.plugin = "nvchad"

---@type boolean
M.hard = false

---@type string
M.note = "on_attach/on_init/capabilities bridge"

---@internal
---@return table|nil
local function nvlsp()
  local ok, mod = pcall(require, "nvchad.configs.lspconfig")
  if ok and type(mod) == "table" then
    return mod
  end
  return nil
end

---@return boolean
function M.available()
  return nvlsp() ~= nil
end

--- Merge NvChad's capabilities in.
---@param caps table
---@return table|nil caps
---@return LspCaps.Warning[]|nil warnings
function M.capabilities(caps)
  local mod = nvlsp()
  if mod == nil or type(mod.capabilities) ~= "table" then
    return nil, nil
  end
  return vim.tbl_deep_extend("force", caps, mod.capabilities), nil
end

--- Hand the client to NvChad's own on_init.
---@param client table
---@return nil
function M.on_init(client)
  local mod = nvlsp()
  if mod ~= nil and type(mod.on_init) == "function" then
    pcall(mod.on_init, client)
  end
end

--- Hand the client to NvChad's own on_attach.
---@param client table
---@param bufnr integer
---@return nil
function M.on_attach(client, bufnr)
  local mod = nvlsp()
  if mod ~= nil and type(mod.on_attach) == "function" then
    pcall(mod.on_attach, client, bufnr)
  end
end

return M
