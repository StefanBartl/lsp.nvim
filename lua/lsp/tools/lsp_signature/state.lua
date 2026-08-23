---@module 'lsp.tools.lsp_signature.state'
--- Holds popup state and provides a safe close function.
--- Consumers should require this module and use set/get/close.
local M = {}

-- current popup references; consumers may read but should call M.close()
M.current = {
  buf = nil, -- integer|nil
  win = nil, -- integer|nil
}

--- Close the currently tracked popup window (safe, idempotent).
--- Also clears stored references.
---@return boolean closed True if a window was closed.
function M.close()
  local api = vim.api
  local win = M.current.win
  local ok = false
  if win and api.nvim_win_is_valid(win) then
    pcall(api.nvim_win_close, win, true)
    ok = true
  end
  M.current.buf = nil
  M.current.win = nil
  return ok
end

--- Set current popup references.
---@param bufnr integer|nil
---@param winid integer|nil
function M.set(bufnr, winid)
  M.current.buf = bufnr
  M.current.win = winid
end

return M
