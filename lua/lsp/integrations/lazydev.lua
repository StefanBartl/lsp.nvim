---@module 'lsp.integrations.lazydev'
---@brief lazydev.nvim, loaded on the first Lua attach.
---@description
--- lazydev resolves the Lua library paths lua_ls needs for `require`. It is
--- required on attach rather than at setup so a session that never opens a Lua
--- file never pays for it -- which is also why `core/attach.lua` used to do it
--- inline, and why that line was one of the couplings the integration layer
--- had to take over.
---
--- Requiring is the whole integration: lazydev registers itself.
---
---@see lsp.integrations

local M = {}

---@type string
M.plugin = "lazydev.nvim"

---@type boolean
M.hard = false

---@type string
M.note = "lua_ls library resolution, loaded on the first Lua attach"

---@type boolean
local _enabled = true

---@return boolean
function M.available()
  return (pcall(require, "lazydev"))
end

--- Honor `attach.use_lazydev`.
---@param cfg LspNvim.Config
---@return nil
function M.setup(cfg)
  _enabled = cfg.attach.use_lazydev == true
end

--- Load lazydev the first time a Lua buffer gets a server.
---@param _client table
---@param bufnr integer
---@return nil
function M.on_attach(_client, bufnr)
  if not _enabled then
    return
  end
  if vim.bo[bufnr].filetype ~= "lua" then
    return
  end
  pcall(require, "lazydev")
end

return M
