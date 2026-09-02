# Features

What the plugin actually does, by area. Configuration for each is in
[configuration.md](configuration.md); the commands are in
[commands.md](commands.md).

## Configuration layers

Four sources, lowest to highest: `DEFAULTS`, the `preset` profile, your
`setup()` options, and a `.nvim-lsp.json` found by walking up from the working
directory. `preset = "lean"` turns down the work paid per keystroke and per
attach without touching on-demand actions; the project file switches a server
off in one checkout without touching the global config. Every warning names the
layer the offending value came from, and `:Lsp status` / `:checkhealth lsp`
name the profile and the project file that were used.

The project file is JSON, not Lua, and accepts only the keys the repository
knows the answer to — cloning a repository must not be enough to run its code
or to move your keys.

- **Modules:** `config/init.lua`, `config/PRESETS.lua`, `config/project.lua`
- **Config:** `preset`, `project.enable`, `project.file`

## Server registry

Resolves the configured `servers` names to `lsp.servers.<name>` modules — with
`lsp.servers.webdev.<name>` as a fallback for dotless names — sets each up with
the shared capabilities/attach table, and enables it. A name whose module is
missing or whose setup throws is skipped with a warning; the rest still come up.

The list is configuration. It used to be a hardcoded `ACTIVE` table inside the
registry, where turning a server on or off meant editing the plugin.

- **Module:** `core/registry.lua`
- **Config:** `servers`

## Capabilities

Builds the client capabilities from the base protocol plus whatever the
completion stacks contribute — NvChad first, then the completion engine, then
blink — and verifies that *something* contributed a completion section, falling
back to a hand-written one when nothing did.

That verification is the point: a silently degraded capability set makes the
editor feel worse with nothing pointing at the cause. It is how the merge bug in
this module was eventually found.

- **Module:** `core/capabilities.lua`, contributors from `integrations/`

## Attach handling

One `on_attach`/`on_init` pair for every server, plus the hooks the integration
layer contributes (lazydev on the first Lua attach, NvChad's own handlers). The
core does not know those plugins exist — it takes hooks.

- **Module:** `core/attach.lua`
- **Config:** `attach.use_workspace_diagnostics`, `attach.use_lazydev`

## Formatter

Conform-first with an LSP fallback, and a format-on-save toggle that preserves
every window's view across the write. `conform.setup()` is called in exactly one
place; the plugin's own autocommand owns format-on-save, never conform's option.

`:LspDoctor`'s formatter section asks conform itself what would run
(`list_formatters_to_run`) rather than deciding a second time, so the report
cannot disagree with a real format. `lspdoctor.formatter_priority` only ranks
the LSP clients listed beneath that — it chooses nothing, which is why it lives
in the reporting namespace.

- **Module:** `formatter/`, `integrations/conform.lua`, `lspdoctor/inspect.lua`
- **Config:** `formatter.on_save`, `formatter.timeout_ms`,
  `lspdoctor.formatter_priority` (report only)

## Diagnostics

Diagnostics into the quickfix or location list, and navigation within either.
`vim.diagnostic.config()` is applied *after* the servers are enabled, so a
server config cannot overwrite it -- everything in `diagnostics` except `ui`,
which has nothing to do with `vim.diagnostic.config()` and is stripped before
that call.

`ui` picks where `]d`/`[d` send you: `"native"` always uses
`vim.diagnostic.jump`; `"trouble"` opens (and focuses) Trouble's diagnostics
list and moves inside it instead, the same way Trouble's own keymaps do;
`"auto"` (the default) is `"trouble"` when Trouble is installed and
`"native"` otherwise. `]w`/`[w` are unaffected either way -- they move inside
an *already open* Trouble list and do nothing if there is none, which is a
deliberately different question from "where does `]d` send me".

Every `textDocument/publishDiagnostics` push is deduplicated and then
throttled. The throttle is leading-edge and per `(client, file)`: the first
push of a burst renders immediately, the ones arriving inside the window are
collapsed down to the newest, and the coalescing never merges — a diagnostics
list replaces a file's diagnostics wholesale, so merging two would resurrect
entries the server had just cleared. `debounce_ms = 0` turns it off.

- **Module:** `diagnostics/`, `core/diagnostics.lua`, `core/handlers.lua`,
  `core/filter.lua`, `bindings/actions.lua`
- **Config:** `diagnostics`, `diagnostics.ui`, `diagnostics.debounce_ms`

## Inlay hints

Neovim ships `vim.lsp.inlay_hint` natively but ships it off and per buffer, so
"hints on for Go, off for Lua" is something every config builds itself. This is
that switch: a global default plus a per-filetype override map, applied to every
loaded buffer at once and to later ones through an `LspAttach` handler.

An absent filetype key inherits the global; `false` overrides it. The two are
deliberately different states — a list where the map belongs would override
nothing, so it is rejected with a warning rather than accepted silently. Only
clients advertising `inlayHintProvider` are asked, which is also what `status`
reports: switched on and will-show-something are separate questions.

- **Module:** `core/inlay_hints.lua`
- **Config:** `inlay_hints.enable`, `inlay_hints.filetypes`
- **Commands:** `:Lsp hints [toggle|on|off|status|clear] [filetype]`
- **Keys:** `<leader>th` (global), `<leader>tH` (this filetype)

## Code-action indicator

`lsa` used to be a blind grab: press it and find out afterwards whether the
server had anything. The indicator asks `textDocument/codeAction` for the cursor
position ahead of the keypress and marks the line when the answer is non-empty.

The kind allowlist is the design, not a refinement of it. An unfiltered
lightbulb is lit permanently under `ts_ls` and `gopls` — both offer refactors on
nearly every line — and a permanently lit indicator carries no information. The
default allowlist is `quickfix` and `source`, so the mark means *something here
is broken and fixable*. Add `"refactor"` for the noisy version; `kinds = {}`
switches the filter off. An action with no `kind` always counts: `kind` is
optional in the protocol, and dropping those would hide every action from a
server that does not classify.

Both obvious places to draw are already taken — the sign column carries
diagnostic signs, `virtual_text` sits at end of line — so `render = "sign"`
borrows the sign column on the cursor line only, at a priority above the
diagnostic signs, and `render = "virtual_text"` draws at the window edge
instead. Requests are debounced, sent only to clients advertising
`codeActionProvider`, marked `triggerKind = 2` (Automatic) so servers that
distinguish it can answer more cheaply, and skipped entirely in insert mode.

- **Module:** `core/lightbulb.lua`
- **Config:** `lightbulb.enable`, `lightbulb.filetypes`, `lightbulb.kinds`,
  `lightbulb.render`, `lightbulb.text`, `lightbulb.debounce_ms`,
  `lightbulb.priority`
- **Commands:** `:Lsp lightbulb [toggle|on|off|status|clear] [filetype]`
- **Keys:** `<leader>tb` (global), `<leader>tB` (this filetype)

## Automatic restart after a crash

A server that dies mid-session is invisible: hover stops answering, completion
goes empty, diagnostics freeze at whatever they last said. It reads as
slowness. The supervisor notices instead and brings the server back before the
next keypress needs it, with an exponential backoff and a cap.

**Crash versus intent is the whole difficulty.** `vim.lsp.stop_client(id, true)`
sends SIGTERM, so a deliberate `:Lsp restart` is indistinguishable from a
server killed by the OOM killer. Intent is therefore *declared*: every
deliberate stop in the plugin calls `expect_stop(id)` first, and a marked exit
is not a crash. Three further exits are deliberately not crashes either — a
clean exit nobody asked for (ambiguous, and restarting risks a loop), an exit
during `:qa`, and a client that died before it ever attached. That last one is
where a retry loop would be a real hazard, and it already has an owner:
`:Lsp recover`.

The counter is cleared by **survival**, not by success: a relaunched client
that is still alive `reset_after_ms` later clears it. Clearing on attach would
let a server that crashes two seconds after every attach restart forever.

The module also owns the per-server attempt counter that `:LspDoctor startup`
reports, for both the automatic restarts and the asked ones in
`usercmds/recovery.lua` — one number, one owner.

- **Module:** `core/supervisor.lua`
- **Config:** `auto_restart.enable`, `auto_restart.max_attempts`,
  `auto_restart.initial_delay_ms`, `auto_restart.max_delay_ms`,
  `auto_restart.reset_after_ms`
- **Commands:** `:Lsp autorestart [toggle|on|off|status]`

## Workspace diagnostics

A runtime toggle for populating diagnostics workspace-wide on every attach,
with its own size gate — it walks the workspace asynchronously and refuses
above `max_files` rather than freezing the editor on a large repository.

- **Module:** `core/workspace_diagnostics.lua`
- **Commands:** `:Lsp workspace [on|off|toggle|status|now]`

## Root resolution and workspace folders

Two mechanisms under one word, because from where you sit both answer "what
does this server consider my project".

The **root scope** is a global switch between the working directory, the git
root and the file's own path. It decides *how* a root is found, and it reaches
the servers whose `root_dir` is a function -- `lua_ls` and `marksman` here.
lua_ls additionally treats the Neovim config directory as a root of its own,
which is what its workspace library needs.

**Workspace folders** are LSP's own multi-root mechanism: a running client
holds a list of them and accepts `workspace/didChangeWorkspaceFolders` to grow
or shrink it. That reaches *every* server that says it supports the
notification, including the `root_markers` ones the scope switch cannot touch,
and it takes effect without a restart. `:Lsp root add` offers the projects
around the current buffer -- upward through its parents, then one level sideways
through container directories like `packages/`, which is where a monorepo's
sibling package lives and where an upward walk never looks.

Only clients that declare both `workspaceFolders.supported` and
`changeNotifications` are sent anything; the rest are listed as skipped, with
the reason, rather than notified into the void.

- **Module:** `core/root_scope.lua`, `core/workspace_folders.lua`,
  `core/workspace_picker.lua`, `servers/*/rootresolver.lua`
- **Commands:** `:Lsp root [pick|show|add|remove|list]`
- **Keymaps:** `<leader>lsp` (scope), `<leader>lsw` (add a workspace folder)
- **Config:** `workspace.markers`, `workspace.containers`

## Doctor

`:LspDoctor` in six reports — `startup`, `resolve`, `buffer`, `capabilities`,
`probe`, `all` — answering the per-buffer questions: which servers are
expected, which are running, whether their executables resolve, where the
filetype → server chain breaks, what the clients advertise, and where two
providers overlap.

Five of them observe. `probe` provokes: it hands the attached clients a buffer
they cannot parse and reports whether diagnostics come back — the only way to
tell a clean file from a dead pipeline, since both look like an empty gutter.
It is not part of `all`, because it is the only report that costs anything.

The first four were called `health`, `debug`, `quick` and `deep` until
2026-08-29. Those spellings still work; they are no longer offered in
completion.

- **Module:** `lspdoctor/`
- **Config:** `lspdoctor`, `lspdoctor.probe_timeout`

## Per-language and per-server setup

Filetype-specific quality-of-life applied before the servers are registered
(`languages/`), and one module per server for the configs that need more than a
table (`servers/`) — lua_ls's library resolver and reload, marksman's own
handlers, and so on.

- **Config:** `languages.enable`, `server_opts`

## Tools

Four extras, each behind its own switch: ESLint/Prettier integration, signature
help, TypeScript type lookup, and deprecation help.

- **Module:** `tools/`
- **Config:** `tools.<name>.enable`

## One picker, not two

The four picker keymaps (`<leader>dos`, `<leader>wos`, `<leader>do`,
`<leader>wo`) are fzf-lua, and so is `:TypeDefPick` since roadmap M4a. It used
to be 171 lines of hand-rolled Telescope — its own finder, entry maker, buffer
previewer and single `<CR>` action — answering the same `workspace/symbol`
request fzf-lua answers with `lsp_workspace_symbols`. Two backends for one kind
of list meant two sets of keys inside the picker, two preview behaviours, and
two plugins to have installed.

Telescope is not gone from the plugin: `languages/webdev/astro` still uses
`telescope.builtin` for component, layout and page navigation, behind a
`FileType astro` autocommand. What is gone is a second picker for the same
list.

`integrations/picker.lua` is still presence-reporting rather than an
abstraction, and says so. An adapter over fzf-lua, telescope, snacks and
pickers.nvim is worth building when there is a second backend to abstract;
removing the second backend was the cheaper half of that trade.

Call hierarchy rides on the same picker and is the reason it was worth
consolidating first: `lsc` asks who calls the symbol under the cursor, `lsC`
what it calls. Neovim ships `vim.lsp.buf.incoming_calls`, but it dumps into the
quickfix list and loses the tree the protocol actually returns; fzf-lua's
providers keep it browsable. `lsc`/`lsC` follow `lsd`/`lsD` — lowercase is the
direction one asks for far more often.

- **Module:** `tools/ts_type_lookup/symbol_picker.lua`, `integrations/picker.lua`
- **Commands:** `:TypeDefPick [symbol]`
- **Keys:** `<leader>dos`, `<leader>wos`, `<leader>do`, `<leader>wo`, `lsc`, `lsC`

## Completion source

An nvim-cmp source that completes dotted plugin names as one atomic candidate
each, ranked by a disk-persisted use counter. The name list is supplied by the
host through `setup({ labels = fn })` — it is the config's data, not the
plugin's.

- **Module:** `completion/personal_names/`

## Right-click context menu

`lsp.integrations.menu` builds entries straight from
`require("lsp").status().keymaps` — the resolved keymap catalogue, with the
active `keymaps.preset` and any `keymaps.map` overrides already applied —
in the shape [nvzone/menu](https://github.com/nvzone/menu) expects, grouped
into fly-outs (Navigation, Rename, Formatter, Diagnostics, Trouble, Picker)
derived from each entry's catalogue name. Entries whose `requires` names an
uninstalled plugin are skipped. No `menu` dependency here; a host composes
the entries into its own menu.

- **Module:** `integrations/menu.lua` (`M.items`, `M.submenu`)
- **Config:** `opts.menu.enable` (default `true`)
- **Docs:** [docs/BINDINGS.md](BINDINGS.md#right-click-context-menu)
