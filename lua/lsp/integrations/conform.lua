---@module 'lsp.integrations.conform'
---@brief conform.nvim, the formatter engine.
---@description
--- A thin re-export of `lsp.formatter.conform`, which owns the actual
--- `conform.setup()` call (LUA-03: a module that only forwards says so, and
--- names where the truth lives). It is here so the health report has one row
--- per third-party plugin and so the ownership question has a visible answer.
---
--- That ownership is roadmap finding B5: conform used to be configured twice,
--- once in the config's plugin spec and once here, with contradicting
--- `format_on_save` settings. It is settled -- `plugins/lsp.lua` carries an
--- explicit note that it deliberately has no `config` block, and this is the
--- single authoritative `conform.setup()`. The format-on-save autocommand is
--- ours (`lsp/formatter/init.lua`), never conform's own option.
---
---@see lsp.formatter.conform
---@see lsp.integrations

local M = {}

---@type string
M.plugin = "conform.nvim"

---@type boolean
M.hard = true

---@type string
M.note = "the formatter's primary engine; setup lives in lsp.formatter.conform"

---@return boolean
function M.available()
  return (pcall(require, "conform"))
end

return M
