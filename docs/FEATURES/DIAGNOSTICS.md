# Diagnostics

Where diagnostics go, how you move through them, and what stops a chatty server
from redrawing the screen twenty times per keystroke pause.

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

## Workspace diagnostics

A runtime toggle for populating diagnostics workspace-wide on every attach,
with its own size gate — it walks the workspace asynchronously and refuses
above `max_files` rather than freezing the editor on a large repository.

- **Module:** `core/workspace_diagnostics.lua`
- **Commands:** `:Lsp workspace [on|off|toggle|status|now]`
