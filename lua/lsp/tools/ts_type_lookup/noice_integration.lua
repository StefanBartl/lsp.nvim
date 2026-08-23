---@module 'lsp.tools.ts_type_lookup.noice_integration'
--- Small Noice integration: set keymaps in Noice floating buffers so the user can
--- open the shown symbol/type definition directly into a real buffer (vsplit).
--- This module watches Noice-created floating buffers (filetype 'noice' or bufnames)
--- and installs a small set of keymaps:
---   'o' -> open symbol/type under cursor via GoToTypeDefStr
---   'p' -> PeekTypeDefStr for the symbol under cursor
---   'q' -> close the preview window

local api = vim.api
local Autocmd = require("lib.nvim.autocmd")
local usercmd = require("lib.nvim.usercmd")
local M = {}

--- Determine whether a buffer looks like a Noice floating buffer.
---@param bufnr number
---@return boolean
local function is_noice_buf(bufnr)
  local ok, ft = pcall(api.nvim_get_option_value, "filetype", { buf = bufnr })
  if ok and ft and ft ~= "" and ft == "noice" then
    return true
  end
  -- additional heuristic: buffer name contains "Noice" or is a floating preview (optional)
  local name = api.nvim_buf_get_name(bufnr) or ""
  if name:match("Noice") then
    return true
  end
  return false
end

--- Install keymaps into the given noice buffer
---@param bufnr number
local function install_maps(bufnr)
  -- do not override existing maps if already set
  local opts = { nowait = true, noremap = true, silent = true }
  -- open in vsplit: use the word under cursor in the noice buffer
  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "o",
    "<cmd>lua require('lsp.tools.ts_type_lookup.cmds').go_to_type_definition_for(vim.fn.expand('<cword>'))<CR>",
    opts
  )
  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "p",
    "<cmd>lua require('lsp.tools.ts_type_lookup.cmds').peek_type_definition_for(vim.fn.expand('<cword>'))<CR>",
    opts
  )
  api.nvim_buf_set_keymap(bufnr, "n", "q", "<cmd>close<CR>", opts)
end

--- Autocmd callback: when a window is entered, check if it's a Noice preview and install maps
local group = api.nvim_create_augroup("ToolsNoiceIntegration", { clear = true })
Autocmd.create("BufWinEnter", function(ev)
  local bufnr = ev.buf
  if is_noice_buf(bufnr) then
    install_maps(bufnr)
  end
end, {
  group = group,
})

--- Manual function to attach maps to current buffer
function M.attach_to_current()
  local bufnr = api.nvim_get_current_buf()
  if is_noice_buf(bufnr) then
    install_maps(bufnr)
  end
end

usercmd.create("TypeDefAttachNoiceKeys", function()
  M.attach_to_current()
end, { desc = "Attach type lookup keymaps to current Noice buffer" })

return M
