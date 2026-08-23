---@module 'lsp.@types'
---@brief Shared type definitions for lsp.nvim.
---@description
--- Top-level annotations for the plugin: the resolved configuration, the
--- declarative keymap catalogue and the status record that `:Lsp status`,
--- `:checkhealth lsp` and the roadmap's future integration layer all read.
---
--- Types live here rather than inline so the source stays readable
--- (LUA-66). Nested levels carry their own `@types/init.lua`.
---
---@see lsp.config
---@see lsp.bindings.keymaps

-- #####################################################################
-- config/DEFAULTS.lua, config/init.lua

---@alias LspNvim.KeymapPreset
--- Which entry of the keymap catalogue is bound on setup.
---| '"default"' # the full preset -- everything the plugin knows about
---| '"minimal"' # only the keys with no plausible native equivalent
---| '"none"'    # bind nothing; the catalogue stays available for manual use

---@class LspNvim.KeymapsOpts
---@field enable boolean # Master switch. false = the plugin binds no keys at all.
---@field preset LspNvim.KeymapPreset # Catalogue entry to bind.
---@field map table<string, string|false> # Per-action override: a string replaces the lhs, false disables that action. An absent key keeps the preset's lhs.

---@class LspNvim.UsrcmdsOpts
---@field enable boolean # Register the `:Lsp` verb on setup.

---@class LspNvim.WhichKeyOpts
---@field enable boolean # Label the bound key prefixes as which-key groups.

---@class LspNvim.Config
--- The resolved configuration: DEFAULTS with the user's options merged over
--- them, normalized so every field below is guaranteed present and valid.
---@field keymaps LspNvim.KeymapsOpts
---@field usrcmds LspNvim.UsrcmdsOpts
---@field which_key LspNvim.WhichKeyOpts

-- #####################################################################
-- config/KEYMAPS.lua, bindings/keymaps.lua

---@class LspNvim.KeymapSpec
--- One entry of the declarative keymap catalogue. `docs/BINDINGS.md` is meant
--- to be generated from these rather than maintained by hand, which is why the
--- description is part of the data instead of a comment.
---@field lhs string # Default left-hand side.
---@field mode string|string[] # Mode(s), as `vim.keymap.set` takes them.
---@field rhs string|fun(): nil # What the key does.
---@field desc string # Human-readable description; also the which-key label.
---@field requires string|nil # Name of an integration that must be available, or nil for "always".

-- #####################################################################
-- init.lua, health.lua

---@class LspNvim.Status
--- Snapshot of what the plugin currently is, shared by `:Lsp status` and
--- `:checkhealth lsp` so the two can never drift apart.
---@field initialized boolean # Has setup() run?
---@field config LspNvim.Config|nil # The resolved config, or nil before setup().
---@field keymaps LspNvim.KeymapSpec[] # Keymaps actually registered.
---@field usrcmd boolean # Was the `:Lsp` verb registered?
---@field clients vim.lsp.Client[] # LSP clients currently attached, buffer-independent.
---@field warnings string[] # Non-fatal problems collected during setup().

return {}
