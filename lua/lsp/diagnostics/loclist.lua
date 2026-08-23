---@module 'lsp.diagnostics.loclist'
--- Buffer-local diagnostics via location list and direct navigation.

local util = require("lsp.diagnostics.util")

---@class Lsp.Diagnostics.Loclist
local M = {}

---@type boolean|nil
local SETLOCLIST_TAKES_TWO_ARGS = nil

--- Compatibility wrapper for vim.diagnostic.setloclist (0.10 vs 0.11+).
---@param opts Lsp.Diagnostics.ListOpts
---@return nil
local function call_setloclist(opts)
  if SETLOCLIST_TAKES_TWO_ARGS == nil then
    local ok = pcall(vim.diagnostic.setloclist, 0, { open = false })
    SETLOCLIST_TAKES_TWO_ARGS = ok
  end

  if SETLOCLIST_TAKES_TWO_ARGS then
    local win = opts.win_id or 0
    local copy = vim.tbl_extend("force", {}, opts)
    copy.win_id = nil
    vim.diagnostic.setloclist(win, copy)
  else
    vim.diagnostic.setloclist(opts)
  end
end

--- Populate location list from diagnostics.
---@param opts Lsp.Diagnostics.ListOpts|nil
---@return nil
function M.to_loc(opts)
  opts = opts or {}
  local sev = util.to_severity(opts.severity)

  local locopts = {
    open = (opts.open ~= false),
    win_id = opts.win_id or 0,
    bufnr = opts.bufnr,
    namespace = opts.namespace,
    severity = sev,
  }

  call_setloclist(locopts)
end

--- Jump to next diagnostic in current buffer.
---@param severity integer|nil
---@return nil
function M.next_loc(severity)
  vim.diagnostic.jump({ count = 1, severity = severity, float = true })
end

--- Jump to previous diagnostic in current buffer.
---@param severity integer|nil
---@return nil
function M.prev_loc(severity)
  vim.diagnostic.jump({ count = -1, severity = severity, float = true })
end

return M
