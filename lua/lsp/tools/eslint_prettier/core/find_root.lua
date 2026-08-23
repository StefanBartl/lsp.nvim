---@module 'lsp.tools.eslint_prettier.core.find_root'
--- Find project root by searching upward for markers. Delegates to
--- lib.nvim.fs.find_root (cached, per-directory LRU) instead of a
--- hand-rolled upward walk -- this module used to carry its own copy of
--- that walk, including a manual `vim.fs.find`-unavailable fallback that
--- lib.nvim.fs.find_root's own `find_upward_dir` already covers.
local api = vim.api
local fn = vim.fn

---markers to detect project root
local markers = { "package.json", ".git", ".eslintrc", ".prettierrc" }

local root_finder = require("lib.nvim.fs.find_root")({ markers = markers })

---@param bufnr number|nil
---@return string|nil
local function find_root(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local bufname = api.nvim_buf_get_name(bufnr)
  if bufname == "" then
    return nil
  end
  local start_dir = fn.fnamemodify(bufname, ":p:h")
  return root_finder.find(start_dir)
end

return find_root
