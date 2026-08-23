---@module 'lsp.tools.lsp_signature.open_floating_preview'
-- changes for custom/lsp_signature/open_floating_preview.lua
-- Accept opts.orig_fname / orig_line / orig_col and use them to set buffer name and a compact title.
local api = vim.api
local fn = vim.fn
local Autocmd = require("lib.nvim.autocmd")

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

  local footer = opts.title

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

  -- Create scratch buffer
  local bufnr = api.nvim_create_buf(false, true)
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
    title = opts.title or "",
    title_pos = "center",
  }

  local winid = api.nvim_open_win(bufnr, opts.focus == true, win_opts)

  -- Set window-local statusline to display centered title/path (title already compact)
  if footer and footer ~= "" then
    local title = tostring(footer)
    local max_title = math.max(10, math.floor(final_width * 0.9))
    if fn.strdisplaywidth(title) > max_title then
      local short
      if title:match("[/\\]") then
        short = title:match("[^/\\]+[/\\][^/\\]+$") or title:sub(-max_title)
      else
        short = title:sub(-max_title)
      end
      title = "…" .. short
    end
    api.nvim_set_option_value("statusline", "%=" .. title .. "%=", { win = winid })
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
  Autocmd.create({ "BufWipeout", "BufHidden", "BufLeave", "WinClosed" }, function()
    pcall(require("lsp.tools.lsp_signature.state").close)
    pcall(api.nvim_del_augroup_by_id, aug_id)
  end, {
    group = aug_id,
    once = true,
    buffer = bufnr,
  })

  return bufnr, winid
end
