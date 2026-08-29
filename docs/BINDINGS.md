# lsp.nvim — Binding Cheatsheet

Every keymap, user command and autocommand `lsp.nvim` defines. This file is
documentation only; the source of truth is `lua/lsp/config/KEYMAPS.lua` (the
keymap catalogue) and `lua/lsp/bindings/` (commands, autocommands). A change
there must be reflected here.

The LSP core has moved in (migration phase 2), so the command family below is
real. The keymap catalogue is still empty and `bindings/autocmds.lua` registers
no autocommand; both are migration phase 3.

## Keymaps

The tables below are **generated** from `lua/lsp/config/KEYMAPS.lua` by
`scripts/gen_bindings.lua`, which CI runs with `--check`. Editing them by hand
is pointless: change the catalogue instead.

These keys used to live in five places — `bindings/mappings/lsp.lua`,
`bindings/mappings/trouble.lua`, the LSP lines of `bindings/mappings/fzf.lua`,
`config/inc_rename/`, and this plugin's own `diagnostics/keymaps.lua` — with
two pairs of them owned twice over. One catalogue, one owner.

| Config | Effect |
| ------ | ------ |
| `keymaps.enable = false` | Bind nothing at all |
| `keymaps.preset` | `"default"`, `"minimal"` or `"none"` |
| `keymaps.map.<action> = "<lhs>"` | Bind that action to a different key |
| `keymaps.map.<action> = false` | Drop that action's mapping |

The `needs` column names a third-party plugin. It is recorded, not enforced:
probing at bind time would force-load a plugin configured to load on demand.
Those entries are command strings that stay inert until pressed, or Lua
functions that require lazily. `:checkhealth lsp` reports any that are bound
while their plugin is missing.

The eight motion keys honour a count: `3]q` moves three quickfix entries,
`2]d` two diagnostics. `]d`/`[d`, `]q`/`[q`, `]l`/`[l` and `]w`/`[w` are the
ones that mean "move"; the leader-prefixed actions populate a list or toggle a
setting and have no ordered target for a count to index into (NEW-25).

Three things worth knowing about the left-hand sides:

- The prefixless `ls*` family costs every Normal-mode `l` a `timeoutlen` wait,
  because Neovim has to see whether an `s` follows. That is the price of a
  prefixless three-character mapping and it is deliberate.
- `grn` and `grt` collide with Neovim 0.11's own `gr*` maps, which are set
  **buffer-locally** on `LspAttach` and therefore win over a global mapping.
  `bindings/autocmds.lua` re-binds those two on `LspAttach` so the catalogue's
  version is the one that runs — which matters as soon as `rename.provider`
  selects inc-rename.

<!-- BEGIN GENERATED KEYMAPS -->

The `default` preset binds all 44 entries below. `minimal` binds the 28
marked in the last column; `none` binds nothing.

| action | lhs | mode | needs | minimal | description |
| --- | --- | --- | --- | --- | --- |
| `code_action` | `lsa` | n | — | — | Code action |
| `diag_next` | `]d` | n, x, o | — | — | Next diagnostic (buffer) |
| `diag_prev` | `[d` | n, x, o | — | — | Prev diagnostic (buffer) |
| `diag_setqflist` | `<leader>tq` | n | — | yes | Diagnostics -> quickfix (plain) |
| `diag_to_loclist` | `<leader>lq` | n | — | yes | Diagnostics -> loclist (buffer) |
| `diag_to_qflist` | `<leader>wq` | n | — | yes | Diagnostics -> quickfix (workspace) |
| `document_symbols` | `lss` | n | — | — | Document symbols |
| `format_buffer` | `<leader>ft` | n | — | yes | Format buffer once |
| `format_lsp` | `<leader>fl` | n | — | yes | Format via the language server directly |
| `format_toggle` | `<leader>tft` | n | — | yes | Toggle format-on-save |
| `goto_declaration` | `lsD` | n | — | — | Go to declaration |
| `goto_definition` | `lsd` | n | — | — | Go to definition |
| `goto_implementations` | `lsi` | n | — | — | List implementations |
| `goto_references` | `lsr` | n | — | — | List references |
| `goto_type_definition` | `lst` | n | — | — | Go to type definition |
| `goto_type_definition_gr` | `grt` | n | — | — | Go to type definition (g-prefix variant) |
| `hints_toggle` | `<leader>th` | n | — | yes | Toggle inlay hints (global) |
| `hints_toggle_filetype` | `<leader>tH` | n | — | yes | Toggle inlay hints for this filetype |
| `loc_next` | `]l` | n | — | yes | Next location-list entry |
| `loc_prev` | `[l` | n | — | yes | Prev location-list entry |
| `marksman_hints` | `<leader>lb` | n | — | yes | Toggle Marksman markdown hints |
| `picker_document_diagnostics` | `<leader>do` | n | `fzf-lua` | yes | Picker: document diagnostics |
| `picker_document_symbols` | `<leader>dos` | n | `fzf-lua` | yes | Picker: document symbols |
| `picker_workspace_diagnostics` | `<leader>wo` | n | `fzf-lua` | yes | Picker: workspace diagnostics |
| `picker_workspace_symbols` | `<leader>wos` | n | `fzf-lua` | yes | Picker: workspace symbols (live) |
| `qf_next` | `]q` | n | — | yes | Next quickfix entry |
| `qf_prev` | `[q` | n | — | yes | Prev quickfix entry |
| `rename` | `grn` | n | — | — | Rename symbol |
| `rename_leader` | `<leader>rn` | n | — | yes | Rename symbol (leader variant) |
| `root_scope_pick` | `<leader>lsp` | n | — | yes | Pick root scope (cwd / git root / file path) |
| `signature_help` | `<M-s>` | i | — | yes | Signature help |
| `trouble_all` | `<leader>xx` | n | `trouble` | yes | Trouble: all diagnostics |
| `trouble_buffer` | `<leader>xd` | n | `trouble` | yes | Trouble: buffer diagnostics |
| `trouble_definitions` | `<leader>xld` | n | `trouble` | — | Trouble: definitions |
| `trouble_diag_next` | `]w` | n | `trouble` | yes | Next entry in the open Trouble diagnostics list |
| `trouble_diag_prev` | `[w` | n | `trouble` | yes | Prev entry in the open Trouble diagnostics list |
| `trouble_implementations` | `<leader>xli` | n | `trouble` | — | Trouble: implementations |
| `trouble_loclist` | `<leader>xl` | n | `trouble` | yes | Trouble: location list |
| `trouble_qflist` | `<leader>xq` | n | `trouble` | yes | Trouble: quickfix list |
| `trouble_references` | `<leader>xlr` | n | `trouble` | — | Trouble: references |
| `trouble_symbols` | `<leader>xls` | n | `trouble` | — | Trouble: document symbols |
| `trouble_toggle` | `<leader>xt` | n | `trouble` | yes | Trouble: toggle diagnostics |
| `trouble_type_definitions` | `<leader>xlt` | n | `trouble` | — | Trouble: type definitions |
| `trouble_workspace` | `<leader>xw` | n | `trouble` | yes | Trouble: workspace diagnostics |

which-key group labels:

| prefix | label |
| --- | --- |
| `<leader>x` | Trouble / LSP lists |
| `<leader>xl` | Trouble LSP views |

<!-- END GENERATED KEYMAPS -->

## Right-click context menu

`lsp.integrations.menu` builds entries straight from
`require("lsp").status().keymaps` — the resolved catalogue above, with the
active `keymaps.preset` and any `keymaps.map` overrides/disables already
applied — the same anti-drift reasoning `config/KEYMAPS.lua` itself exists
for. Grouped into fly-outs (Navigation, Rename, Formatter, Diagnostics,
Trouble, Picker) derived from each entry's catalogue name, in the shape
[nvzone/menu](https://github.com/nvzone/menu) expects. `rename_leader` and
`goto_type_definition_gr` are skipped as pure alternate-key duplicates of an
already-included action; any entry whose `requires` names a plugin that
isn't installed (Trouble, fzf-lua) is skipped too — a menu entry is
something you're actively looking at, so one that would just error on
click is worse than one that doesn't appear.

lsp.nvim has no dependency on `menu` and never opens a context menu itself
— a host (typically your own `<RightMouse>` dispatcher) composes the
entries into its own menu:

```lua
local items = require("lsp.integrations.menu").items()  -- one entry per group, each a fly-out
local sub = require("lsp.integrations.menu").submenu()  -- { name = "  LSP", items = {…} } | nil
```

`opts.menu.enable = false` opts out entirely.

## User Commands

One command, `:Lsp <subcommand>`, built with
[`lib.nvim.bindings.usercmd.composer`](https://github.com/StefanBartl/lib.nvim), with
`<Tab>` completion over subcommands and arguments. Registered by `setup()`
unless `usrcmds.enable = false`.

| subcommand | args | desc |
| ---------- | ---- | ---- |
| `:Lsp status` | — | Plugin state: config, bound keymaps, servers, warnings |
| `:Lsp servers` | — | Servers set up, and the clients currently attached |
| `:Lsp info` | — | Detailed LSP information for the current buffer |
| `:Lsp health` | — | Run `:checkhealth lsp` |
| `:Lsp doctor` | `{health\|debug\|quick\|deep\|all}` | Per-buffer diagnosis (default `health`) |
| `:Lsp start` | `[server]` | Start servers here (auto-detect, or one by name) |
| `:Lsp stop` | `[server]` | Stop clients here (all, or one by name) |
| `:Lsp restart` | `[server]` | Restart clients here (all, or one by name) |
| `:Lsp force-restart` | `{server}` | Restart one server with a full cleanup first |
| `:Lsp recover` | — | Auto-recover servers that should be running here |
| `:Lsp format` | `[once\|on\|off\|toggle\|status\|which]` | Format once (default), or control format-on-save |
| `:Lsp diag` | `{qf\|loc\|next\|prev} [qf\|loc]` | Diagnostics into a list, or move within one |
| `:Lsp workspace` | `[on\|off\|toggle\|status\|now]` | Workspace-wide diagnostics on attach (default `status`) |
| `:Lsp root` | `[pick\|show]` | Root scope: pick between cwd / git root / path (default `pick`) |
| `:Lsp log open` | — | Open Neovim's LSP log file in a split |
| `:Lsp log level` | `{trace\|debug\|info\|warn\|error\|off}` | Set the LSP log level |

None of these takes a range: they act on the current buffer or on global
state, neither of which a line range narrows.

Every closed argument set completes with `<Tab>`. `[server]` completes from the
**live** set — attached clients first, then everything in `servers` — through a
custom argument type, because an enum captured when the verb was registered
would go stale the moment a server is added (NEW-26).

### Legacy aliases

The flat commands the migration brought along are still registered, and reach
the same functions as the routes above. Switch them off with
`usrcmds.legacy_aliases = false`.

| Alias | Route |
| ----- | ----- |
| `:LspStatus` | `:Lsp servers` (it reports the buffer's clients) |
| `:LspInfo` | `:Lsp info` |
| `:LspLog` | `:Lsp log open` |
| `:LspRecover` | `:Lsp recover` |
| `:LspForceRestart {server}` | `:Lsp force-restart {server}` |
| `:LspStartHere` / `:LspStopHere` / `:LspRestartHere` | `:Lsp start` / `stop` / `restart` |
| `:LspFormat` / `On` / `Off` / `Toggle` / `Status` / `Which` | `:Lsp format [once\|on\|off\|toggle\|status\|which]` |
| `:LspWorkspaceDiagnostics{On,Off,Toggle,Status,Now}` | `:Lsp workspace [on\|off\|toggle\|status\|now]` |
| `:DiagQF` / `:DiagLoc` | `:Lsp diag qf` / `:Lsp diag loc` |
| `:DiagNextQF` / `:DiagPrevQF` | `:Lsp diag next qf` / `:Lsp diag prev qf` |
| `:DiagNextLoc` / `:DiagPrevLoc` | `:Lsp diag next loc` / `:Lsp diag prev loc` |

Two commands are **not** aliases and stay registered either way:

- `:LspDoctor` — a diagnostic tool with its own renderer and five modes, not an
  LSP control command. It is reachable as `:Lsp doctor` as well.
- `:LspMdHints` — marksman-specific. Server commands do not belong in a global
  verb, which is also why `:TypeDef*`, `:EslintFix`, `:AstroDevStart`,
  `:MdFormat` and `:LuaLsReloadLibrary` are untouched: they are filetype-bound.

`vim.g._formatter_api` is published by `setup()` so the formatter actions can
find the instance the bootstrap built.

Report output goes to a scratch split rather than a notification: it is
multi-line and meant to be read and copied from.

## Autocommands

None yet. `lua/lsp/bindings/autocmds.lua` owns the augroup name `lsp_nvim` and
a `clear()`, so the group is reloadable from the first handler onward.

Planned (phases 2 and 3): `LspAttach` wiring, the format-on-save group, and the
diagnostics refresh — all under the single group above.
