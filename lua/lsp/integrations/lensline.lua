---@module 'lsp.integrations.lensline'
---@brief lensline.nvim, codelens-style inline info.
---@description
--- Presence reporting only, for the same reason as the lspsaga adapter: the
--- core does not touch it and its configuration is a lazy spec, but the health
--- report should be able to answer whether it is installed.
---
---@see lsp.integrations
---@see lsp.integrations.lspsaga

local M = {}

---@type string
M.plugin = "lensline.nvim"

---@type boolean
M.hard = false

---@type string
M.note = "inline codelens-style info; configured in the config's plugin spec"

---@return boolean
function M.available()
  return (pcall(require, "lensline"))
end

--- Configure lensline. Called from the pack spec's `config`.
---@return boolean ok
function M.configure()
  local ok, lensline = pcall(require, "lensline")
  if not ok then
    return false
  end

  lensline.setup({
    profiles = {
      {
        name = "minimal",
        style = {
          placement = "inline",
          prefix = "",
          -- Only render lenses for the focused function.
          render = "focused",
        },
      },
    },
  })
  return true
end

return M
