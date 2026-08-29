---@module 'lsp.core.inlay_hints'
---@brief Runtime toggle for `vim.lsp.inlay_hint`, globally and per filetype.
---@description
--- Neovim ships inlay hints natively since 0.10, but ships them *off* and with
--- no switch: `vim.lsp.inlay_hint.enable()` takes a buffer, so "hints on for
--- Lua and off everywhere else" is something every config has to build for
--- itself. This is that switch, in the one place that already knows when a
--- client attaches.
---
--- Two levels, and the second wins: a global default plus a per-filetype
--- override table. `filetypes.lua = false` with `enable = true` means "hints
--- everywhere except Lua"; an absent filetype key inherits the global value.
--- Absent is not the same as `false` -- that distinction is the whole reason
--- the overrides are a map and not a list.
---
--- Applying a change touches every loaded buffer immediately, and an
--- |LspAttach| handler applies the resolved state to buffers that arrive
--- later. The handler lives in this module's own augroup rather than
--- `lsp.bindings.autocmds`, because that group is cleared when
--- `keymaps.enable = false` and hints are not a keymap concern.
---
--- Hints are only requested from clients that advertise `inlayHintProvider`.
--- Neovim tolerates the call on a buffer without one, but then `status()`
--- would report "on" for buffers that will never show a hint, which is the
--- kind of report that costs an hour.
---
--- Driven by `:Lsp hints [on|off|toggle|status] [filetype]` and `<leader>th`.
---
---@see lsp.config.DEFAULTS
---@see lsp.bindings.actions
---@see lsp.core.attach

local notify = require("lib.nvim.notify").create("[lsp.core.inlay_hints]")
local autocmd = require("lib.nvim.bindings.autocmd")

local api = vim.api

local M = {}

--- Augroup for the attach handler. Separate from `lsp_nvim` on purpose: that
--- one belongs to the keymap layer and is cleared with it.
---@type string
M.GROUP = "lsp_nvim_inlay_hints"

---@type { enable: boolean, filetypes: table<string, boolean> }
local state = {
  enable = false,
  filetypes = {},
}

---@type boolean
local registered = false

---@internal
--- Whether this Neovim exposes the native inlay-hint API at all.
---@return boolean
local function available()
  return type(vim.lsp.inlay_hint) == "table" and type(vim.lsp.inlay_hint.enable) == "function"
end

---@internal
--- Does any client attached to `bufnr` advertise `inlayHintProvider`?
---@param bufnr integer
---@return boolean
local function has_provider(bufnr)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if (client.server_capabilities or {}).inlayHintProvider ~= nil then
      return true
    end
  end
  return false
end

---@internal
--- Push the resolved state onto one buffer. Silent about buffers with no
--- provider: they are the normal case, not a failure.
---@param bufnr integer
---@return boolean applied
local function apply_to(bufnr)
  if not (available() and api.nvim_buf_is_loaded(bufnr) and has_provider(bufnr)) then
    return false
  end
  local want = M.enabled(vim.bo[bufnr].filetype)
  pcall(vim.lsp.inlay_hint.enable, want, { bufnr = bufnr })
  return true
end

---@internal
--- Push the resolved state onto every loaded buffer, optionally narrowed to
--- one filetype.
---@param ft string|nil
---@return integer count # Buffers the call reached.
local function apply_all(ft)
  local count = 0
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(bufnr) and (ft == nil or vim.bo[bufnr].filetype == ft) then
      if apply_to(bufnr) then
        count = count + 1
      end
    end
  end
  return count
end

--- Seed the live state from the configuration and register the attach handler.
---
--- Idempotent in the handler: a second `setup()` resets the augroup rather
--- than stacking a second identical autocommand on it.
---@param opts { enable?: boolean, filetypes?: table<string, boolean> }|nil
---@return nil
function M.setup(opts)
  opts = opts or {}
  state.enable = opts.enable and true or false
  state.filetypes = {}
  if type(opts.filetypes) == "table" then
    for ft, value in pairs(opts.filetypes) do
      if type(ft) == "string" and type(value) == "boolean" then
        state.filetypes[ft] = value
      end
    end
  end

  if not available() then
    return
  end

  -- Through lib.nvim rather than `vim.api.nvim_create_autocmd`, which is what
  -- every other autocommand in this plugin does -- see
  -- docs/NOTES/PersonelPlugins/BINDINGS/Autocmds/lsp.nvim.md, which states it
  -- as an invariant of the plugin.
  autocmd.create("LspAttach", function(args)
    -- Deferred: `server_capabilities` is in place by the time LspAttach
    -- fires, but the buffer's filetype may not be settled on the very first
    -- attach of a session, and the filetype is what resolves the override.
    vim.schedule(function()
      if api.nvim_buf_is_valid(args.buf) then
        apply_to(args.buf)
      end
    end)
  end, {
    group = autocmd.group(M.GROUP, true),
    desc = "lsp.nvim: apply the inlay-hint toggle to newly attached buffers",
  })
  registered = true

  apply_all(nil)
end

--- Whether hints are on for a filetype (or globally, with no argument).
---@param ft string|nil # Filetype to resolve; nil asks for the global default.
---@return boolean
function M.enabled(ft)
  if ft ~= nil and state.filetypes[ft] ~= nil then
    return state.filetypes[ft]
  end
  return state.enable
end

--- Set the global default, or one filetype's override.
---@param value boolean
---@param ft string|nil # nil sets the global default.
---@return boolean value # The state now in effect for that scope.
function M.set(value, ft)
  value = value and true or false

  if not available() then
    notify.warn("vim.lsp.inlay_hint is unavailable (Neovim 0.10+ required)")
    return value
  end

  if ft == nil then
    state.enable = value
  else
    state.filetypes[ft] = value
  end

  local touched = apply_all(ft)
  notify.info(
    ("inlay hints %s%s (%d buffer%s)"):format(
      value and "on" or "off",
      ft and (" for " .. ft) or "",
      touched,
      touched == 1 and "" or "s"
    )
  )
  return value
end

--- Flip the global default, or one filetype's effective state.
---
--- Toggling a filetype writes an explicit override even when the result equals
--- the global default -- otherwise a later change to the global would silently
--- undo the toggle the user just made.
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
    notify.info(("inlay hints: %s had no override"):format(ft))
    return
  end
  state.filetypes[ft] = nil
  apply_all(ft)
  notify.info(
    ("inlay hints: %s follows the global default (%s)"):format(ft, state.enable and "on" or "off")
  )
end

--- Human-readable lines for `:Lsp hints status`.
---@return string[]
function M.status()
  if not available() then
    return { "lsp.nvim - inlay hints", "", "vim.lsp.inlay_hint is unavailable (Neovim 0.10+)." }
  end

  local lines = {
    "lsp.nvim - inlay hints",
    "",
    ("global:         %s"):format(state.enable and "on" or "off"),
    ("attach handler: %s"):format(registered and "registered" or "not registered"),
  }

  ---@type string[]
  local fts = vim.tbl_keys(state.filetypes)
  table.sort(fts)
  lines[#lines + 1] = ""
  if #fts == 0 then
    lines[#lines + 1] = "per-filetype overrides: (none)"
  else
    lines[#lines + 1] = "per-filetype overrides"
    for _, ft in ipairs(fts) do
      lines[#lines + 1] = ("  %-16s %s"):format(ft, state.filetypes[ft] and "on" or "off")
    end
  end

  ---@type string[]
  local buffers = {}
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(bufnr) and has_provider(bufnr) then
      local on = type(vim.lsp.inlay_hint.is_enabled) == "function"
        and vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr })
      local ft = vim.bo[bufnr].filetype
      buffers[#buffers + 1] = ("  buffer %-4d %-16s %s"):format(
        bufnr,
        ft ~= "" and ft or "-",
        on and "on" or "off"
      )
    end
  end

  lines[#lines + 1] = ""
  if #buffers == 0 then
    lines[#lines + 1] = "no loaded buffer has a client advertising inlayHintProvider"
  else
    lines[#lines + 1] = "buffers with an inlayHintProvider"
    vim.list_extend(lines, buffers)
  end

  return lines
end

--- Filetypes that carry an explicit override, for command completion.
---@return string[]
function M.overridden()
  local fts = vim.tbl_keys(state.filetypes)
  table.sort(fts)
  return fts
end

--- Remove the attach handler.
---@return nil
function M.detach()
  pcall(api.nvim_del_augroup_by_name, M.GROUP)
  registered = false
end

return M
