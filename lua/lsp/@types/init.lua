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

---@alias LspNvim.Preset
--- Named option profile the configuration starts from, below the `setup()`
--- options. Not `keymaps.preset`, which picks a set of keys: this picks a set
--- of options, one of which is `keymaps.preset`.
---| '"default"' # the documented defaults, unchanged
---| '"lean"'    # continuous per-keystroke/per-attach work turned down
---| '"full"'    # every feature on, at the cost of more work per keystroke

---@class LspNvim.ProjectOpts
---@field enable? boolean # Look for a per-project override file at all.
---@field file? string # Its name; found by walking upward from the working directory at setup() time.

---@class LspNvim.ConfigLayers
--- Which layers the active configuration was actually built from. Reported by
--- `:Lsp status` and `:checkhealth lsp`: an override nobody can see is a
--- debugging trap.
---@field preset LspNvim.Preset # Profile that was applied.
---@field project string|nil # Absolute path of the project file that was merged, or nil when none was found or it was disabled.

---@alias LspNvim.KeymapPreset
--- Which entry of the keymap catalogue is bound on setup.
---| '"default"' # the full preset -- everything the plugin knows about
---| '"minimal"' # only the keys with no plausible native equivalent
---| '"none"'    # bind nothing; the catalogue stays available for manual use

---@class LspNvim.KeymapsOpts
---@field enable? boolean # Master switch. false = the plugin binds no keys at all.
---@field preset? LspNvim.KeymapPreset # Catalogue entry to bind.
---@field map? table<string, string|false> # Per-action override: a string replaces the lhs, false disables that action. An absent key keeps the preset's lhs.

---@class LspNvim.UsrcmdsOpts
---@field enable? boolean # Register the `:Lsp` verb on setup.
---@field legacy_aliases? boolean # Also register the flat `:Lsp*`/`:Diag*` commands as aliases onto the same functions.

---@class LspNvim.WhichKeyOpts
---@field enable? boolean # Label the bound key prefixes as which-key groups.

---@class LspNvim.MenuOpts
---@field enable? boolean # Provide nvzone/menu entries via `lsp.integrations.menu`. No nvzone/menu dependency itself; this only gates whether `M.items()`/`M.submenu()` return entries.

---@class LspNvim.FormatterOpts
---@field on_save? boolean # Format on write at startup; the runtime toggle owns it afterwards.
---@field timeout_ms? integer # Upper bound for one format request.

---@class LspNvim.WorkspaceOpts
---@field markers? string[] # A directory holding one of these is offered as a workspace-folder candidate. Replaces the default list rather than extending it.
---@field containers? string[] # Directory names that hold projects rather than being one; the sibling scan descends exactly one level through them.

---@class LspNvim.InlayHintsOpts
---@field enable? boolean # Global default for `vim.lsp.inlay_hint`; the runtime toggle owns it afterwards.
---@field filetypes? table<string, boolean> # Per-filetype override. An absent key inherits `enable`; `false` is an explicit off.

---@class LspNvim.LightbulbOpts
--- The code-action indicator. `filetypes` resolves exactly like
--- `LspNvim.InlayHintsOpts.filetypes`.
---@field enable? boolean # Global default; the runtime toggle owns it afterwards.
---@field filetypes? table<string, boolean> # Per-filetype override. An absent key inherits `enable`; `false` is an explicit off.
---@field kinds? string[] # CodeActionKind prefixes that light the indicator. Empty means unfiltered; an action without a kind always counts.
---@field render? "sign"|"virtual_text" # Sign column on the cursor line, or `right_align` virtual text.
---@field text? string # The indicator itself. Truncated to two display cells when rendered as a sign.
---@field debounce_ms? integer # Window between the last cursor movement and the request.
---@field priority? integer # Extmark priority. Above `vim.diagnostic`'s signs (10) by default.

---@class LspNvim.AttachOpts
---@field use_workspace_diagnostics? boolean # Populate workspace diagnostics on attach (the module's own size gate still applies).
---@field use_lazydev? boolean # Wire lazydev into lua_ls attaches.

---@class LspNvim.MasonOpts
---@field ensure_install? boolean # Install missing packages on setup.
---@field overrides? table<string, table<string, boolean>> # Per-category force-on/off, keyed lsp/dap/linters/formatters.

---@class LspNvim.ToolOpts
---@field enable? boolean # Master switch for this tool.
---@field filetypes string[]|nil # Filetypes it attaches to, where the tool takes a list.

---@class LspNvim.ToolsOpts
---@field eslint_prettier? LspNvim.ToolOpts
---@field lsp_signature? LspNvim.ToolOpts
---@field ts_type_lookup? LspNvim.ToolOpts
---@field deprecated_help? LspNvim.ToolOpts

---@class LspNvim.LanguagesOpts
---@field enable? boolean # Apply the filetype-specific setup under `lsp/languages/**`.

---@alias LspNvim.RenameProvider
--- Which backend the rename action uses. Both bound rename keys go through it.
---| '"auto"'       # inc-rename when installed, `vim.lsp.buf.rename` otherwise
---| '"inc_rename"' # always inc-rename (no-op if it is not installed)
---| '"native"'     # always `vim.lsp.buf.rename`

---@class LspNvim.RenameOpts
---@field provider? LspNvim.RenameProvider

---@class LspNvim.Config
--- The resolved configuration: DEFAULTS, then the preset, then the user's
--- options, then the project file merged over one another and normalized, so
--- every field below is guaranteed present and valid.
---@field preset? LspNvim.Preset # Option profile the rest starts from.
---@field project? LspNvim.ProjectOpts # Per-project override file lookup.
---@field servers? string[] # Server names to set up and enable.
---@field diagnostics? table # Passed straight to `vim.diagnostic.config()`.
---@field formatter? LspNvim.FormatterOpts
---@field workspace? LspNvim.WorkspaceOpts
---@field inlay_hints? LspNvim.InlayHintsOpts
---@field lightbulb? LspNvim.LightbulbOpts
---@field attach? LspNvim.AttachOpts
---@field mason? LspNvim.MasonOpts
---@field lspdoctor? table # Options forwarded to `lsp.lspdoctor.setup()`.
---@field tools? LspNvim.ToolsOpts
---@field languages? LspNvim.LanguagesOpts
---@field rename? LspNvim.RenameOpts
---@field keymaps? LspNvim.KeymapsOpts
---@field usrcmds? LspNvim.UsrcmdsOpts
---@field which_key? LspNvim.WhichKeyOpts
---@field menu? LspNvim.MenuOpts

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
---@field requires string|nil # Third-party plugin this entry needs. Recorded, not enforced: see `lsp.bindings.keymaps`.
---@field name string|nil # Catalogue key. Set by the binder on the returned copies, absent in the catalogue itself.

-- #####################################################################
-- integrations/

---@class LspNvim.Integration
--- One third-party plugin's adapter. Everything except `available` is
--- optional: most adapters only answer "is this installed", and the ones that
--- contribute do so through whichever of the hooks applies.
---@field plugin string # Plugin name, for the health report.
---@field hard boolean|nil # true when the plugin's absence degrades this plugin's own behaviour.
---@field note string|nil # One line for the health report saying what it is for.
---@field available fun(): boolean # Is the plugin installed/loadable?
---@field setup fun(cfg: LspNvim.Config)|nil # Called once during setup(), in adapter order.
---@field capabilities LspCaps.Contributor|nil # Merge into the client capabilities.
---@field on_attach fun(client: table, bufnr: integer)|nil # Run on every LspAttach.
---@field on_init fun(client: table)|nil # Run on every client init.

---@class LspNvim.IntegrationStatus
--- One row of `integrations.report()`, consumed by `:checkhealth lsp`.
---@field name string # Adapter module name.
---@field plugin string # Plugin it wraps.
---@field available boolean
---@field hard boolean
---@field note string

-- #####################################################################
-- init.lua, health.lua

---@class LspNvim.Status
--- Snapshot of what the plugin currently is, shared by `:Lsp status` and
--- `:checkhealth lsp` so the two can never drift apart.
---@field initialized boolean # Has setup() run?
---@field config LspNvim.Config|nil # The resolved config, or nil before setup().
---@field layers LspNvim.ConfigLayers # Which preset and which project file the config was built from.
---@field keymaps LspNvim.KeymapSpec[] # Keymaps actually registered.
---@field usrcmd boolean # Was the `:Lsp` verb registered?
---@field servers string[] # Servers that were set up and enabled.
---@field clients vim.lsp.Client[] # LSP clients currently attached, buffer-independent.
---@field warnings string[] # Non-fatal problems collected during setup().

return {}
