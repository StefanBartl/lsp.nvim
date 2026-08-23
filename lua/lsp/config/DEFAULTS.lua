---@module 'lsp.config.DEFAULTS'
---@brief Immutable default configuration for lsp.nvim.
---@description
--- Single source of truth for every user-settable value. `config/init.lua`
--- deep-merges the user's options over a copy of this table; the table itself
--- is never mutated at runtime.
---
--- Deliberately small right now. The full option surface designed in
--- `docs/ROADMAP.md` §9 (`servers`, `diagnostics`, `formatter`, `completion`,
--- `rename`, `tools`, `integrations`, `mason`) is *not* listed here yet:
--- nothing consumes those keys until the migration phases land, and a default
--- that nothing reads is a promise the plugin does not keep. Keys move here as
--- the code that honors them arrives.
---
---@see lsp.config
---@see lsp.config.KEYMAPS

---@type LspNvim.Config
local DEFAULTS = {
  keymaps = {
    -- The mechanism is on by default; the "default" catalogue entry is still
    -- empty (see config/KEYMAPS.lua), so this binds nothing until the keymap
    -- consolidation in roadmap phase 3. On by default now means no config
    -- change is needed later, and no key is claimed in the meantime.
    enable = true,
    preset = "default",
    -- Per-action overrides, e.g. `map = { goto_definition = "gd", rename = false }`.
    map = {},
  },

  usrcmds = {
    enable = true,
  },

  which_key = {
    enable = true,
  },
}

return DEFAULTS
