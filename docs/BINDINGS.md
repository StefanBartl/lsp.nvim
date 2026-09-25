# lsp.nvim — Binding Cheatsheet

Every keymap, user command and autocommand `lsp.nvim` defines. This file is
documentation only; the source of truth is `lua/lsp/config/KEYMAPS.lua` (the
keymap catalogue) and `lua/lsp/bindings/` (commands, autocommands). A change
there must be reflected here.

The keymap tables are generated from the catalogue and checked by CI, so they
cannot go stale. The prose around them can — including the counts quoted in it,
which is why they are quoted nowhere else.

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
setting and have no ordered target for a count to index into.

Two things worth knowing about the left-hand sides:

- The prefixless `ls*` family costs every Normal-mode `l` a `timeoutlen` wait,
  because Neovim has to see whether an `s` follows. That is the price of a
  prefixless three-character mapping and it is deliberate. The family has
  fourteen members since the peek, finder and type-hierarchy keys joined it
  (`lsp`, `lsT`, `lsf`, `lsh`, `lsH`); none of them is in `minimal`, which
  exists to avoid exactly that wait.
- `grn` and `grt` collide with Neovim 0.11's own `gr*` maps, which are
  **global**, not buffer-local — this page claimed the opposite until it was
  measured. `$VIMRUNTIME/lua/vim/_core/defaults.lua` sets all six at startup,
  "mapped unconditionally to avoid different behavior depending on whether an
  LSP client is attached", and a `--headless --noplugin` session with no
  client at all reports `maparg("grn", "n", false, true).buffer == 0` for
  every one of them. Being global is what makes the catalogue's two entries
  win: they replace Neovim's outright the moment the binder runs — measured,
  `maparg("grn").desc` reads `LSP: Rename symbol` after `setup()` where it
  read `vim.lsp.buf.rename()` before, still with nothing attached. That is
  what makes `rename.provider` decide the rename for both keys, and it does
  not need an `LspAttach` hook to get there. `bindings/autocmds.lua` re-binds
  the pair on `LspAttach` anyway, on the buffer-local premise; see the
  autocommand table below.

<!-- BEGIN GENERATED KEYMAPS -->

The `default` preset binds all 58 entries below. `minimal` binds the 33
marked in the last column; `none` binds nothing.

| action | lhs | mode | needs | minimal | description |
| --- | --- | --- | --- | --- | --- |
| `code_action` | `lsa` | n | — | — | Code action (with diff preview) |
| `code_action_range` | `gra` | x | — | — | Code action for the selection (with diff preview) |
| `diag_code_action` | `<leader>xa` | n | — | — | Quick fix for the diagnostic on this line |
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
| `lightbulb_toggle` | `<leader>tb` | n | — | yes | Toggle the code-action indicator (global) |
| `lightbulb_toggle_filetype` | `<leader>tB` | n | — | yes | Toggle the code-action indicator for this filetype |
| `loc_next` | `]l` | n | — | yes | Next location-list entry |
| `loc_prev` | `[l` | n | — | yes | Prev location-list entry |
| `marksman_hints` | `<leader>lb` | n | — | yes | Toggle Marksman markdown hints |
| `peek_definition` | `lsp` | n | — | — | Peek definition (floating, editable) |
| `peek_type_definition` | `lsT` | n | — | — | Peek type definition (floating, editable) |
| `picker_document_diagnostics` | `<leader>do` | n | `fzf-lua` | yes | Picker: document diagnostics |
| `picker_document_symbols` | `<leader>dos` | n | `fzf-lua` | yes | Picker: document symbols |
| `picker_finder` | `lsf` | n | `fzf-lua` | — | Picker: finder (references + implementations + definitions) |
| `picker_incoming_calls` | `lsc` | n | — | yes | Picker: incoming calls (who calls this) |
| `picker_outgoing_calls` | `lsC` | n | — | yes | Picker: outgoing calls (what this calls) |
| `picker_type_sub` | `lsH` | n | — | — | Picker: subtypes of this type |
| `picker_type_super` | `lsh` | n | — | — | Picker: supertypes of this type |
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
| `trouble_outline` | `<leader>xo` | n | `trouble` | — | Trouble: outline sidebar (document symbols) |
| `trouble_qflist` | `<leader>xq` | n | `trouble` | yes | Trouble: quickfix list |
| `trouble_references` | `<leader>xlr` | n | `trouble` | — | Trouble: references |
| `trouble_symbols` | `<leader>xls` | n | `trouble` | — | Trouble: document symbols |
| `trouble_toggle` | `<leader>xt` | n | `trouble` | yes | Trouble: toggle diagnostics |
| `trouble_type_definitions` | `<leader>xlt` | n | `trouble` | — | Trouble: type definitions |
| `trouble_workspace` | `<leader>xw` | n | `trouble` | yes | Trouble: workspace diagnostics |
| `winbar_toggle` | `<leader>tW` | n | — | — | Toggle the LSP breadcrumb in the winbar (global) |
| `workspace_folder_add` | `<leader>lsw` | n | — | yes | Add a workspace folder (multi-root / monorepo) |

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
[nvzone/menu](https://github.com/nvzone/menu) expects. `rename_leader`,
`goto_type_definition_gr` and `code_action_range` are skipped as pure
alternate-key duplicates of an already-included action; any entry whose
`requires` names a plugin that
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

`opts.menu.enable = false` opts out entirely. `opts.integrations.ui_menu = false`
keeps only ui.nvim's right-click menu (`ui.menu`) from composing the fly-outs;
`items()`/`submenu()` keep working for any other host. The module also answers
`enabled()` (`false` when either switch is off), which is what `ui.menu` asks
first.

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
| `:Lsp doctor` | `{startup\|resolve\|buffer\|capabilities\|probe\|all}` | Per-buffer diagnosis (default `startup`; `all` omits `probe`) |
| `:Lsp start` | `[server]` | Start servers here (auto-detect, or one by name) |
| `:Lsp stop` | `[server]` | Stop clients here (all, or one by name) |
| `:Lsp restart` | `[server]` | Restart clients here (all, or one by name) |
| `:Lsp force-restart` | `{server}` | Restart one server with a full cleanup first |
| `:Lsp recover` | — | Auto-recover servers that should be running here |
| `:Lsp format` | `[once\|on\|off\|toggle\|status\|which]` | Format once (default), or control format-on-save |
| `:Lsp diag` | `{qf\|loc\|next\|prev} [qf\|loc]` | Diagnostics into a list, or move within one |
| `:Lsp workspace` | `[on\|off\|toggle\|status\|now]` | Workspace-wide diagnostics on attach (default `status`) |
| `:Lsp root` | `[pick\|show\|add\|remove\|list]` | Roots and workspace folders (default `show`) |
| `:Lsp hints` | `[toggle\|on\|off\|status\|clear] [filetype]` | Inlay hints, globally or for one filetype (default `toggle`) |
| `:Lsp lightbulb` | `[toggle\|on\|off\|status\|clear] [filetype]` | Code-action indicator, globally or for one filetype (default `toggle`) |
| `:Lsp winbar` | `[toggle\|on\|off\|status\|clear] [filetype]` | LSP breadcrumb in the winbar, globally or for one filetype (default `toggle`) |
| `:Lsp implement` | `[toggle\|on\|off\|status\|clear] [filetype]` | Implementation markers on interfaces, globally or for one filetype (default `toggle`) |
| `:Lsp peek` | `[definition\|type_definition\|implementation\|declaration]` | Peek in a floating, editable window (default `definition`) |
| `:Lsp autorestart` | `[toggle\|on\|off\|status]` | Bring a crashed server back automatically (default `toggle`) |
| `:Lsp log open` | — | Open Neovim's LSP log file in a split |
| `:Lsp log level` | `{trace\|debug\|info\|warn\|error\|off}` | Set the LSP log level |

None of these takes a range: they act on the current buffer or on global
state, neither of which a line range narrows.

Every closed argument set completes with `<Tab>`. `[server]` completes from the
**live** set — attached clients first, then everything in `servers` — through a
custom argument type, because an enum captured when the verb was registered
would go stale the moment a server is added.

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

- `:LspDoctor` — a diagnostic tool with its own renderer and six reports, not an
  LSP control command. It is reachable as `:Lsp doctor` as well.
- `:LspMdHints` — marksman-specific. Server commands do not belong in a global
  verb, which is also why `:TypeDef*`, `:EslintFix`, `:AstroDevStart`,
  `:MdFormat` and `:LuaLsReloadLibrary` are untouched: they are filetype-bound.

`lsp.formatter.set()` publishes the instance the bootstrap built, so the
formatter actions can find it again through `lsp.formatter.get()` without
building a second one.

Report output goes to a scratch split rather than a notification: it is
multi-line and meant to be read and copied from.

## Autocommands

Four augroups belong to the binding layer proper, five more to the indicators
and navigation features (listed here because they are what a key or a command
toggles); the rest of the plugin's autocommands belong to the subsystems that
own them.

| augroup | event | what it does |
| ------- | ----- | ------------ |
| `lsp_nvim` | `LspAttach` | Re-binds the catalogue's `rename` and `goto_type_definition_gr` buffer-locally. The reason `bindings/autocmds.lua` gives for it — that Neovim sets its own `gr*` maps buffer-locally on attach, so a global mapping would be shadowed — does not survive measurement: those maps are global (see above), and the catalogue has already replaced them by the time any client attaches. The re-bind is a no-op over a key the plugin already owns. Registered only when `keymaps.enable` is on; `bindings/autocmds.lua` owns the name and a `clear()`. |
| `lsp_nvim_inlay_hints` | `LspAttach` | Applies the resolved inlay-hint state to a newly attached buffer. Deliberately a separate group: `lsp_nvim` is cleared when `keymaps.enable = false`, and hints are not a keymap concern. `core/inlay_hints.lua` owns it. |
| `lsp_nvim_lightbulb` | `CursorMoved`, `BufEnter`, `InsertLeave`, `DiagnosticChanged`, `InsertEnter`, `LspAttach` | Re-asks `textDocument/codeAction` for the cursor position and marks the line when something comes back, debounced; `InsertEnter` clears it undebounced, because hiding is never what needs rate limiting. Separate group for the same reason as the inlay-hint one. `core/lightbulb.lua` owns it. |
| `lsp_nvim_winbar` | `CursorMoved`, `BufWinEnter`, `WinEnter`, `BufEnter`, `TextChanged`, `InsertLeave`, `LspAttach`, `LspDetach`, `BufWipeout`, `ColorScheme` | Keeps the LSP breadcrumb up to date: the cursor repaints from the symbol cache (debounced, sends nothing), an edit re-requests document symbols (debounced per buffer), an attach draws the path-only bar. Its own group, for the reason the two above give. `core/winbar/` owns it. |
| `lsp_nvim_implement` | `TextChanged`, `InsertLeave`, `BufEnter`, `LspAttach`, `BufWipeout` | Asks for implementations after an edit and marks the interfaces that have some; off unless `implement.enable`. `core/implement.lua` owns it. |
| `lsp_nvim_symbols` | `BufWipeout`, `BufUnload`, `LspDetach` | Drops a buffer's cached document symbols. Created on the first symbol request. `core/symbols.lua` owns it. |
| `lsp_nvim_peek` | `WinClosed` | Gives back the keymaps and the buffer of a closed peek window. Created on the first peek. `core/peek/` owns it. |
| `lsp_nvim_gitsigns_actions` | `User GitSignsUpdate` | Starts the in-process gitsigns code-action server on a buffer gitsigns attached to; only with `code_actions.gitsigns`. `core/gitsigns_actions.lua` owns it. |
| `lsp_nvim_supervisor` | `LspAttach`, `VimLeavePre` | Records which server each client is and which buffers wanted it, because `on_exit` is handed a client id and nothing else at a point where the client is already going away. `VimLeavePre` stops exits being read as crashes during `:qa`. `core/supervisor.lua` owns it. |

Beyond these, `formatter/`, `languages/`, `tools/` and `servers/` each register
their own groups (format-on-save, per-filetype setup, the signature popup's
per-window group, lua_ls's root recompute). They are not listed here because
they are not bindings — the complete inventory is [autocmds.md](autocmds.md),
kept as a separate page so a second copy here does not need to stay in sync.
