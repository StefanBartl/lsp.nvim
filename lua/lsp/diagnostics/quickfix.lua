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
function M.next_qf(count)
  -- `:{count}cnext` is native; no loop needed. Still pcall-wrapped, because
  -- Vim raises E553 at the end of the list and swallowing that is the
  -- friendlier behaviour for a key one holds down.
  pcall(function()
    vim.cmd((count or 1) .. "cnext")
  end)
end

--- Jump to previous quickfix entry.
---@return nil
function M.prev_qf(count)
  pcall(function()
    vim.cmd((count or 1) .. "cprev")
  end)
end

return M
