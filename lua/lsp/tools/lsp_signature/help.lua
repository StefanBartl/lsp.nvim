---@module 'lsp.tools.lsp_signature.help'
--- The Insert-mode signature help (`signature_help`, `<M-s>`): Neovim's own
--- `vim.lsp.buf.signature_help`, framed like the hover of hover.nvim, plus the
--- answer it never gives -- a visible "No signature help".
---
--- Why a wrapper at all: the core call opens a borderless float, and when
--- there is nothing to show it only emits a notification. A notification
--- renderer that swallows that message on purpose (noice does, so a plain
--- `vim.lsp.buf.signature_help()` on a blank line stays quiet) leaves the user
--- with a key that apparently did nothing. The skip rule stays; the feedback
--- is a small float of this module's own instead, in the same border style.
local api = vim.api

local M = {}

local METHOD = "textDocument/signatureHelp"
local NOTICE_TEXT = "No signature help"
--- How long the "no signature" float stays when nothing closes it earlier.
M.NOTICE_TIMEOUT_MS = 2500

--- Border names Neovim understands, plus the styles hover.nvim adds.
---@type string[]
local NATIVE_BORDERS = { "none", "single", "double", "rounded", "solid", "shadow" }

---@type { win: integer|nil, group: integer|nil, timer: uv.uv_timer_t|nil }
local notice = {}

--- Resolve the configured border into what `nvim_open_win` takes.
---
--- Default is "rounded", which is hover.nvim's own default. A style name only
--- hover.nvim knows (`heavy`, `dashed`, ...) is translated through its
--- resolver when that plugin is installed, so one name looks the same in both
--- floats; an unknown name falls back to "rounded" rather than making the
--- window fail to open.
---@param border string|string[]|nil Override; nil reads `tools.lsp_signature.border`.
---@return string|string[]
function M.resolve_border(border)
  if border == nil then
    local ok, cfg = pcall(function()
      return require("lsp.config").get()
    end)
    local tool = ok and cfg and cfg.tools and cfg.tools.lsp_signature
    border = tool and tool.border or nil
  end
  if border == nil then
    return "rounded"
  end
  if type(border) == "table" then
    return border
  end
  if type(border) ~= "string" then
    return "rounded"
  end
  if vim.tbl_contains(NATIVE_BORDERS, border) then
    return border
  end
  local ok, hover_float = pcall(require, "hover.float")
  if ok and type(hover_float.resolve_border) == "function" then
    local names = type(hover_float.border_names) == "function" and hover_float.border_names() or {}
    if vim.tbl_contains(names, border) then
      return hover_float.resolve_border(border)
    end
  end
  return "rounded"
end

--- Close the "no signature" float, if any.
---@return nil
function M.close_notice()
  if notice.timer then
    pcall(function()
      notice.timer:stop()
      notice.timer:close()
    end)
  end
  if notice.group then
    pcall(api.nvim_del_augroup_by_id, notice.group)
  end
  if notice.win and api.nvim_win_is_valid(notice.win) then
    pcall(api.nvim_win_close, notice.win, true)
  end
  notice = {}
end

--- Open the small "No signature help" float at the cursor.
---
--- It closes itself on the next cursor move, on leaving Insert mode or the
--- buffer, or after `NOTICE_TIMEOUT_MS`, whichever comes first.
---@param opts? { border?: string|string[], timeout?: integer }
---@return integer|nil winid
function M.show_notice(opts)
  opts = opts or {}
  M.close_notice()

  local buf = api.nvim_create_buf(false, true)
  if buf == 0 then
    return nil
  end
  api.nvim_buf_set_lines(buf, 0, -1, false, { NOTICE_TEXT })
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false

  local ok, win = pcall(api.nvim_open_win, buf, false, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = vim.fn.strdisplaywidth(NOTICE_TEXT),
    height = 1,
    style = "minimal",
    border = M.resolve_border(opts.border),
    focusable = false,
    noautocmd = true,
  })
  if not ok then
    pcall(api.nvim_buf_delete, buf, { force = true })
    return nil
  end
  -- Window-local, like hover.nvim's float: `vim.wo` would write the global too.
  require("lib.nvim.ui.winhighlight").apply(win, "Normal:NormalFloat,FloatBorder:FloatBorder")

  notice.win = win
  notice.group = api.nvim_create_augroup("LspSignatureNotice", { clear = true })
  -- Armed on the next tick: the key press that opened this float may itself
  -- still be followed by a cursor event.
  vim.schedule(function()
    if notice.win ~= win then
      return
    end
    api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertLeave", "BufLeave" }, {
      group = notice.group,
      once = true,
      callback = M.close_notice,
    })
  end)
  local timer = vim.uv.new_timer()
  if timer then
    notice.timer = timer
    timer:start(
      opts.timeout or M.NOTICE_TIMEOUT_MS,
      0,
      vim.schedule_wrap(function()
        if notice.win == win then
          M.close_notice()
        end
      end)
    )
  end
  return win
end

--- Does any result carry a signature?
---@param results table<integer, { result?: lsp.SignatureHelp }>|nil
---@return boolean
local function has_signature(results)
  for _, r in pairs(results or {}) do
    local res = r.result
    if type(res) == "table" and type(res.signatures) == "table" and res.signatures[1] then
      return true
    end
  end
  return false
end

--- Signature help at the cursor, with a border, and with feedback when empty.
---@param opts? { border?: string|string[], timeout?: integer }
---@return nil
function M.show(opts)
  opts = opts or {}
  local bufnr = api.nvim_get_current_buf()
  local border = M.resolve_border(opts.border)

  M.close_notice()

  if #vim.lsp.get_clients({ bufnr = bufnr, method = METHOD }) == 0 then
    M.show_notice({ border = border, timeout = opts.timeout })
    return
  end

  -- `silent`: the core message is the one a notification renderer may drop;
  -- the empty case is reported by the float below instead.
  vim.lsp.buf.signature_help({ border = border, silent = true })

  local cursor = api.nvim_win_get_cursor(0)
  -- A second, parallel request only to learn whether there was an answer: the
  -- core call shows it but does not report an empty one.
  vim.lsp.buf_request_all(bufnr, METHOD, function(client)
    return vim.lsp.util.make_position_params(0, client.offset_encoding)
  end, function(results)
    if has_signature(results) then
      return
    end
    -- The user moved on while the server thought: the answer is stale.
    if
      api.nvim_get_current_buf() ~= bufnr or not vim.deep_equal(api.nvim_win_get_cursor(0), cursor)
    then
      return
    end
    M.show_notice({ border = border, timeout = opts.timeout })
  end)
end

return M
