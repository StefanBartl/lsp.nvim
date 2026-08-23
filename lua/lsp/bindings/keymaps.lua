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
---@see lsp.config.KEYMAPS
---@see lsp.bindings.which_key

local map = require("lib.nvim.map")
local KEYMAPS = require("lsp.config.KEYMAPS")

local M = {}

--- Bind the configured preset.
---
--- Entries carrying `requires` are skipped for now: gating a key on an
--- integration ("bind the Trouble variant only if Trouble is loaded") needs the
--- integration registry from roadmap phase 4. Skipping is the safe direction --
--- an unbound key falls back to whatever else owns it, a wrongly bound one does
--- not.
---@param cfg LspNvim.Config
---@return LspNvim.KeymapSpec[] registered # In catalogue order.
function M.setup(cfg)
  ---@type LspNvim.KeymapSpec[]
  local registered = {}

  if not cfg.keymaps.enable then
    return registered
  end

  local catalogue = KEYMAPS[cfg.keymaps.preset] or {}
  local overrides = cfg.keymaps.map

  -- Sorted so the registration order (and thus docs/BINDINGS.md) is stable
  -- across runs rather than following Lua's table iteration order.
  ---@type string[]
  local names = {}
  for name in pairs(catalogue) do
    names[#names + 1] = name
  end
  table.sort(names)

  for _, name in ipairs(names) do
    local spec = catalogue[name]
    local override = overrides[name]

    if override ~= false and spec.requires == nil then
      local lhs = (type(override) == "string") and override or spec.lhs
      map(spec.mode, lhs, spec.rhs, { silent = true, desc = spec.desc })
      registered[#registered + 1] = vim.tbl_extend("force", spec, { lhs = lhs })
    end
  end

  return registered
end

return M
