---@module 'lsp.diagnostics.quickfix'
--- Workspace-wide diagnostics via quickfix list.

local util = require("lsp.diagnostics.util")

---@class Lsp.Diagnostics.Quickfix
local M = {}

--- Populate quickfix list from diagnostics.
---@param opts Lsp.Diagnostics.ListOpts|nil
---@return nil
function M.to_qf(opts)
  opts = opts or {}
  local sev = util.to_severity(opts.severity)

  local qfopts = {
    open = (opts.open ~= false),
    bufnr = opts.bufnr,
    namespace = opts.namespace,
    severity = sev,
  }

  vim.diagnostic.setqflist(qfopts)
end

--- Jump to next quickfix entry.
---@return nil
function M.next_qf()
  pcall(vim.cmd, "cnext")
end

--- Jump to previous quickfix entry.
---@return nil
function M.prev_qf()
  pcall(vim.cmd, "cprev")
end

return M
