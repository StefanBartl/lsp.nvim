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
---@see lsp.@types.subsystem
---@see lsp.@types.vim_lsp

-- Annotations of the migrated subsystem (client/server records, formatter,
-- diagnostics, doctor) and the `vim.lsp.*` types Neovim does not ship. Pulled
-- in here so requiring one types module is enough.
require("lsp.@types.subsystem")
require("lsp.@types.vim_lsp")

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

---@class LspNvim.FormatterOpts
---@field on_save boolean # Format on write at startup; the runtime toggle owns it afterwards.
---@field timeout_ms integer # Upper bound for one format request.

---@class LspNvim.AttachOpts
---@field use_workspace_diagnostics boolean # Populate workspace diagnostics on attach (the module's own size gate still applies).
---@field use_lazydev boolean # Wire lazydev into lua_ls attaches.

---@class LspNvim.MasonOpts
---@field ensure_install boolean # Install missing packages on setup.
---@field overrides table<string, table<string, boolean>> # Per-category force-on/off, keyed lsp/dap/linters/formatters.

---@class LspNvim.ToolOpts
---@field enable boolean # Master switch for this tool.
---@field filetypes string[]|nil # Filetypes it attaches to, where the tool takes a list.

---@class LspNvim.ToolsOpts
---@field eslint_prettier LspNvim.ToolOpts
---@field lsp_signature LspNvim.ToolOpts
---@field ts_type_lookup LspNvim.ToolOpts
---@field deprecated_help LspNvim.ToolOpts

---@class LspNvim.LanguagesOpts
---@field enable boolean # Apply the filetype-specific setup under `lsp/languages/**`.

---@class LspNvim.Config
--- The resolved configuration: DEFAULTS with the user's options merged over
--- them, normalized so every field below is guaranteed present and valid.
---@field servers string[] # Server names to set up and enable.
---@field diagnostics table # Passed straight to `vim.diagnostic.config()`.
---@field formatter LspNvim.FormatterOpts
---@field attach LspNvim.AttachOpts
---@field mason LspNvim.MasonOpts
---@field lspdoctor table # Options forwarded to `lsp.lspdoctor.setup()`.
---@field tools LspNvim.ToolsOpts
---@field languages LspNvim.LanguagesOpts
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
---@field servers string[] # Servers that were set up and enabled.
---@field clients vim.lsp.Client[] # LSP clients currently attached, buffer-independent.
---@field warnings string[] # Non-fatal problems collected during setup().

return {}
