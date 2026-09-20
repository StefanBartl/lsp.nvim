---@module 'lsp.tools.deprecated_help.helper'
--- Helper utilities used by other modules.
--- Provides safe buffer/diagnostic helpers and small caches.

local map = require("lib.nvim.bindings.keymap")
local autocmd = require("lib.nvim.bindings.autocmd")

local M = {}

-- Cache per-buffer mapped symbols to avoid duplicated mappings/notifications.
---@type table<number, table<string, boolean>>
M.buf_symbol_cache = {}

-- Utility: ensure per-buffer cache table exists.
---@param bufnr number
---@return table<string, boolean>
function M.ensure_buf_cache(bufnr)
  -- create table if missing
  if M.buf_symbol_cache[bufnr] == nil then
    M.buf_symbol_cache[bufnr] = {}
  end
  return M.buf_symbol_cache[bufnr]
end

-- Drop a buffer's cached symbols. Exposed for tests as well as the
-- BufDelete/BufWipeout autocmd below.
---@param bufnr number
---@return nil
function M.clear_buf_cache(bufnr)
  M.buf_symbol_cache[bufnr] = nil
end

-- Without this, `buf_symbol_cache` grows by one entry per buffer ever
-- visited and is never reclaimed for the rest of the session (PERF-53).
autocmd.create({ "BufDelete", "BufWipeout" }, function(args)
  M.clear_buf_cache(args.buf)
end, {
  group = autocmd.group("lsp_deprecated_help_buf_cache", true),
  desc = "lsp.nvim: drop a deleted buffer's cached deprecated-symbol mappings",
})

-- Safely get a line from buffer (returns empty string if invalid)
---@param bufnr number
---@param linenr number 0-indexed
---@return string
function M.get_line(bufnr, linenr)
  local ok, line = pcall(vim.api.nvim_buf_get_lines, bufnr, linenr, linenr + 1, false)
  if not ok or type(line) ~= "table" then
    return ""
  end
  return line[1] or ""
end

-- Given a diagnostic range, return the substring covered by it.
-- Fallback: return word under start position if range length is zero.
---@param bufnr number
---@param range table  LSP range table: { start = { line, character }, ["end"] = { line, character } }
---@return string
function M.get_text_for_range(bufnr, range)
  -- defensive checks
  if not range or not range.start then
    return ""
  end
  local s_row = range.start.line or 0
  local s_col = range.start.character or 0
  local e_row = (range["end"] and range["end"].line) or s_row
  local e_col = (range["end"] and range["end"].character) or s_col

  -- if single-line range
  if s_row == e_row then
    local line = M.get_line(bufnr, s_row)
    -- protect against out-of-bounds columns
    s_col = math.max(0, math.min(#line, s_col))
    e_col = math.max(0, math.min(#line, e_col))
    local text = line:sub(s_col + 1, e_col) -- Lua strings are 1-indexed
    if text ~= "" then
      return text
    end
  end

  -- fallback: get 'word' under start position (common and forgiving)
  local ok_word, word = pcall(vim.fn.expand, "<cword>")
  if ok_word and type(word) == "string" and word ~= "" then
    return word
  end

  return ""
end

-- Create a buffer-local normal mode mapping only once per (bufnr, lhs).
-- Uses vim.keymap.set for modern API and sets {silent=true, noremap=true, buffer=bufnr}.
---@param bufnr number
---@param lhs string
---@param rhs function|string
---@param opts table|nil
function M.set_buf_keymap_once(bufnr, lhs, rhs, opts)
  opts = opts or {}
  opts.buffer = bufnr
  opts.noremap = true
  opts.silent = true

  -- The comparison has to happen on the resolved key sequence. Neovim stores a
  -- mapping under the expanded lhs -- `<leader>oh` comes back out of
  -- `nvim_buf_get_keymap` as `\oh` -- so comparing against the notation the
  -- caller passed never matched, and "once" was never once: measured with a
  -- user's own buffer-local `<leader>oh` in place, the guard fell through and
  -- the mapping was replaced. `nvim_replace_termcodes` expands `<leader>` the
  -- same way the mapping did.
  local resolved = vim.api.nvim_replace_termcodes(lhs, true, true, true)
  local existing = vim.api.nvim_buf_get_keymap(bufnr, "n")
  for _, m in ipairs(existing) do
    if m.lhs == resolved then
      return -- mapping already exists; do nothing
    end
  end

  -- set mapping
  if type(rhs) == "function" then
    map("n", lhs, rhs, opts)
  else
    map("n", lhs, rhs, opts)
  end
end

return M
