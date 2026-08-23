---@module 'lsp.config.KEYMAPS'
---@brief Declarative catalogue of every keymap lsp.nvim can bind.
---@description
--- Keymaps are data, not code: `bindings/keymaps.lua` iterates this table,
--- applies the user's `keymaps.map` overrides and registers what is left, and
--- `docs/BINDINGS.md` is meant to be generated from the same table rather than
--- kept in sync by hand.
---
--- The catalogue is empty on purpose. Roadmap phase 3 moves the LSP and
--- diagnostics keymaps that today live in five different places of the nvim
--- config (`bindings/mappings/lsp.lua`, `bindings/mappings/trouble.lua`,
--- `config/inc_rename`, the FzfLua LSP maps, `lsp/diagnostics/keymaps.lua`)
--- into these entries. Until then the plugin claims no keys: binding half of
--- them now would collide with the config that still owns them.
---
--- Roadmap §8.1 puts this table in `DEFAULTS.lua`. It lives in its own file
--- instead so `DEFAULTS.lua` stays a pure configuration table -- the catalogue
--- is binding data the user overrides *through* `keymaps.map`, not a config
--- value they set directly.
---
---@see lsp.bindings.keymaps
---@see lsp.config.DEFAULTS

---@type table<LspNvim.KeymapPreset, table<string, LspNvim.KeymapSpec>>
local KEYMAPS = {
  default = {},
  minimal = {},
  none = {},
}

return KEYMAPS
