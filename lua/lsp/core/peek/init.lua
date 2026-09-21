---@module 'lsp.core.peek'
---@brief Peek a definition in a floating, editable window, without leaving the code.
---@description
--- `lsd` jumps and loses the place; `lsr` lists. Between them sits "I only want
--- to see what `foo()` does", and that is what this is: the definition (or type
--- definition, implementation, declaration) opens in a float over the current
--- window, and the buffer in it is the **real** buffer -- same highlighting,
--- same LSP, editable. Close it and the cursor is where it was.
---
--- Inside the float (keys are `peek.keys`, buffer-local, and given back when the
--- last peek window over that buffer closes):
---
--- * `q` closes it.
--- * `<C-o>` takes the peeked buffer into the window you came from, `<C-v>` /
---   `<C-x>` into a new vertical / horizontal split, `<C-t>` into a new tab --
---   at the cursor the peek window has *now*, not where it opened.
--- * The peek keymaps work in there too, so a peek from inside a peek stacks
---   another float on top. `q` closes the top one; closing a lower one closes
---   what is above it.
---
--- **Several results.** One definition opens directly. More than one goes
--- through `vim.ui.select` first, with the file and the line, because a float
--- has room for one buffer and picking is the honest answer to "which".
---
--- **Buffers it loaded.** A buffer that was not open before the peek is
--- unloaded again when the peek closes, unless it was modified or is shown
--- somewhere else -- otherwise ten peeks leave ten buffers in the list. A
--- buffer that was already loaded is never touched.
---
--- **The buffer list.** A peek opens its buffer through `bufadd`, which leaves
--- it *unlisted*: right for the buffer it unloads again, wrong for one that
--- stays. A buffer taken into a window and one that was edited and so cannot be
--- unloaded are both listed, so `:ls`, the tabline and the pickers show what
--- the editor is holding.
---
--- lspsaga had this as `peek_definition` / `peek_type_definition`; the float,
--- the four "take it" keys and the nesting are the same idea, minus a plugin.
---
---@see lsp.core.peek.beacon
---@see lsp.bindings.actions

local notify = require("lib.nvim.notify").create("[lsp.core.peek]")
local autocmd = require("lib.nvim.bindings.autocmd")

local api = vim.api

local M = {}

--- Augroup for the `WinClosed` bookkeeping.
---@type string
M.GROUP = "lsp_nvim_peek"

--- What can be peeked, and the request behind each.
---@type table<string, string>
M.METHODS = {
  definition = "textDocument/definition",
  type_definition = "textDocument/typeDefinition",
  implementation = "textDocument/implementation",
  declaration = "textDocument/declaration",
}

---@class LspPeek.Target
---@field uri string
---@field lnum integer # 0-based.
---@field char integer # Character offset in `encoding`.
---@field encoding string

---@class LspPeek.Entry
---@field win integer
---@field buf integer
---@field parent integer # The window it was opened from: a normal one, or the peek below it.
---@field fresh boolean # The buffer was not loaded before this peek loaded it.

--- The open peeks, bottom first.
---@type LspPeek.Entry[]
local stack = {}

--- Buffer -> the keymaps this module put on it and what they replaced.
---@type table<integer, { lhs: string[], previous: table<string, table> }>
local mapped = {}

---@type boolean
local wired = false

---@return LspNvim.PeekOpts
local function opts()
  return require("lsp.config").get().peek
end

-- ------------------------------------------------------------- locations

---@internal
--- The locations in one server's answer, whichever of the three shapes it took:
--- a `Location`, a list of them, or `LocationLink`s.
---@param result table|nil
---@param encoding string
---@param out LspPeek.Target[]
---@return nil
local function collect_locations(result, encoding, out)
  if type(result) ~= "table" then
    return
  end
  -- A single Location is a table with a uri; a list is indexed from 1.
  local list = (result.uri or result.targetUri) and { result } or result
  for _, item in ipairs(list) do
    local uri = item.uri or item.targetUri
    local range = item.range or item.targetSelectionRange or item.targetRange
    if type(uri) == "string" and range and range.start then
      out[#out + 1] = {
        uri = uri,
        lnum = range.start.line,
        char = range.start.character,
        encoding = encoding,
      }
    end
  end
end

--- Flatten the per-client answers of `buf_request_all` into a list without
--- duplicates. Two servers often name the same place (ts_ls and an eslint
--- server, say), and a picker listing it twice would ask a question with one
--- answer.
---@param results table<integer, { err: any, result: any }>
---@return LspPeek.Target[]
function M.flatten(results)
  ---@type LspPeek.Target[]
  local out = {}
  ---@type table<integer, integer>
  local ids = vim.tbl_keys(results)
  table.sort(ids)
  for _, id in ipairs(ids) do
    local client = vim.lsp.get_client_by_id(id)
    local encoding = client and client.offset_encoding or "utf-16"
    local answer = results[id]
    if answer and not answer.err then
      collect_locations(answer.result, encoding, out)
    end
  end

  ---@type LspPeek.Target[]
  local unique = {}
  ---@type table<string, true>
  local seen = {}
  for _, target in ipairs(out) do
    local key = ("%s:%d:%d"):format(target.uri, target.lnum, target.char)
    if not seen[key] then
      seen[key] = true
      unique[#unique + 1] = target
    end
  end
  return unique
end

---@internal
--- A character offset in the server's encoding, as a byte column in a loaded
--- buffer. Falls back to the offset itself, which is exact for ASCII.
---@param bufnr integer
---@param target LspPeek.Target
---@return integer
local function byte_col(bufnr, target)
  local line = api.nvim_buf_get_lines(bufnr, target.lnum, target.lnum + 1, false)[1]
  if line == nil then
    return 0
  end
  local ok, col = pcall(vim.str_byteindex, line, target.encoding, target.char)
  return ok and col or math.min(target.char, #line)
end

-- ---------------------------------------------------------------- keymaps

---@internal
---@param win integer
---@return LspPeek.Entry|nil entry, integer|nil index
local function entry_of(win)
  for i, entry in ipairs(stack) do
    if entry.win == win then
      return entry, i
    end
  end
  return nil, nil
end

--- The peek window the cursor is in, if it is in one.
---@return LspPeek.Entry|nil
function M.current()
  return (entry_of(api.nvim_get_current_win()))
end

--- Every open peek, bottom first. A copy: what callers do with it is theirs.
---@return LspPeek.Entry[]
function M.entries()
  return vim.list_slice(stack, 1, #stack)
end

---@internal
--- Put the peek keys on a buffer, remembering any buffer-local map they
--- shadow so it can be given back.
---@param bufnr integer
---@return nil
local function map_keys(bufnr)
  if mapped[bufnr] then
    return
  end
  local record = { lhs = {}, previous = {} }
  mapped[bufnr] = record

  local actions = {
    close = function()
      M.close()
    end,
    edit = function()
      M.take("edit")
    end,
    vsplit = function()
      M.take("vsplit")
    end,
    split = function()
      M.take("split")
    end,
    tabedit = function()
      M.take("tabedit")
    end,
  }

  for action, fn in pairs(actions) do
    local lhs = opts().keys[action]
    if type(lhs) == "string" and lhs ~= "" then
      -- `maparg` answers for the current buffer, which is the peeked one only
      -- by the coincidence that `open` has just entered its window.
      local prev = api.nvim_buf_call(bufnr, function()
        return vim.fn.maparg(lhs, "n", false, true)
      end)
      if type(prev) == "table" and prev.buffer == 1 then
        record.previous[lhs] = prev
      end
      vim.keymap.set("n", lhs, fn, {
        buffer = bufnr,
        nowait = true,
        silent = true,
        desc = "lsp.nvim peek: " .. action,
      })
      record.lhs[#record.lhs + 1] = lhs
    end
  end
end

---@internal
---@param bufnr integer
---@return nil
local function unmap_keys(bufnr)
  local record = mapped[bufnr]
  mapped[bufnr] = nil
  if not record or not api.nvim_buf_is_valid(bufnr) then
    return
  end
  for _, lhs in ipairs(record.lhs) do
    pcall(vim.keymap.del, "n", lhs, { buffer = bufnr })
    local prev = record.previous[lhs]
    if prev then
      -- `mapset` puts a buffer-local map back into the *current* buffer, and
      -- the float is not always where the cursor is when it closes:
      -- `M.close()` closes the top peek from any window, and a peek closes
      -- the ones stacked above it from `WinClosed`.
      api.nvim_buf_call(bufnr, function()
        pcall(vim.fn.mapset, "n", false, prev)
      end)
    end
  end
end

-- -------------------------------------------------------------- lifecycle

---@internal
--- Everything that has to happen once a peek window is gone, however it went:
--- through `q`, through `:q`, or because the window below it closed.
---@param win integer
---@return nil
local function on_closed(win)
  local entry, index = entry_of(win)
  if not entry or not index then
    return
  end
  table.remove(stack, index)

  -- Whatever was opened from this window has lost its parent. Closed later:
  -- another window cannot be closed from inside `WinClosed`.
  for i = #stack, index, -1 do
    local child = stack[i]
    vim.schedule(function()
      if api.nvim_win_is_valid(child.win) then
        pcall(api.nvim_win_close, child.win, true)
      end
    end)
  end

  local bufnr = entry.buf
  local still_used = false
  for _, other in ipairs(stack) do
    if other.buf == bufnr then
      still_used = true
    end
  end
  if not still_used then
    unmap_keys(bufnr)
  end

  vim.schedule(function()
    -- Focus goes back to where the peek came from, unless something else has
    -- already taken it (a `take` puts it in the window it just filled).
    local current = api.nvim_get_current_win()
    if
      api.nvim_win_is_valid(entry.parent)
      and (not api.nvim_win_is_valid(current) or entry_of(current) ~= nil or current == win)
    then
      pcall(api.nvim_set_current_win, entry.parent)
    end

    -- Give back a buffer this peek loaded, if nothing else holds it. After
    -- the window is gone, or `win_findbuf` still counts it.
    if
      not still_used
      and entry.fresh
      and api.nvim_buf_is_valid(bufnr)
      and api.nvim_buf_is_loaded(bufnr)
      and #vim.fn.win_findbuf(bufnr) == 0
    then
      if vim.bo[bufnr].modified then
        -- It was edited, so it cannot be unloaded -- and it was opened through
        -- `bufadd`, which leaves it unlisted. Loaded, modified and hidden from
        -- `:ls` is a buffer `:qa` refuses to leave and nothing shows: list it,
        -- so it is where the user would look for it.
        vim.bo[bufnr].buflisted = true
      else
        pcall(api.nvim_buf_delete, bufnr, { unload = true })
      end
    end
  end)
end

---@internal
---@return nil
local function wire()
  if wired then
    return
  end
  wired = true
  local group = autocmd.group(M.GROUP, true)
  autocmd.create("WinClosed", function(args)
    local win = tonumber(args.match)
    if win then
      on_closed(win)
    end
  end, {
    group = group,
    desc = "lsp.nvim: release the keymaps and the buffer of a closed peek window",
  })
end

--- Close the peek the cursor is in (and every peek stacked above it), or the
--- top one when the cursor is elsewhere.
---@return nil
function M.close()
  local entry = M.current() or stack[#stack]
  if not entry then
    return
  end
  if api.nvim_win_is_valid(entry.win) then
    pcall(api.nvim_win_close, entry.win, true)
  else
    on_closed(entry.win)
  end
end

--- Close every peek.
---@return nil
function M.close_all()
  for i = #stack, 1, -1 do
    local entry = stack[i]
    if entry and api.nvim_win_is_valid(entry.win) then
      pcall(api.nvim_win_close, entry.win, true)
    end
  end
end

-- ----------------------------------------------------------------- opening

---@internal
--- The float's size and position for the `depth`-th peek. Each level is offset
--- a little, so a stack reads as a stack rather than as one window.
---@param depth integer
---@return table
local function geometry(depth)
  local o = opts()
  local cols = vim.o.columns
  local lines = vim.o.lines - vim.o.cmdheight

  local width = o.width <= 1 and math.floor(cols * o.width) or math.floor(o.width)
  local height = o.height <= 1 and math.floor(lines * o.height) or math.floor(o.height)
  -- Room for the border on both sides, and never wider than the screen.
  width = math.max(20, math.min(width, cols - 4)) - 2
  height = math.max(5, math.min(height, lines - 4)) - 2

  local row = math.floor((lines - height) / 2) - 1 + (depth - 1)
  local col = math.floor((cols - width) / 2) - 1 + (depth - 1) * 2
  return {
    width = width,
    height = height,
    row = math.max(0, row),
    col = math.max(0, col),
  }
end

---@internal
---@param target LspPeek.Target
---@return integer bufnr, boolean fresh
local function load_buffer(target)
  local bufnr = vim.uri_to_bufnr(target.uri)
  local fresh = not api.nvim_buf_is_loaded(bufnr)
  if fresh then
    vim.fn.bufload(bufnr)
    -- `bufload` reads the file and fires `BufRead`, which is where filetype
    -- detection hangs; this covers a file it had no rule for at that moment.
    if vim.bo[bufnr].filetype == "" then
      local ft = vim.filetype.match({ buf = bufnr })
      if ft then
        vim.bo[bufnr].filetype = ft
      end
    end
  end
  return bufnr, fresh
end

--- Open one target in a float.
---@param target LspPeek.Target
---@return LspPeek.Entry|nil
function M.open(target)
  wire()

  local ok, bufnr, fresh = pcall(load_buffer, target)
  if not ok then
    notify.warn("cannot open " .. target.uri .. ": " .. tostring(bufnr))
    return nil
  end
  ---@cast bufnr integer
  ---@cast fresh boolean

  local parent = api.nvim_get_current_win()
  local geo = geometry(#stack + 1)
  local o = opts()

  local name = vim.fn.fnamemodify(api.nvim_buf_get_name(bufnr), ":~:.")
  ---@type table
  local config = {
    relative = "editor",
    row = geo.row,
    col = geo.col,
    width = geo.width,
    height = geo.height,
    border = o.border,
    zindex = 50 + #stack,
  }
  if o.border ~= "none" then
    config.title = (" %s:%d "):format(name ~= "" and name or "[No Name]", target.lnum + 1)
    config.title_pos = "center"
  end

  local win = api.nvim_open_win(bufnr, true, config)

  local wo = vim.wo[win]
  wo.number = true
  wo.relativenumber = false
  wo.cursorline = true
  wo.signcolumn = "no"
  wo.foldenable = false
  wo.wrap = false
  wo.winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"

  local line_count = api.nvim_buf_line_count(bufnr)
  local lnum = math.min(target.lnum, line_count - 1)
  pcall(api.nvim_win_set_cursor, win, { lnum + 1, byte_col(bufnr, target) })
  api.nvim_win_call(win, function()
    vim.cmd("normal! zz")
  end)

  ---@type LspPeek.Entry
  local entry = { win = win, buf = bufnr, parent = parent, fresh = fresh }
  stack[#stack + 1] = entry
  map_keys(bufnr)
  return entry
end

---@internal
---@param target LspPeek.Target
---@return string
local function describe(target)
  local path = vim.fn.fnamemodify(vim.uri_to_fname(target.uri), ":~:.")
  return ("%s:%d"):format(path, target.lnum + 1)
end

--- Ask the attached servers and open the answer.
---
--- Answers from every client that supports the method are merged; one place
--- opens directly, several are offered through `vim.ui.select`.
---@param kind "definition"|"type_definition"|"implementation"|"declaration"
---@return nil
function M.peek(kind)
  local method = M.METHODS[kind]
  if method == nil then
    notify.warn(("unknown peek kind %q"):format(tostring(kind)))
    return
  end

  local bufnr = api.nvim_get_current_buf()
  local win = api.nvim_get_current_win()
  if #vim.lsp.get_clients({ bufnr = bufnr, method = method }) == 0 then
    notify.warn(("no attached server supports %s"):format(method))
    return
  end

  vim.lsp.buf_request_all(bufnr, method, function(client)
    return vim.lsp.util.make_position_params(win, client.offset_encoding)
  end, function(results)
    local targets = M.flatten(results)
    if #targets == 0 then
      notify.info(("no %s found"):format((kind:gsub("_", " "))))
      return
    end
    if #targets == 1 then
      M.open(targets[1])
      return
    end
    vim.ui.select(targets, {
      prompt = ("Peek %s"):format((kind:gsub("_", " "))),
      format_item = describe,
    }, function(choice)
      if choice then
        M.open(choice)
      end
    end)
  end)
end

-- ----------------------------------------------------------------- taking

---@internal
--- The window a peek was ultimately opened from: the parent of the bottom
--- peek, or -- when that one is gone -- any normal window.
---@return integer|nil
local function root_window()
  local first = stack[1]
  if first and api.nvim_win_is_valid(first.parent) and entry_of(first.parent) == nil then
    return first.parent
  end
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_config(win).relative == "" then
      return win
    end
  end
  return nil
end

--- Take the peeked buffer into a real window.
---
--- `edit` puts it in the window the peek came from, `vsplit` / `split` /
--- `tabedit` in a new one. The cursor lands where the peek window's cursor
--- is, the jump is recorded in the jumplist (so `<C-o>` comes back), and every
--- peek is closed.
---@param how "edit"|"vsplit"|"split"|"tabedit"
---@return nil
function M.take(how)
  local entry = M.current()
  if not entry then
    return
  end
  local root = root_window()
  if not root then
    notify.warn("no window to take the peek into")
    return
  end

  local pos = api.nvim_win_get_cursor(entry.win)
  local bufnr = entry.buf

  api.nvim_set_current_win(root)
  -- The jump is recorded before the buffer changes, in the window it leaves.
  vim.cmd("normal! m'")
  if how == "vsplit" then
    vim.cmd("vsplit")
  elseif how == "split" then
    vim.cmd("split")
  elseif how == "tabedit" then
    vim.cmd("tab split")
  end
  local target_win = api.nvim_get_current_win()
  -- The peek opened the buffer through `bufadd`, which leaves it unlisted, and
  -- putting it in a window does not change that: without this it would sit in
  -- a real window that `:ls`, the tabline and every buffer picker deny exists.
  -- `:edit` lists a buffer it switches to, and this is the same act.
  vim.bo[bufnr].buflisted = true
  api.nvim_win_set_buf(target_win, bufnr)
  pcall(api.nvim_win_set_cursor, target_win, pos)
  vim.cmd("normal! zz")

  M.close_all()

  if opts().beacon then
    require("lsp.core.peek.beacon").flash(target_win, pos[1] - 1)
  end
end

return M
