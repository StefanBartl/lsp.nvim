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

--- Resolve the window whose diagnostics a location list should be built from.
---
--- A location list takes its buffer from its window, and `:DiagLoc` leaves the
--- cursor *inside* the location-list window it opens (`lwindow` focuses it). So
--- a second `:DiagLoc` ran with `winnr = 0` meaning that window, whose buffer is
--- the quickfix scratch buffer, which carries no diagnostics at all. Measured:
--- `:DiagLoc` -> 3 entries, window type "loclist"; `:DiagLoc warn` immediately
--- after -> 0 entries and `lwindow` closed the window again. No error, no
--- warning: the command that was supposed to narrow the list wiped it.
---
--- A location-list window knows the window it belongs to (`filewinid`); any
--- other special window (quickfix, preview, popup) has no such link, so fall
--- back to the first ordinary window in the tabpage.
---@param win integer|nil
---@return integer
local function resolve_win(win)
  if win == nil or win == 0 then
    win = vim.api.nvim_get_current_win()
  end
  if not vim.api.nvim_win_is_valid(win) then
    return 0
  end
  if vim.fn.win_gettype(win) == "" then
    return win
  end
  if vim.fn.win_gettype(win) == "loclist" then
    local file_win = vim.fn.getloclist(win, { filewinid = 0 }).filewinid
    if
      type(file_win) == "number"
      and file_win ~= 0
      and vim.api.nvim_win_is_valid(file_win)
      and vim.fn.win_gettype(file_win) == ""
    then
      return file_win
    end
  end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.fn.win_gettype(w) == "" then
      return w
    end
  end
  return win
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
    -- all: a location list takes it from the window -- which is exactly why
    -- the window has to be a real one, see `resolve_win`.
    winnr = resolve_win(opts.win_id),
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
