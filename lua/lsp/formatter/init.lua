---@module 'lsp.formatter'
--- Formatter API with on-save toggle, Conform-first strategy, and view preservation.
---
--- Cross-platform. This file carries no OS-specific code because it needs
--- none: it drives autocommands and view preservation, both platform-neutral.
--- The parts that do differ per platform -- the Mason bin path, the PATH
--- separator, the `.cmd` suffix on Windows -- live in
--- `lsp/formatter/conform.lua` and are branched on there. (The header used to
--- read "Linux/macOS only; no Windows-specific branches", which read as a
--- limitation of the module rather than an accurate description of one file,
--- in a config whose main machine runs Windows.)

local api = vim.api
local Autocmd = require("lib.nvim.bindings.autocmd")

require("lsp.formatter.@types")

local M = {}

--- Build a formatter API instance (stateless config + internal state).
---@param opts? FormatterOptions
---@return FormatterApi
function M.build(opts)
  -- Defensive defaults
  opts = opts or {} ---@type FormatterOptions
  if opts.format_on_save == nil then
    opts.format_on_save = false
  end
  if opts.timeout_ms == nil then
    opts.timeout_ms = 1500
  end

  local ok_conform, conform = pcall(require, "conform")
  local util_ok, util = pcall(require, "lsp.core.util")
  local ok_confmod, confmod = pcall(require, "lsp.formatter.conform")

  ---@type FormatterState
  local STATE = {
    enabled = opts.format_on_save == true,
    augroup = api.nvim_create_augroup("LspFormatOnSave", { clear = true }),
  }

  --- Check if any attached LSP client can format the given buffer.
  ---@param bufnr? integer
  ---@return boolean
  local function can_lsp_format(bufnr)
    if not util_ok or type(util.any_client_can_format) ~= "function" then
      return false
    end
    bufnr = bufnr or 0
    return util.any_client_can_format(bufnr)
  end

  -- Collect per-window views for all windows currently showing bufnr.
  ---@param bufnr integer
  ---@return table<integer, table>
  local function collect_views(bufnr)
    local views = {} ---@type table<integer, table>
    for _, win in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
        local ok, view = pcall(api.nvim_win_call, win, function()
          return vim.fn.winsaveview()
        end)
        if ok and type(view) == "table" then
          views[win] = view
        end
      end
    end
    return views
  end

  -- Restore previously collected views if windows are still valid.
  ---@param views_by_win table<integer, table>
  ---@return nil
  local function restore_views(views_by_win)
    for win, view in pairs(views_by_win) do
      if api.nvim_win_is_valid(win) then
        pcall(api.nvim_win_call, win, function()
          pcall(vim.fn.winrestview, view)
        end)
      end
    end
  end

  --- One-shot format with Conform first, then LSP fallback.
  --- Preserves multi-window views deterministically (synchronous formatting).
  ---@param bufnr? integer
  ---@return boolean
  local function format(bufnr)
    bufnr = bufnr or 0

    -- Skip special buffers early
    if vim.bo[bufnr].buftype ~= "" then
      return false
    end

    -- Snapshot all window views showing this buffer
    local views = collect_views(bufnr)

    -- Prefer dedicated Conform helper if available (synchronous + restore)
    if ok_confmod and type(confmod.format_preserve_view) == "function" then
      local ok_run = confmod.format_preserve_view(
        bufnr,
        { timeout_ms = opts.timeout_ms, lsp_fallback = can_lsp_format(bufnr) }
      )
      -- Views already restored by helper; return early on success
      if ok_run then
        return true
      end
      -- If helper failed, fall through to LSP with our own restore below
    elseif ok_conform and type(conform.format) == "function" then
      -- Run Conform synchronously here and restore views locally
      local ok_run = pcall(conform.format, {
        bufnr = bufnr,
        async = false, -- critical for deterministic restore
        timeout_ms = opts.timeout_ms,
        lsp_fallback = can_lsp_format(bufnr),
      })
      restore_views(views)
      if ok_run then
        return true
      end
      -- Fall through to LSP if Conform failed
    end

    -- LSP fallback (synchronous) with view restore
    if can_lsp_format(bufnr) then
      local ok_lsp = pcall(vim.lsp.buf.format, {
        bufnr = bufnr,
        async = false, -- ensure edits are applied before restoring
        timeout_ms = opts.timeout_ms,
      })
      restore_views(views)
      return ok_lsp == true
    end

    -- Nothing formatted
    restore_views(views) -- harmless if views are identical
    return false
  end

  --- Create the BufWritePre autocmd if enabled; otherwise do nothing.
  --- Uses synchronous formatting to keep view restore deterministic within the write chain.
  local function create_autocmd_if_enabled()
    -- Clear any previous autocmds in our group first (idempotent)
    pcall(api.nvim_clear_autocmds, { group = STATE.augroup })
    if not STATE.enabled then
      return
    end
    Autocmd.create("BufWritePre", function(ev)
      if vim.bo[ev.buf].buftype ~= "" then
        return
      end
      -- Silent one-shot format with view preservation
      format(ev.buf)
    end, {
      group = STATE.augroup,
      desc = "LSP/Conform: format current buffer on save (toggleable, preserves views)",
    })
  end

  --- Enable on-save formatting.
  ---@return boolean
  local function enable()
    if STATE.enabled then
      return true
    end
    STATE.enabled = true
    create_autocmd_if_enabled()
    return true
  end

  --- Disable on-save formatting.
  ---@return boolean
  local function disable()
    if not STATE.enabled then
      return true
    end
    STATE.enabled = false
    pcall(api.nvim_clear_autocmds, { group = STATE.augroup })
    return true
  end

  --- Toggle on-save formatting; return new state (true = enabled).
  ---@return boolean
  local function toggle()
    STATE.enabled = not STATE.enabled
    if STATE.enabled then
      create_autocmd_if_enabled()
    else
      pcall(api.nvim_clear_autocmds, { group = STATE.augroup })
    end
    return STATE.enabled
  end

  ---@return boolean
  local function is_enabled()
    return STATE.enabled
  end

  -- Initialize once according to opts
  create_autocmd_if_enabled()

  return {
    format = format,
    enable = enable,
    disable = disable,
    toggle = toggle,
    is_enabled = is_enabled,
  }
end

return M
