---@module 'lsp.tools.lsp_signature.open_floating_preview'
--- The floating window every path in this module shows its lines in.
---
--- `orig_line` / `orig_col` used to be advertised here as well. Callers pass
--- them -- `fallback_providers` does -- but nothing has ever read them: the
--- position they carry is already baked into the `title` the same caller
--- builds. Documenting an option that is silently dropped is how the `footer`
--- below came to be dropped for a whole release.
local api = vim.api
local fn = vim.fn
local Autocmd = require("lib.nvim.bindings.autocmd")

--- Open the popup for `lines`.
---
--- opts:
---   - title | footer: string, shown as the border title and centred in the
---     window-local statusline. Two names for one value; see below.
---   - focus: boolean, whether the window is focusable and entered on open.
---   - orig_fname: string, buffer name for the scratch buffer, so filetype
---     detection has something to work with. Best-effort: the name may
---     already be taken by an earlier preview of the same file, and `E95` is
---     swallowed rather than raised on the hot path.
---@param lines string[]
---@param opts table|nil
---@return integer|nil bufnr, integer|nil winid
return function(lines, opts)
  opts = opts or {}
  if not lines or vim.tbl_isempty(lines) then
    return nil
  end

  -- Trim leading/trailing empty lines
  while #lines > 0 and lines[1] == "" do
    table.remove(lines, 1)
  end
  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines, #lines)
  end
  if #lines == 0 then
    return nil
  end

  -- `title` and `footer` are the same thing under two names, and the callers
  -- disagree about which: `request_and_show` passes `footer = <workspace or
  -- buffer path>`, `fallback_providers` passes `title = <path:line:col>`.
  -- Only `title` was read, so the signature popup rendered with no border
  -- title and with the *default* statusline -- measured: `cfg.title = nil` and
  -- a statusline still holding `%<%f %h%w%m%r ...`, i.e. the scratch buffer's
  -- own name. Accepting both is cheaper than a rename that has to reach a
  -- module this audit may not touch.
  local title = opts.title or opts.footer

  -- Compute width (max display width of content), cap to 60% of editor width
  local width = 0
  for _, ln in ipairs(lines) do
    local w = fn.strdisplaywidth(ln)
    if w > width then
      width = w
    end
  end
  local max_width = math.floor(vim.o.columns * 0.6)
  if width > max_width then
    width = max_width
  end

  -- Create scratch buffer. `nvim_create_buf` signals failure by returning 0
  -- -- and 0 is not an invalid handle, it is the alias for the *current*
  -- buffer, so an unchecked failure here would silently retarget every call
  -- below at whatever buffer the user is editing.
  local bufnr = api.nvim_create_buf(false, true)
  if bufnr == 0 then
    return nil
  end
  -- If orig_fname was provided, set buffer name so filetype detection can trigger
  if opts.orig_fname and opts.orig_fname ~= "" then
    pcall(api.nvim_buf_set_name, bufnr, opts.orig_fname)
  end

  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
  -- do not force filetype here; prefer detection via buffer name or upstream mapping
  api.nvim_set_option_value("filetype", "lsp_signature", { buf = bufnr })

  -- Enable wrapping & friendly break behaviour so long signature lines wrap inside the float
  pcall(function()
    api.nvim_set_option_value("wrap", true, { buf = bufnr })
  end)
  pcall(function()
    api.nvim_set_option_value("linebreak", true, { buf = bufnr })
  end)
  pcall(function()
    api.nvim_set_option_value("breakindent", true, { buf = bufnr })
  end)

  api.nvim_buf_clear_namespace(bufnr, -1, 0, -1)

  -- Window sizing
  local final_width = math.max(20, width)
  local height = #lines
  local row = 1
  local cursor_win_row = fn.winline()
  if vim.o.lines - cursor_win_row < (height + 4) then
    row = -(height + 1)
  end

  local win_opts = {
    relative = "cursor",
    row = row,
    col = 0,
    width = final_width,
    height = height,
    focusable = opts.focus == true,
    style = "minimal",
    border = "rounded",
    title = title or "",
    title_pos = "center",
  }

  local winid = api.nvim_open_win(bufnr, opts.focus == true, win_opts)

  -- Set window-local statusline to display centered title/path (title already compact)
  if title and title ~= "" then
    local shown = tostring(title)
    local max_title = math.max(10, math.floor(final_width * 0.9))
    if fn.strdisplaywidth(shown) > max_title then
      local short
      if shown:match("[/\\]") then
        short = shown:match("[^/\\]+[/\\][^/\\]+$") or shown:sub(-max_title)
      else
        short = shown:sub(-max_title)
      end
      shown = "…" .. short
    end
    api.nvim_set_option_value("statusline", "%=" .. shown .. "%=", { win = winid })
    api.nvim_set_option_value("winbar", "", { win = winid })
  end

  -- buffer-local mappings to close the popup and clear state
  local map_opts = { nowait = true, noremap = true, silent = true }
  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<Esc>",
    "<Cmd>lua require('lsp.tools.lsp_signature.state').close()<CR>",
    map_opts
  )
  api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "q",
    "<Cmd>lua require('lsp.tools.lsp_signature.state').close()<CR>",
    map_opts
  )
  api.nvim_buf_set_keymap(
    bufnr,
    "v",
    "q",
    "<Cmd>lua require('lsp.tools.lsp_signature.state').close()<CR>",
    map_opts
  )

  local group_name = "LspSignaturePopup_" .. tostring(winid)
  local aug_id = api.nvim_create_augroup(group_name, { clear = true })
  -- `WinClosed` used to be in this list. Its pattern is a *window id*, and a
  -- buffer-local registration compiles to `<buffer=N>`: measured, the autocmd
  -- was created with pattern `<buffer=2>`, which no `WinClosed` can ever
  -- match. Nothing is lost by dropping it -- the window closing wipes the
  -- buffer (`bufhidden=wipe`), so `BufWipeout` is the event that actually
  -- runs, and it is the one that deletes this group again.
  Autocmd.create({ "BufWipeout", "BufHidden", "BufLeave" }, function()
    pcall(require("lsp.tools.lsp_signature.state").close)
    pcall(api.nvim_del_augroup_by_id, aug_id)
  end, {
    group = aug_id,
    once = true,
    buffer = bufnr,
  })

  return bufnr, winid
end
