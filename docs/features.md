# Features

What the plugin actually does, by area. Configuration for each is in
[configuration.md](configuration.md); the commands are in
[commands.md](commands.md).

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

- **Module:** `formatter/`, `integrations/conform.lua`
- **Config:** `formatter.on_save`, `formatter.timeout_ms`

## Diagnostics

Diagnostics into the quickfix or location list, and navigation within either.
`vim.diagnostic.config()` is applied *after* the servers are enabled, so a
server config cannot overwrite it.

- **Module:** `diagnostics/`, `core/diagnostics.lua`
- **Config:** `diagnostics`

## Workspace diagnostics

A runtime toggle for populating diagnostics workspace-wide on every attach,
with its own size gate — it walks the workspace asynchronously and refuses
above `max_files` rather than freezing the editor on a large repository.

- **Module:** `core/workspace_diagnostics.lua`
- **Commands:** `:Lsp workspace [on|off|toggle|status|now]`

## Root resolution

Per-server project roots, and a global scope switch between the working
directory, the git root and the file's own path. lua_ls additionally treats the
Neovim config directory as a root of its own, which is what its workspace
library needs.

- **Module:** `core/root_scope.lua`, `servers/*/rootresolver.lua`
- **Commands:** `:Lsp root [pick|show]`

## Doctor

`:LspDoctor` in five modes — `health`, `debug`, `quick`, `deep`, `all` —
answering the per-buffer questions: which servers are expected, which are
running, whether their executables resolve, what the clients advertise, and
where two providers overlap.

- **Module:** `lspdoctor/`
- **Config:** `lspdoctor`

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
