# Commands

The full table — every route, every argument, every legacy alias — is in
[BINDINGS.md](BINDINGS.md). This page is the shape of it.

## One verb

```
:Lsp status | servers | info | health | doctor
:Lsp start | stop | restart | force-restart | recover
:Lsp format | diag | workspace | root | hints | lightbulb | autorestart | log
```

`:Lsp doctor` takes the name of the question you have, not a verbosity level:

```
:Lsp doctor startup       -- is the server running, and if not, why
:Lsp doctor resolve       -- where the filetype -> server chain breaks
:Lsp doctor buffer        -- what is going on in this buffer right now
:Lsp doctor capabilities  -- what the servers here can do, plus workspaces
:Lsp doctor all           -- all four
```

Built with lib.nvim's user-command composer, so subcommands and every closed
argument set complete with `<Tab>`. `[server]` completes from the **live** set —
attached clients first, then everything in `servers` — rather than a list frozen
when the verb was registered.

`:Lsp hints` carries the one argument pair worth spelling out:
`[toggle|on|off|status|clear] [filetype]`. With no filetype it moves the global
default; with one it writes an override for that filetype only, and `clear`
gives the filetype back to the global. `status` reports both levels plus which
loaded buffers actually have a client advertising `inlayHintProvider` — the
distinction between "switched on" and "will show something".

`:Lsp lightbulb` takes the same argument pair for the code-action indicator,
and means the same thing by it. Its `status` answers the question that decides
whether the indicator is worth having here: which clients in this buffer
advertise `codeActionProvider`, which CodeActionKinds are on the allowlist, and
whether a mark is on screen right now.

`:Lsp autorestart` controls whether a crashed server is brought back on its
own. Its `status` is the one worth reading after something went wrong: it names
every server with a failed attempt on record, why the last one failed, and how
far the backoff had got before it gave up.

`:Lsp root` carries two mechanisms, deliberately under one word:

```
:Lsp root show     -- scope, plus every client's resolved root and folders
:Lsp root pick     -- switch the resolution strategy (cwd / git / path)
:Lsp root add      -- add a workspace folder to the running clients
:Lsp root remove   -- take one back off
:Lsp root list     -- what `add` would offer, without opening a picker
```

`pick` changes *how* a root is found and only reaches the servers whose
`root_dir` is a function. `add`/`remove` move LSP's own workspace folders over
`workspace/didChangeWorkspaceFolders`, which reaches every server that
advertises `changeNotifications`, `root_markers` ones included, and takes
effect without a restart. A bare `:Lsp root` runs `show`.

None of the routes takes a range: they act on the current buffer or on global
state, neither of which a line range narrows.

## The flat commands are aliases

The ~25 `:Lsp*` and `:Diag*` commands are still registered and reach the same
functions the routes do. `usrcmds.legacy_aliases = false` drops them.

They are kept because muscle memory beats tidiness and an alias costs a line —
but they are aliases now, not a second implementation, so the two cannot drift
apart. [BINDINGS.md](BINDINGS.md) maps each one to its route.

## Two exceptions

`:LspDoctor` keeps its own verb: it is a diagnostic tool with its own renderer
and six reports, not an LSP control command. It stays registered even with the
aliases off, and is reachable as `:Lsp doctor` as well.

Four of the six were called `health`, `debug`, `quick` and `deep` until
2026-08-29. Those spellings still work everywhere they used to — as command
arguments and as functions — they are simply no longer offered in completion.

`:LspMdHints` is marksman-specific. Server commands do not belong in a global
verb, which is also why `:TypeDef*`, `:EslintFix`, `:AstroDevStart`, `:MdFormat`
and `:LuaLsReloadLibrary` are untouched — they are filetype-bound and belong to
the module that owns them.

## When something is wrong

| Symptom | Start here |
| ------- | ---------- |
| A server is not running | `:Lsp doctor startup` — configured vs. running vs. executable found |
| It runs but behaves oddly | `:Lsp doctor capabilities` — capabilities, workspace, provider conflicts |
| It is not even attempted here | `:Lsp doctor resolve` — where the filetype → server chain breaks |
| Nothing is set up at all | `:Lsp status` — what `setup()` registered, and its warnings |
| Formatting picks the wrong tool | `:Lsp format which` |
| The server is spamming errors | `:Lsp log level warn`, then `:Lsp log open` |
