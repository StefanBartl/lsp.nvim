---@module 'lsp.bindings.@types'
---@brief Type definitions local to the bindings layer.
---@description
--- `LspNvim.KeymapSpec` -- the shape of a catalogue entry -- is declared in
--- `lsp.@types`, because the config layer produces it and `health.lua` and
--- `:Lsp status` both consume it; a type that crosses three layers does not
--- belong to one of them.
---
--- This file exists so the level carries its own types module (LUA-66) and is
--- where bindings-only annotations go: the autocommand descriptors and the
--- which-key group spec, once either grows past a single inline field.
---
---@see lsp.@types

return {}
