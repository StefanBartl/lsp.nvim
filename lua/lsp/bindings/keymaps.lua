---@module 'lsp.bindings.keymaps'
---@brief Registers the keymap catalogue, honoring the user's overrides.
---@description
--- Reads `config/KEYMAPS.lua`, applies `keymaps.map` and registers what is
--- left through `lib.nvim.map`. No key is hardcoded here: adding a mapping
--- means adding a catalogue entry, which is what keeps `docs/BINDINGS.md`
--- generatable and `:checkhealth lsp` able to list what is actually bound.
---
--- Every action is overridable and every action is switchable off (NEW-21):
--- a string in `keymaps.map` replaces the lhs, `false` drops the mapping, and
--- `keymaps.enable = false` skips the whole step.
---
--- `requires` is recorded, not enforced. Enforcing it would mean probing with
--- `pcall(require, …)` at setup time, which force-loads a plugin the user
--- configured to load on demand -- slower, and a behaviour change. The entries
--- that name a `requires` are command strings that stay inert until pressed
--- (letting the plugin manager load the plugin then) or Lua functions that
--- require lazily inside themselves. `:checkhealth lsp` reports a bound entry
--- whose plugin is absent; that is the right place for it.
---
---@see lsp.config.KEYMAPS
---@see lsp.bindings.actions
---@see lsp.bindings.which_key

local map = require("lib.nvim.map")
local KEYMAPS = require("lsp.config.KEYMAPS")

local M = {}

--- Bind the configured preset.
---@param cfg LspNvim.Config
---@return LspNvim.KeymapSpec[] registered # sorted by catalogue name.
function M.setup(cfg)
  ---@type LspNvim.KeymapSpec[]
  local registered = {}

  if not cfg.keymaps.enable then
    return registered
  end

  local names = KEYMAPS.presets[cfg.keymaps.preset] or {}
  local overrides = cfg.keymaps.map

  -- Sorted so registration order -- and thus docs/BINDINGS.md and the health
  -- report -- is stable across runs rather than following table iteration.
  names = vim.deepcopy(names)
  table.sort(names)

  for _, name in ipairs(names) do
    local spec = KEYMAPS.entries[name]
    local override = overrides[name]

    if spec ~= nil and override ~= false then
      local lhs = (type(override) == "string") and override or spec.lhs
      map(spec.mode, lhs, spec.rhs, { silent = true, desc = "[LSP] " .. spec.desc })
      registered[#registered + 1] = vim.tbl_extend("force", spec, { lhs = lhs, name = name })
    end
  end

  return registered
end

--- Re-bind one catalogue entry buffer-locally.
---
--- Needed for the `gr*` family: Neovim sets `grn`, `grr`, `gri`, `grt` and `gO`
--- buffer-locally on |LspAttach|, and a buffer-local mapping wins over a global
--- one. Without this, the global `grn` from the catalogue would be shadowed the
--- moment a server attaches -- harmless while both call
--- `vim.lsp.buf.rename`, but wrong as soon as `rename.provider` selects
--- inc-rename (roadmap section 8.1).
---@param cfg LspNvim.Config
---@param name string # Catalogue entry name.
---@param bufnr integer
---@return boolean bound
function M.rebind_buffer_local(cfg, name, bufnr)
  if not cfg.keymaps.enable then
    return false
  end

  local names = KEYMAPS.presets[cfg.keymaps.preset] or {}
  if not vim.tbl_contains(names, name) then
    return false
  end

  local spec = KEYMAPS.entries[name]
  local override = cfg.keymaps.map[name]
  if spec == nil or override == false then
    return false
  end

  local lhs = (type(override) == "string") and override or spec.lhs
  map(spec.mode, lhs, spec.rhs, {
    buffer = bufnr,
    silent = true,
    desc = "[LSP] " .. spec.desc,
  })
  return true
end

return M
