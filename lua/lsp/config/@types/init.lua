---@module 'lsp.config.@types'
---@brief Type definitions local to the configuration layer.
---@description
--- The configuration types themselves (`LspNvim.Config`, `LspNvim.KeymapsOpts`,
--- `LspNvim.KeymapPreset`, ...) are declared one level up in `lsp.@types`,
--- because `health.lua`, `bindings/` and the future integration layer all
--- reference them -- keeping them here would make every consumer depend on the
--- config module's private types.
---
--- This file exists so the level has its own types module as the rules require
--- (LUA-66), and is where config-only annotations go once there are any: the
--- per-domain option tables from `docs/ROADMAP.md` §9 (`servers`,
--- `diagnostics`, `formatter`, `completion`, `rename`, `mason`) are expected
--- to land here rather than swell the top-level file.
---
---@see lsp.@types

return {}
