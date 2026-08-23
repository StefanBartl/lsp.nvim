# lsp.nvim — Binding Cheatsheet

Every keymap, user command and autocommand `lsp.nvim` defines. This file is
documentation only; the source of truth is `lua/lsp/config/KEYMAPS.lua` (the
keymap catalogue) and `lua/lsp/bindings/` (commands, autocommands). A change
there must be reflected here.

The LSP core has moved in (migration phase 2), so the command family below is
real. The keymap catalogue is still empty and `bindings/autocmds.lua` registers
no autocommand; both are migration phase 3.

## Keymaps

None. `keymaps.preset = "default"` currently resolves to an empty catalogue, so
`setup()` binds nothing.

This is deliberate, not an oversight: the LSP and diagnostics keys still live
in the nvim config, spread across `bindings/mappings/lsp.lua`,
`bindings/mappings/trouble.lua`, `config/inc_rename/`, the FzfLua LSP maps and
`lsp/diagnostics/keymaps.lua`. Claiming half of them here would give two owners
to the same key — one of the problems the umbrella exists to remove. They move
in one step, in phase 3.

The mechanism around them is already in place:

| Config | Effect |
| ------ | ------ |
| `keymaps.enable = false` | Bind nothing at all |
| `keymaps.preset` | `"default"`, `"minimal"` or `"none"` |
| `keymaps.map.<action> = "<lhs>"` | Bind that action to a different key |
| `keymaps.map.<action> = false` | Drop that action's mapping |

Bound prefixes are registered as which-key groups when `which-key.nvim` is
installed and `which_key.enable` is true (which-key v2 and v3 APIs both).

## User Commands

One command, `:Lsp <subcommand>`, built with
[`lib.nvim.usercmd.composer`](https://github.com/StefanBartl/lib.nvim), with
`<Tab>` completion over subcommands and arguments. Registered by `setup()`
unless `usrcmds.enable = false`.

| subcommand | args | range | desc |
| ---------- | ---- | ----- | ---- |
| `:Lsp status` | — | no | Plugin state: config, bound keymaps, `:Lsp` registration, warnings |
| `:Lsp servers` | — | no | Attached LSP clients with root directory and buffer count |
| `:Lsp health` | — | no | Run `:checkhealth lsp` |
| `:Lsp log open` | — | no | Open Neovim's LSP log file in a split |
| `:Lsp log level` | `{trace\|debug\|info\|warn\|error\|off}` | no | Set the LSP log level |

None of these takes a range: they report global state, not something a line
range could narrow.

### Migrated command family

These came with the core and are registered by `setup()`. Roadmap section 8.2
folds them into `:Lsp` routes and keeps them as thin aliases; until then they
are the primary form.

| Command | Source | Effect |
| ------- | ------ | ------ |
| `:LspDoctor {health\|debug\|quick\|deep\|all}` | `lspdoctor/` | Per-buffer LSP diagnosis |
| `:LspStatus` / `:LspInfo` / `:LspLog` | `usercmds/` | Buffer client status, info, log file |
| `:LspRecover` / `:LspForceRestart` | `usercmds/` | Recover missing servers, force a restart |
| `:LspStartHere` / `:LspStopHere` / `:LspRestartHere` | `usercmds/` | Act on the current buffer's client |
| `:LspFormat*` | `usercmds/formatter.lua` | Format once, toggle on-save, show which formatter wins |
| `:LspWorkspaceDiagnostics*` | `usercmds/workspace_diagnostics.lua` | Runtime toggle for workspace-wide diagnostics |
| `:LspMdHints` | `usercmds/` | Marksman hint toggle |
| `:Diag*` | `diagnostics/` | Diagnostics to quickfix/loclist, navigation |
| `:TypeDef*` / `:EslintFix` | `tools/` | Type lookup, ESLint fix |

`vim.g._formatter_api` is published by `setup()` for the format keymaps the
config still owns. It disappears in phase 3, when the keymap catalogue can
close over the formatter directly.

Report output goes to a scratch split rather than a notification: it is
multi-line and meant to be read and copied from.

## Autocommands

None yet. `lua/lsp/bindings/autocmds.lua` owns the augroup name `lsp_nvim` and
a `clear()`, so the group is reloadable from the first handler onward.

Planned (phases 2 and 3): `LspAttach` wiring, the format-on-save group, and the
diagnostics refresh — all under the single group above.
