---@module 'lsp.bindings.keymaps'
---@brief Registers the keymap catalogue, honoring the user's overrides.
---@description
--- Reads `config/KEYMAPS.lua` and hands the catalogue to
--- `lib.nvim.bindings.keymap`'s registry, which applies `keymaps.map` and
--- binds what is left. No key is hardcoded here: adding a mapping means adding
--- a catalogue entry, which is what keeps `docs/BINDINGS.md` generatable and
--- `:checkhealth lsp` able to list what is actually bound.
---
--- The catalogue predates that registry and had grown the same shape
--- independently -- named entries, per-action override, `false` to disable, a
--- list handed back for docs. Moving onto the shared one keeps all of that and
--- adds what a local copy could not: a mistyped name in `keymaps.map` is now
--- *reported* rather than silently binding nothing, and the surface joins the
--- one list `keymap.registered()` answers for every plugin here.
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

local keymap = require("lib.nvim.bindings.keymap")
local KEYMAPS = require("lsp.config.KEYMAPS")

local M = {}

--- Bind the configured preset.
---@param cfg LspNvim.Config
---@return LspNvim.KeymapSpec[] registered # sorted by catalogue name.
function M.setup(cfg)
  -- Sorted so registration order -- and thus docs/BINDINGS.md and the health
  -- report -- is stable across runs rather than following table iteration.
  local names = vim.tbl_keys(KEYMAPS.entries)
  table.sort(names)

  local in_preset = {}
  for _, name in ipairs(KEYMAPS.presets[cfg.keymaps.preset] or {}) do
    in_preset[name] = true
  end

  ---@type table<string, Lib.Keymap.Action>
  local actions = {}
  for name, spec in pairs(KEYMAPS.entries) do
    actions[name] = {
      default = spec.lhs,
      mode = spec.mode,
      rhs = spec.rhs,
      desc = spec.desc,
      opts = { silent = true },
    }
  end

  -- Entries outside the selected preset are forced off rather than left out:
  -- `:checkhealth lsp` and the generated bindings page ask what EXISTS, and
  -- "in the catalogue, not in this preset" is a different answer from "no such
  -- entry".
  local user = vim.deepcopy(cfg.keymaps.map or {})
  for _, name in ipairs(names) do
    if not in_preset[name] and user[name] == nil then
      user[name] = false
    end
  end

  local bound = keymap.register("LSP", { order = names, actions = actions }, user, {
    bind = cfg.keymaps.enable ~= false,
  })

  ---@type LspNvim.KeymapSpec[]
  local registered = {}
  for _, e in ipairs(bound) do
    if e.bound then
      registered[#registered + 1] =
        vim.tbl_extend("force", KEYMAPS.entries[e.name], { lhs = e.lhs, name = e.name })
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
  -- The one-off setter, not the registry: this re-binds a single entry that is
  -- already declared, to shadow a buffer-local default Neovim installs itself.
  -- Registering it again would replace the plugin's whole record with one
  -- action.
  keymap(spec.mode, lhs, spec.rhs, {
    buffer = bufnr,
    silent = true,
    desc = "LSP: " .. spec.desc,
  })
  return true
end

return M
