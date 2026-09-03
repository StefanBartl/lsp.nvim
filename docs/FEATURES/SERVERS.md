# Servers

Everything between "a name in the `servers` list" and "a client answering
requests in this buffer" — and what happens when one of them dies.

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

## Per-language and per-server setup

Filetype-specific quality-of-life applied before the servers are registered
(`languages/`), and one module per server for the configs that need more than a
table (`servers/`) — lua_ls's library resolver and reload, marksman's own
handlers, and so on.

- **Config:** `languages.enable`
