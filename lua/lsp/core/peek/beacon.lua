---@module 'lsp.core.peek.beacon'
---@brief A brief highlight on a line, so the eye finds the cursor after a jump.
---@description
--- Used where a jump takes the cursor somewhere the eye is not looking: after a
--- peeked buffer is taken into a real window. It is one extmark with a line
--- highlight, removed by a timer, in a namespace of its own -- so it cannot
--- collide with another plugin's marks and leaves nothing behind.
---
--- lspsaga had this as `beacon`, and it fired only from its own definition and
--- call-hierarchy jumps. Here it is a plain function that whatever jumps can
--- call, and it is off unless `peek.beacon` says otherwise.
---
---@see lsp.core.peek

local api = vim.api

local M = {}

--- Linked to `Visual` by default; override with `:hi link LspNvimBeacon …`.
---@type string
M.HL = "LspNvimBeacon"

--- How long the line stays lit, in milliseconds.
---@type integer
M.DURATION_MS = 350

---@type integer
local NS = api.nvim_create_namespace("lsp_nvim_beacon")

--- Light a line for `M.DURATION_MS`.
---@param win integer
---@param lnum integer # 0-based.
---@return nil
function M.flash(win, lnum)
  if not api.nvim_win_is_valid(win) then
    return
  end
  local bufnr = api.nvim_win_get_buf(win)
  if lnum < 0 or lnum >= api.nvim_buf_line_count(bufnr) then
    return
  end

  api.nvim_set_hl(0, M.HL, { link = "Visual", default = true })
  local ok, id = pcall(api.nvim_buf_set_extmark, bufnr, NS, lnum, 0, {
    line_hl_group = M.HL,
    priority = 200,
  })
  if not ok then
    return
  end

  vim.defer_fn(function()
    if api.nvim_buf_is_valid(bufnr) then
      pcall(api.nvim_buf_del_extmark, bufnr, NS, id)
    end
  end, M.DURATION_MS)
end

return M
