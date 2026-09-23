---@module 'lsp.core.winbar'
---@brief LSP breadcrumb in the window bar: `folder > file > Class > method`.
---@description
--- Draws where the cursor is, in terms the language server understands: the
--- file's path, then every symbol that contains the cursor line, outermost
--- first. It replaces lspsaga's `symbol_in_winbar`, which is what lsp.nvim used
--- for this until lspsaga was removed -- and it does it by *producing* the
--- string rather than rewriting lspsaga's, which is what the old depth cap and
--- chip styling had to do.
---
--- **What it costs.** One `textDocument/documentSymbol` request per text
--- change, shared with anything else that wants the symbols
--- (`lsp.core.symbols`), debounced by `refresh_ms`. The cursor position only
--- reads the cache, so moving around is a table walk and, when the result did
--- not change, no write at all.
---
--- **Who owns `'winbar'`.** Window-local, set only on windows that show a
--- normal, LSP-attached buffer (`buftype == ""`, not a float). It is written
--- over whatever was there -- the same contract lspsaga had -- but a window that
--- stops qualifying is only cleared when the string in it is *ours*, recognised
--- by the `LspNvimWinbar` group names every string carries. So a winbar another
--- plugin put on a help or terminal window is never touched.
---
--- **Depth.** `max_symbols` caps how many symbols follow the file, per
--- filetype. Only `markdown` has one by default, and the reason is the shape of
--- the symbols rather than anything about drawing: marksman reports headings as
--- a *nested* outline, so a cursor in the body of an H3 is inside three symbols
--- at once and the breadcrumb grows to `folder > file > H1 > H2 > H3`. lua_ls
--- reports no symbol at all for a line outside a function, so the same code
--- yields `folder > file`. The value that reads best is the file's own top
--- heading and nothing below it -- deeper levels are a table of contents, and a
--- breadcrumb is not one.
---
--- Structure mirrors `lsp.core.lightbulb` on purpose -- global default plus
--- per-filetype overrides (an absent filetype inherits `enable`, `false` is an
--- explicit off), its own augroup, and the same `on/off/toggle/status/clear`
--- surface. Driven by `:Lsp winbar [on|off|toggle|status|clear] [filetype]`.
---
---@see lsp.core.symbols
---@see lsp.core.winbar.render
---@see lsp.core.lightbulb

local notify = require("lib.nvim.notify").create("[lsp.core.winbar]")
local autocmd = require("lib.nvim.bindings.autocmd")
local debounce = require("lib.nvim.debounce")
local symbols = require("lsp.core.symbols")
local render = require("lsp.core.winbar.render")
local kinds = require("lsp.core.winbar.kinds")

local api = vim.api

local M = {}

--- Augroup for the handlers. Separate from `lsp_nvim` for the reason
--- `lsp.core.lightbulb` gives: that group belongs to the keymap layer and is
--- cleared with `keymaps.enable = false`.
---@type string
M.GROUP = "lsp_nvim_winbar"

--- The default per-filetype depth cap. See the module doc for why markdown.
---@type table<string, integer>
M.DEFAULT_MAX_SYMBOLS = { markdown = 1 }

---@class LspWinbar.State
---@field enable boolean
---@field filetypes table<string, boolean>
---@field show_file boolean
---@field folder_level integer
---@field separator string
---@field max_symbols table<string, integer>
---@field chips boolean
---@field align "left"|"right"
---@field debounce_ms integer
---@field refresh_ms integer

--- A fresh state at the documented defaults. `setup()` starts from this rather
--- than from whatever the last call left behind, so an option that is not
--- passed means its default and not "what it was".
---@return LspWinbar.State
local function defaults()
  return {
    enable = true,
    filetypes = {},
    show_file = true,
    folder_level = 1,
    -- U+203A, by codepoint like the glyphs in `winbar.kinds` and
    -- `winbar.render`: a literal here was once read as Latin-1 and written
    -- back as UTF-8, which is not a bug a reader sees.
    separator = " " .. vim.fn.nr2char(0x203A) .. " ",
    max_symbols = vim.deepcopy(M.DEFAULT_MAX_SYMBOLS),
    chips = true,
    align = "left",
    debounce_ms = 60,
    refresh_ms = 300,
  }
end

---@type LspWinbar.State
local state = defaults()

---@type boolean
local registered = false

--- Cursor-driven repaint, rebuilt by `setup()` because the window is a
--- configuration value.
---@type Lib.Debounce.Handle|nil
local repaint = nil

--- One symbol-refresh debounce per buffer: a single shared one would drop the
--- refresh of buffer A when buffer B changed within the window.
---@type table<integer, Lib.Debounce.Handle>
local refreshers = {}

---@type (fun())|nil
local unsubscribe = nil

-- ------------------------------------------------------------------ resolving

--- Whether the breadcrumb is on for a filetype (or globally, with no argument).
---@param ft string|nil
---@return boolean
function M.enabled(ft)
  if ft ~= nil and state.filetypes[ft] ~= nil then
    return state.filetypes[ft]
  end
  return state.enable
end

---@internal
--- Should this window carry a breadcrumb at all?
---
--- Floats are out (a peek window is a float, and has its own title), so is
--- anything that is not a plain file buffer, and so is a buffer no language
--- server is attached to: with no server there are no symbols and the path
--- alone is not what this feature is for. (lsp.nvim's own in-process clients
--- do not count as a server; see `lsp.core.util.server_clients`.)
---@param win integer
---@return boolean
local function eligible(win)
  if not api.nvim_win_is_valid(win) then
    return false
  end
  if api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local bufnr = api.nvim_win_get_buf(win)
  if vim.bo[bufnr].buftype ~= "" then
    return false
  end
  if not M.enabled(vim.bo[bufnr].filetype) then
    return false
  end
  return symbols.attached(bufnr)
end

---@internal
--- Is this string one this module wrote?
---@param value string
---@return boolean
local function ours(value)
  return value ~= "" and value:find(render.MARK, 1, true) ~= nil
end

-- ---------------------------------------------------------------------- parts

---@internal
--- Icon and highlight group for the file part, from nvim-web-devicons when it
--- is installed.
---@param name string
---@param filetype string
---@return string icon, string|nil hl
local function file_icon(name, filetype)
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if ok then
    local icon, hl
    if filetype ~= "" and devicons.get_icon_by_filetype then
      icon, hl = devicons.get_icon_by_filetype(filetype, { default = true })
    end
    if not icon and name ~= "" then
      icon, hl = devicons.get_icon(name, vim.fn.fnamemodify(name, ":e"), { default = true })
    end
    if icon then
      return icon, hl
    end
  end
  return kinds.FILE, nil
end

--- The breadcrumb's parts for a file and the symbols containing the cursor.
---
--- Pure: no window, no buffer, no request, so the depth cap and the path
--- shape are testable without any of them.
---@param input { name: string, filetype: string, path: LspSymbols.Node[] }
---@return LspWinbar.Part[]
function M.parts(input)
  ---@type LspWinbar.Part[]
  local out = {}

  if state.show_file then
    if input.name ~= "" then
      ---@type string[]
      local dirs = {}
      local dir = vim.fn.fnamemodify(input.name, ":h")
      for _ = 1, state.folder_level do
        local tail = vim.fn.fnamemodify(dir, ":t")
        if tail == "" or tail == "." then
          break
        end
        table.insert(dirs, 1, tail)
        local parent = vim.fn.fnamemodify(dir, ":h")
        if parent == dir then
          break
        end
        dir = parent
      end
      for _, d in ipairs(dirs) do
        out[#out + 1] = { role = "folder", icon = kinds.FOLDER, text = d }
      end
    end

    local file = input.name ~= "" and vim.fn.fnamemodify(input.name, ":t") or "[No Name]"
    local icon, hl = file_icon(input.name, input.filetype)
    out[#out + 1] = { role = "file", icon = icon, icon_hl = hl, text = file }
  end

  local cap = state.max_symbols[input.filetype]
  for i, node in ipairs(input.path) do
    if cap ~= nil and i > cap then
      break
    end
    if node.name ~= "" then
      local kind = kinds.get(node.kind, input.filetype)
      out[#out + 1] = { role = "symbol", icon = kind.icon, icon_hl = kind.hl, text = node.name }
    end
  end

  return out
end

--- The `'winbar'` string for a window, or `""` when it should show nothing.
---@param win integer
---@return string
function M.build(win)
  local bufnr = api.nvim_win_get_buf(win)

  ---@type LspSymbols.Node[]
  local path = {}
  local nodes, encoding = symbols.get(bufnr)
  if nodes and #nodes > 0 then
    local line, col = symbols.cursor(win, encoding)
    path = symbols.path_at(nodes, line, col)
  end

  local parts = M.parts({
    name = api.nvim_buf_get_name(bufnr),
    filetype = vim.bo[bufnr].filetype,
    path = path,
  })
  return render.render(
    parts,
    { chips = state.chips, separator = state.separator, align = state.align }
  )
end

-- -------------------------------------------------------------------- drawing

---@internal
--- Take our string out of a window, and only ours.
---@param win integer
---@return nil
local function release(win)
  if not api.nvim_win_is_valid(win) then
    return
  end
  if ours(vim.wo[win].winbar) then
    -- Back to the *global* value rather than to "": a plugin that sets
    -- `vim.o.winbar` for every window would otherwise lose it on exactly the
    -- windows this module had drawn on.
    api.nvim_win_call(win, function()
      vim.cmd("setlocal winbar<")
    end)
  end
end

---@internal
--- Bring one window's breadcrumb up to date.
---@param win integer
---@return nil
local function paint(win)
  if not registered then
    return
  end
  if not eligible(win) then
    release(win)
    return
  end

  local line = M.build(win)
  if line == "" then
    release(win)
    return
  end
  -- Compared first: an unchanged string must not be written, or every cursor
  -- movement would redraw the bar.
  if vim.wo[win].winbar ~= line then
    vim.wo[win].winbar = line
  end
end

---@internal
--- Repaint every window that shows a buffer.
---@param bufnr integer
---@return nil
local function paint_buffer(bufnr)
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    paint(win)
  end
end

---@internal
--- Repaint every window in every tab page, for the moments that change what
--- all of them show (a toggle, a colorscheme).
---@return nil
local function paint_all()
  for _, win in ipairs(api.nvim_list_wins()) do
    paint(win)
  end
end

---@internal
--- Ask for fresh symbols, once the buffer has been quiet for `refresh_ms`.
---@param bufnr integer
---@return nil
local function schedule_refresh(bufnr)
  local handle = refreshers[bufnr]
  if handle == nil then
    handle = debounce.new(function(target)
      if api.nvim_buf_is_valid(target) and M.enabled(vim.bo[target].filetype) then
        symbols.refresh(target)
      end
    end, state.refresh_ms)
    refreshers[bufnr] = handle
  end
  handle.call(bufnr)
end

---@internal
---@return nil
local function drop_refreshers()
  for _, handle in pairs(refreshers) do
    handle.cancel()
  end
  refreshers = {}
end

-- ---------------------------------------------------------------------- setup

--- Seed the live state from the configuration and register the handlers.
---
--- Idempotent: a second `setup()` resets the augroup rather than stacking a
--- second set of identical autocommands on it.
---@param opts LspNvim.WinbarOpts|nil
---@return nil
function M.setup(opts)
  opts = opts or {}

  state = defaults()
  state.enable = opts.enable ~= false
  if type(opts.filetypes) == "table" then
    for ft, value in pairs(opts.filetypes) do
      if type(ft) == "string" and type(value) == "boolean" then
        state.filetypes[ft] = value
      end
    end
  end
  state.show_file = opts.show_file ~= false
  if type(opts.folder_level) == "number" and opts.folder_level >= 0 then
    state.folder_level = math.floor(opts.folder_level)
  end
  if type(opts.separator) == "string" then
    state.separator = opts.separator
  end
  if type(opts.max_symbols) == "table" then
    state.max_symbols = {}
    for ft, n in pairs(opts.max_symbols) do
      if type(ft) == "string" and type(n) == "number" and n >= 0 then
        state.max_symbols[ft] = math.floor(n)
      end
    end
  end
  state.chips = opts.chips ~= false
  state.align = opts.align == "right" and "right" or "left"
  if type(opts.debounce_ms) == "number" and opts.debounce_ms >= 0 then
    state.debounce_ms = math.floor(opts.debounce_ms)
  end
  if type(opts.refresh_ms) == "number" and opts.refresh_ms >= 0 then
    state.refresh_ms = math.floor(opts.refresh_ms)
  end

  M.detach()
  render.setup_highlights()
  repaint = debounce.new(paint, state.debounce_ms)
  unsubscribe = symbols.subscribe(paint_buffer)

  -- Through lib.nvim rather than `vim.api.nvim_create_autocmd`, which is what
  -- every autocommand in this plugin does.
  local group = autocmd.group(M.GROUP, true)

  -- The cursor is the only thing that moves the breadcrumb between two
  -- symbol answers. Debounced, and it reads the cache: no request here.
  autocmd.create("CursorMoved", function()
    if repaint then
      repaint.call(api.nvim_get_current_win())
    end
  end, {
    group = group,
    desc = "lsp.nvim: follow the cursor in the LSP breadcrumb",
  })

  -- A window that just started showing a buffer, or just got focus, may be
  -- showing a stale (or somebody else's) bar.
  autocmd.create({ "BufWinEnter", "WinEnter", "BufEnter" }, function()
    local win = api.nvim_get_current_win()
    vim.schedule(function()
      paint(win)
      -- Not debounced: entering a buffer is a single event, not a burst, and
      -- `refresh` is a no-op when the cache already answers for this text.
      local bufnr = api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) or nil
      if bufnr and eligible(win) then
        symbols.refresh(bufnr)
      end
    end)
  end, {
    group = group,
    desc = "lsp.nvim: draw the LSP breadcrumb for the window that just changed",
  })

  -- What changes the answer: an edit, or leaving insert mode with one pending.
  autocmd.create({ "TextChanged", "InsertLeave" }, function(args)
    if M.enabled(vim.bo[args.buf].filetype) then
      schedule_refresh(args.buf)
    end
  end, {
    group = group,
    desc = "lsp.nvim: re-request document symbols after an edit (LSP breadcrumb)",
  })

  autocmd.create("LspAttach", function(args)
    -- A path-only bar right away, symbols as soon as the request answers.
    vim.schedule(function()
      paint_buffer(args.buf)
      if api.nvim_buf_is_valid(args.buf) and M.enabled(vim.bo[args.buf].filetype) then
        symbols.refresh(args.buf)
      end
    end)
  end, {
    group = group,
    desc = "lsp.nvim: draw the LSP breadcrumb once a client attaches",
  })

  autocmd.create("LspDetach", function(args)
    -- Scheduled: the client is still listed while this fires, and `attached`
    -- would still say yes.
    vim.schedule(function()
      paint_buffer(args.buf)
    end)
  end, {
    group = group,
    desc = "lsp.nvim: drop the LSP breadcrumb when the last client detaches",
  })

  autocmd.create("BufWipeout", function(args)
    local handle = refreshers[args.buf]
    if handle then
      handle.cancel()
      refreshers[args.buf] = nil
    end
  end, {
    group = group,
    desc = "lsp.nvim: forget the symbol-refresh timer of a wiped buffer",
  })

  -- A colorscheme change clears every group, the derived chip ones included.
  -- The strings already in a winbar name them, so they are redefined under the
  -- same names. Scheduled: a colorscheme may re-link groups on the same event,
  -- and ours have to be the ones standing afterwards.
  autocmd.create("ColorScheme", function()
    vim.schedule(function()
      render.setup_highlights()
    end)
  end, {
    group = group,
    desc = "lsp.nvim: rebuild the LSP breadcrumb highlights",
  })

  registered = true
  vim.schedule(function()
    paint_all()
    for _, bufnr in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_loaded(bufnr) and symbols.attached(bufnr) then
        symbols.refresh(bufnr)
      end
    end
  end)
end

-- -------------------------------------------------------------------- toggles

---@internal
--- Repaint after a switch changed which windows qualify.
---@return nil
local function reapply()
  paint_all()
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(bufnr) and M.enabled(vim.bo[bufnr].filetype) then
      symbols.refresh(bufnr)
    end
  end
end

--- Set the global default, or one filetype's override.
---@param value boolean
---@param ft string|nil # nil sets the global default.
---@return boolean value # The state now in effect for that scope.
function M.set(value, ft)
  value = value and true or false

  if ft == nil then
    state.enable = value
  else
    state.filetypes[ft] = value
  end

  reapply()
  notify.info(
    ("winbar breadcrumb %s%s"):format(value and "on" or "off", ft and (" for " .. ft) or "")
  )
  return value
end

--- Flip the global default, or one filetype's effective state.
---
--- Toggling a filetype writes an explicit override even when the result equals
--- the global default -- otherwise a later change to the global would silently
--- undo the toggle just made.
---@param ft string|nil
---@return boolean value
function M.toggle(ft)
  return M.set(not M.enabled(ft), ft)
end

--- Drop a filetype's override so it follows the global default again.
---@param ft string
---@return nil
function M.clear(ft)
  if state.filetypes[ft] == nil then
    notify.info(("winbar breadcrumb: %s had no override"):format(ft))
    return
  end
  state.filetypes[ft] = nil
  reapply()
  notify.info(
    ("winbar breadcrumb: %s follows the global default (%s)"):format(
      ft,
      state.enable and "on" or "off"
    )
  )
end

--- Filetypes that carry an explicit override, for command completion.
---@return string[]
function M.overridden()
  ---@type string[]
  local fts = vim.tbl_keys(state.filetypes)
  table.sort(fts)
  return fts
end

--- Human-readable lines for `:Lsp winbar status`.
---@return string[]
function M.status()
  local lines = {
    "lsp.nvim - winbar breadcrumb",
    "",
    ("global:         %s"):format(state.enable and "on" or "off"),
    ("handlers:       %s"):format(registered and "registered" or "not registered"),
    ("style:          %s"):format(state.chips and "chips" or "flat"),
    ("align:          %s"):format(state.align),
    ("path:           %s"):format(
      state.show_file and ("file + %d folder(s)"):format(state.folder_level) or "hidden"
    ),
    ("debounce:       cursor %dms, symbols %dms"):format(state.debounce_ms, state.refresh_ms),
  }

  local caps = {}
  for ft, n in pairs(state.max_symbols) do
    caps[#caps + 1] = ("%s=%d"):format(ft, n)
  end
  table.sort(caps)
  lines[#lines + 1] = ("depth caps:     %s"):format(
    #caps > 0 and table.concat(caps, ", ") or "(none)"
  )

  local fts = M.overridden()
  lines[#lines + 1] = ""
  if #fts == 0 then
    lines[#lines + 1] = "per-filetype overrides: (none)"
  else
    lines[#lines + 1] = "per-filetype overrides"
    for _, ft in ipairs(fts) do
      lines[#lines + 1] = ("  %-16s %s"):format(ft, state.filetypes[ft] and "on" or "off")
    end
  end

  local bufnr = api.nvim_get_current_buf()
  local provider = symbols.provider(bufnr)
  lines[#lines + 1] = ""
  lines[#lines + 1] = provider
      and ("documentSymbolProvider in this buffer: %s"):format(provider.name)
    or "this buffer has no client advertising documentSymbolProvider"
  lines[#lines + 1] = ("symbols cached: %s"):format(
    symbols.get(bufnr) and (symbols.fresh(bufnr) and "yes (fresh)" or "yes (stale)") or "no"
  )
  return lines
end

--- Remove the handlers and every breadcrumb this module drew.
---@return nil
function M.detach()
  if repaint then
    repaint.cancel()
    repaint = nil
  end
  drop_refreshers()
  if unsubscribe then
    unsubscribe()
    unsubscribe = nil
  end
  pcall(api.nvim_del_augroup_by_name, M.GROUP)
  registered = false
  for _, win in ipairs(api.nvim_list_wins()) do
    release(win)
  end
end

return M
