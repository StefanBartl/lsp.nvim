# LSP UserCommands - Refactored

## Table of content

- [LSP UserCommands - Refactored](#lsp-usercommands---refactored)
  - [Commands](#commands)
    - [LspStartHere](#lspstarthere)
    - [LspStopHere](#lspstophere)
    - [LspRestartHere](#lsprestarthere)
    - [LspForceRestart](#lspforcerestart)
    - [LspRecover](#lsprecover)
    - [LspInfo](#lspinfo)
    - [LspStatus](#lspstatus)
    - [LspLog](#lsplog)
    - [LspMdHints](#lspmdhints)
  - [Troubleshooting](#troubleshooting)
    - ["Server not attached" after start](#server-not-attached-after-start)
    - ["Exit code 1, signal 15"](#exit-code-1-signal-15)
    - [Server won't start](#server-wont-start)
  - [Technical Notes](#technical-notes)
    - [Why delayed checks?](#why-delayed-checks)

---

## Commands

Every command below except `:LspMdHints` is a legacy alias, and
`usrcmds.legacy_aliases = false` drops the lot of them. The `:Lsp` route named
beside each one is the primary form; the lifecycle commands reach the same
`lsp.usercmds.*` functions through it, so those two cannot drift apart.
`:LspMdHints` is registered either way — it is marksman-specific, and a server
command does not belong in a global verb.

### LspStartHere
Start LSP servers for current buffer. `:Lsp start [server]`.

Auto-detect asks the registered configs which of them declare this buffer's
filetype — the same data `vim.lsp.enable` attaches from, and the same answer
`:LspInfo` and `:LspDoctor startup` report. A server that is already attached
is counted as already running, not as started: the summary reads
`Started 0/1 LSP server(s) (1 already running)` rather than claiming work it
did not do.

Completion offers only names it can actually start — this buffer's filetype
first, then the rest of the registered configs, running ones excluded.
```vim
:LspStartHere          " Auto-detect servers for filetype
:LspStartHere lua_ls   " Start specific server
```

### LspStopHere
Stop the clients attached to the current buffer. `:Lsp stop [server]`.

Graceful first, forced after the timeout (3s). The poll asks whether the client
is gone, not whether `is_stopped()` flipped — that means "shutdown has been
requested", not "the process is gone", and a server that never answers
`shutdown` used to stay attached forever while the command said it had stopped
it. Naming a server stops *every* client carrying that name, not the first one
found.
```vim
:LspStopHere          " Stop every client on this buffer
:LspStopHere lua_ls   " Stop a specific server
```

### LspRestartHere
Restart LSP servers with proper cleanup. `:Lsp restart [server]`.

The summary counts servers, not clients: `supervisor.start` reuses a client for
a name it has already started, so three clients sharing a name go down and one
comes back, and counting the clients reported a restart of three.
```vim
:LspRestartHere          " Restart all servers
:LspRestartHere lua_ls   " Restart specific server
```

### LspForceRestart
Force-restart with full cleanup (use if normal restart fails). Takes exactly
one server name. `:Lsp force-restart {server}`.
```vim
:LspForceRestart lua_ls
```

### LspRecover
Auto-recover missing servers for current filetype. `:Lsp recover`.
```vim
:LspRecover
```

### LspInfo
Detailed LSP information (floating window): the buffer and its filetype, the
servers expected for that filetype with a running marker each, and the attached
clients with their roots. `:Lsp info`.

The expected list comes from `lsp.usercmds.start`, which derives it from the
registered configs. It used to be a hardcoded seventeen-entry filetype table,
and the two disagreed about every filetype that matters — on an `html` buffer
with `tailwindcss` running it listed `html` and `emmet_ls`, which this plugin
does not configure, and never mentioned the server that was actually there.
```vim
:LspInfo
```

### LspStatus
Print the clients attached to the current buffer — id, root and running state
per client — as a notification. `:Lsp status` is the fuller report and opens a
scratch split instead.
```vim
:LspStatus
```

### LspLog
Open LSP log file. `:Lsp log open`; `:Lsp log level {trace|debug|info|warn|error|off}`
sets the level.
```vim
:LspLog
```

### LspMdHints
Toggle marksman's Hint-severity diagnostics — the closest thing marksman has
to an editor "lightbulb" (unresolved references, dangling link suggestions,
etc.). Only affects Hint severity; Error/Warn/Info diagnostics and other
servers are untouched. Also bound to `<leader>lb`.
```vim
:LspMdHints          " toggle
:LspMdHints on
:LspMdHints off
:LspMdHints status    " print current state
```
Implemented in `lsp.servers.marksman.hints` (state) and
`lsp.servers.marksman.diagnostics_handler` (filtering + instant re-publish of
already-open buffers, since marksman only pushes diagnostics on its own
schedule).

## Troubleshooting

### "Server not attached" after start
No longer the expected outcome, so treat it as a real failure. `:LspStartHere`
used to end in "setup completed but not yet attached. Try `:edit`" because it
called `vim.lsp.enable`, which arms an autocommand and launches a client the
next time a matching buffer event fires — an event that never comes for a
buffer that is already open, and the `:edit` was that event. It attaches to the
buffer in hand now.
```vim
:LspForceRestart lua_ls
" or
:LspRecover
```

### "Exit code 1, signal 15"
This is normal - server was killed gracefully. Use `:LspForceRestart` for full cleanup.

### Server won't start
```vim
:LspDoctor startup   " Is it running, and if not, why
:LspDoctor resolve   " Where the filetype -> server chain breaks
:LspLog              " Check for errors
```

## Technical Notes

### Why delayed checks?
LSP startup is asynchronous. We use `vim.defer_fn()` to check attachment status after server initialization.
