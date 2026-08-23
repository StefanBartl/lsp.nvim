# LSP UserCommands - Refactored

## Table of content

- [LSP UserCommands - Refactored](#lsp-usercommands-refactored)
  - [Commands](#commands)
    - [LspStartHere](#lspstarthere)
    - [LspStopHere](#lspstophere)
    - [LspRestartHere](#lsprestarthere)
    - [LspForceRestart](#lspforcerestart)
    - [LspRecover](#lsprecover)
    - [LspHealth](#lsphealth)
    - [LspInfo](#lspinfo)
    - [LspDebug](#lspdebug)
    - [LspLog](#lsplog)
    - [LspMdHints](#lspmdhints)
  - [Troubleshooting](#troubleshooting)
    - ["Server not attached" after start](#server-not-attached-after-start)
    - ["Exit code 1, signal 15"](#exit-code-1-signal-15)
    - [Server won't start](#server-wont-start)
  - [Technical Notes](#technical-notes)
    - [Why `{name}` instead of `name`?](#why-name-instead-of-name)
    - [Why delayed checks?](#why-delayed-checks)

---

## Commands

### LspStartHere
Start LSP servers for current buffer.
```vim
:LspStartHere          " Auto-detect servers for filetype
:LspStartHere lua_ls   " Start specific server
```

### LspStopHere
Gracefully stop LSP servers with timeout.
```vim
:LspStopHere          " Stop all servers
:LspStopHere lua_ls   " Stop specific server
```

### LspRestartHere
Restart LSP servers with proper cleanup.
```ascii-vim
:LspRestartHere          " Restart all servers
:LspRestartHere lua_ls   " Restart specific server
```

### LspForceRestart
Force-restart with full cleanup (use if normal restart fails).
```vim
:LspForceRestart lua_ls
```

### LspRecover
Auto-recover missing servers for current filetype.
```vim
:LspRecover
```

### LspHealth
Show LSP health status for current buffer.
```vim
:LspHealth
```

### LspInfo
Detailed LSP information (floating window).
```vim
:LspInfo
```

### LspDebug
Debug information for troubleshooting.
```vim
:LspDebug
```

### LspLog
Open LSP log file.
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
```vim
:LspForceRestart lua_ls
" or
:edit
:LspRecover
```

### "Exit code 1, signal 15"
This is normal - server was killed gracefully. Use `:LspForceRestart` for full cleanup.

### Server won't start
```vim
:LspDebug  " Check configurations
:LspLog    " Check for errors
```

## Technical Notes

### Why `{name}` instead of `name`?
From Neovim docs:
```lua
vim.lsp.enable({client_names})
  -- client_names: string[]
```
The API expects an **array of strings**, not a single string.

### Why delayed checks?
LSP startup is asynchronous. We use `vim.defer_fn()` to check attachment status after server initialization.
