---@module 'lsp.integrations.lspsaga'
---@brief lspsaga.nvim, breadcrumbs.
---@description
--- Everything but the breadcrumb is switched off and nothing in the core
--- touches lspsaga, so the adapter's first job is the health report: one row
--- per plugin the umbrella claims to cover. A plugin the umbrella names but
--- cannot report on is a gap in exactly the place someone looks when
--- something is missing.
---
--- Past that row it does two things, both out of `configure()`, which the
--- pack spec calls (`lsp/pack/ui.lua`): it hands lspsaga its options, and it
--- caps how deep the breadcrumb may go. The cap is written as a rewrite of
--- lspsaga's output rather than as an option because lspsaga has none -- see
--- "Winbar depth" below.
---
---@see lsp.integrations

local M = {}

local api = vim.api

---@type string
M.plugin = "lspsaga.nvim"

---@type boolean
M.hard = false

---@type string
M.note = "breadcrumbs; configured here, with a per-filetype depth cap"

---@return boolean
function M.available()
  return (pcall(require, "lspsaga"))
end

-- ---------------------------------------------------------------------------
-- Winbar depth
-- ---------------------------------------------------------------------------

--- How many symbols may follow the file name in the winbar, per filetype.
--- A filetype that is not named here has no cap.
---
--- Only `markdown` needs one, and the reason is the shape of the symbols
--- rather than anything about lspsaga: marksman reports headings as a *nested*
--- document outline, so a cursor in the body of an H3 is inside three symbols
--- at once and the breadcrumb grows to
--- `folder > file > H1 > H2 > H3`. In Lua the same code produces
--- `folder > file`, because lua_ls reports no symbol at all for a line outside
--- a function -- the difference is what the server sends, not how it is drawn.
---
--- The value that reads best is the one this was cut down to: the file's own
--- top heading, and nothing below it. Deeper levels are the table of contents,
--- and a breadcrumb is not one.
---@type table<string, integer>
M.winbar_max_symbols = {
  markdown = 1,
}

--- Replace the per-filetype caps. Becomes a real config key when the pack
--- layer takes lspsaga's options over (see the module doc); until then this is
--- the seam, so that "how deep should the breadcrumb go" is not a number
--- buried in a callback.
---@param tbl table<string, integer>|nil # nil restores the default.
---@return nil
function M.set_winbar_max_symbols(tbl)
  M.winbar_max_symbols = tbl or { markdown = 1 }
end

---@internal
--- lspsaga's winbar separator, exactly as it builds it
--- (`symbol/winbar.lua`, `bar_prefix`). Read from the live config rather than
--- assumed: `separator` is user-settable, and a guessed one would silently
--- match nothing -- which looks exactly like "no trimming needed".
---@return string|nil sep, integer path_parts
local function winbar_shape()
  local ok, saga = pcall(require, "lspsaga")
  if not ok then
    return nil, 0
  end
  local cfg = saga.config and saga.config.symbol_in_winbar
  if type(cfg) ~= "table" then
    return nil, 0
  end
  -- The path is rendered as `folder_level + 1` items joined by the same
  -- separator, so it occupies that many of the parts a split produces.
  local path_parts = cfg.show_file and ((tonumber(cfg.folder_level) or 1) + 1) or 0
  return "%#SagaSep#" .. tostring(cfg.separator or " > ") .. "%*", path_parts
end

---@internal
--- Split on a literal separator (no pattern semantics -- `%#SagaSep#` is full
--- of characters Lua patterns would read as syntax).
---@param s string
---@param sep string
---@return string[]
local function split_plain(s, sep)
  local out, from = {}, 1
  while true do
    local a, b = s:find(sep, from, true)
    if not a then
      out[#out + 1] = s:sub(from)
      return out
    end
    out[#out + 1] = s:sub(from, a - 1)
    from = b + 1
  end
end

--- Cut the winbar of `win` down to the file part plus `max` symbols.
---
--- Done by rewriting what lspsaga already wrote, rather than by configuring
--- it: lspsaga has no depth option at all (`ignore_patterns`, the only related
--- knob, matches on the *buffer name* and would remove the folder and file
--- name along with the symbols, which is the part worth keeping). Its
--- `find_in_node` recurses into every child containing the cursor line
--- unconditionally.
---@param win integer
---@return nil
function M.trim_winbar(win)
  if not api.nvim_win_is_valid(win) then
    return
  end

  local buf = api.nvim_win_get_buf(win)
  local max = M.winbar_max_symbols[vim.bo[buf].filetype]
  if not max then
    return
  end

  local line = vim.wo[win].winbar
  if not line or line == "" then
    return
  end

  local sep, path_parts = winbar_shape()
  if not sep then
    return
  end

  local parts = split_plain(line, sep)
  local keep = path_parts + max
  if #parts <= keep then
    return
  end

  vim.wo[win].winbar = table.concat(vim.list_slice(parts, 1, keep), sep)
end

---@internal
--- Watch the two moments lspsaga writes the winbar and re-cut what it wrote.
---
--- `vim.schedule` rather than autocmd ordering: lspsaga creates its
--- `CursorMoved` handler per buffer at `LspAttach` time, so an autocmd
--- registered here at `config` time cannot be relied on to run after it.
--- Deferring to the event loop is ordering-independent.
---@return nil
local function watch_winbar()
  local group = api.nvim_create_augroup("LspNvimSagaWinbarDepth", { clear = true })

  local function schedule_trim()
    -- Cheapest possible guard, on the main path: one table lookup per cursor
    -- move for filetypes that have no cap, which is all of them but one.
    if not M.winbar_max_symbols[vim.bo.filetype] then
      return
    end
    local win = api.nvim_get_current_win()
    vim.schedule(function()
      M.trim_winbar(win)
    end)
  end

  api.nvim_create_autocmd("CursorMoved", {
    group = group,
    callback = schedule_trim,
    desc = "lsp.nvim: cap the lspsaga breadcrumb's symbol depth",
  })
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = "SagaSymbolUpdate",
    callback = schedule_trim,
    desc = "lsp.nvim: cap the lspsaga breadcrumb's symbol depth",
  })
end

--- Configure lspsaga. Called from the pack spec's `config`.
---
--- Almost everything is off: the breadcrumb is the reason this plugin is here.
---
--- Two spelling traps, both found the same way -- by reading lspsaga's source
--- for the name rather than trusting the one that looked right:
---   * `symbol_in_winbar`, not `breadcrumb`. The breadcrumb table was passed
---     here from the start and lspsaga never read a key by that name; what one
---     saw was its defaults, which happen to carry the same three values. A
---     dead option that produces the intended result is the hardest kind to
---     notice.
---   * `lightbulb.enable`, not `enabled`. That misspelling merged in as a dead
---     extra field while the lightbulb kept running on every cursor move
---     (~214ms in a startup sample, plus permanent load while editing).
---@return boolean ok
function M.configure()
  local ok, lspsaga = pcall(require, "lspsaga")
  if not ok then
    return false
  end

  lspsaga.setup({
    beacon = { enable = false },
    symbol_in_winbar = { enable = true, show_file = true, folder_level = 1 },
    hover = { enable = false },
    lightbulb = { enable = false },
    rename = { enable = false },
    term_toggle = { enable = false },
  })

  watch_winbar()
  return true
end

return M
