---@module 'lsp.tools.lsp_signature.utils.helper'
--- Two display helpers for lsp_signature: `hexnum_to_hexstr` (numeric color
--- to `#rrggbb`) and `shorten_display_path` (absolute path to a shorter
--- form for the popup).

local M = {}

-- Convert numeric hex (0xRRGGBB) to hex string "#rrggbb"
---@param n integer
---@return string
function M.hexnum_to_hexstr(n)
  n = math.max(0, math.floor(n))
  local s = string.format("#%06x", n)
  return s
end

--- Shorten absolute file name for display.
--- If file is inside current working directory, return path relative to cwd (prefixed with ".").
--- If path contains "node_modules", return the path starting at "node_modules/..." to make output concise.
--- Converts backslashes to forward slashes for consistent display.
---@param fname string
---@return string
function M.shorten_display_path(fname)
  if not fname or fname == "" then
    return "[unknown]"
  end

  -- normalize separators to forward slash for matching and display
  local norm = fname:gsub("\\", "/")

  -- try node_modules first (case-insensitive)
  local nm_start = norm:lower():find("node_modules")
  if nm_start then
    return norm:sub(nm_start) -- returns "node_modules/..."
  end

  -- try relative to cwd
  local ok, cwd = pcall(vim.uv.cwd)
  if ok and cwd and cwd ~= "" then
    local norm_cwd = cwd:gsub("\\", "/")
    if norm:sub(1, #norm_cwd) == norm_cwd then
      local rel = "." .. norm:sub(#norm_cwd + 1)
      if rel == "." or rel == "./" then
        return "./" .. vim.fn.fnamemodify(fname, ":t") -- fallback to basename
      end
      return rel
    end
  end

  -- fallback: show basename only to keep compact
  return vim.fn.fnamemodify(fname, ":t")
end

return M
