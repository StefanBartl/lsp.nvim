---@module 'lsp.diagnostics.loclist'
--- Buffer-local diagnostics via location list and direct navigation.

local util = require("lsp.diagnostics.util")

---@class Lsp.Diagnostics.Loclist
local M = {}

---@type boolean|nil
local SETLOCLIST_TAKES_TWO_ARGS = nil

--- Compatibility wrapper for vim.diagnostic.setloclist (0.10 vs 0.11+).
---@param opts vim.diagnostic.setloclist.Opts
---@return nil
local function call_setloclist(opts)
  if SETLOCLIST_TAKES_TWO_ARGS == nil then
    local ok = pcall(vim.diagnostic.setloclist, 0, { open = false })
    SETLOCLIST_TAKES_TWO_ARGS = ok
  end

  if SETLOCLIST_TAKES_TWO_ARGS then
    local win = opts.winnr or 0
    local copy = vim.tbl_extend("force", {}, opts)
    copy.winnr = nil
    -- The two-argument form is what Neovim had before the opts table; the
    -- probe above is what decides which one this build wants, and the
    -- annotation only knows the current one.
    ---@diagnostic disable-next-line: param-type-mismatch, redundant-parameter
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

  ---@type vim.diagnostic.setloclist.Opts
  local locopts = {
    open = (opts.open ~= false),
    -- Neovim names this `winnr`; it was `win_id` here, which the
    -- one-argument form silently ignored. The buffer is not passed at
    -- all: a location list takes it from the window.
    winnr = opts.win_id or 0,
    namespace = opts.namespace,
    severity = sev,
  }

  call_setloclist(locopts)
end

--- Jump to next diagnostic in current buffer.
---@param severity integer|nil
---@return nil
function M.next_loc(severity, count)
  vim.diagnostic.jump({ count = count or 1, severity = severity, float = true })
end

--- Jump to previous diagnostic in current buffer.
---@param severity integer|nil
---@return nil
function M.prev_loc(severity, count)
  vim.diagnostic.jump({ count = -(count or 1), severity = severity, float = true })
end

return M
