# Commands

The full table — every route, every argument, every legacy alias — is in
[BINDINGS.md](BINDINGS.md). This page is the shape of it.

## One verb

```
:Lsp status | servers | info | health | doctor
:Lsp start | stop | restart | force-restart | recover
:Lsp format | diag | workspace | root | log
```

Built with lib.nvim's user-command composer, so subcommands and every closed
argument set complete with `<Tab>`. `[server]` completes from the **live** set —
attached clients first, then everything in `servers` — rather than a list frozen
when the verb was registered.

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
and five modes, not an LSP control command. It stays registered even with the
aliases off, and is reachable as `:Lsp doctor` as well.

`:LspMdHints` is marksman-specific. Server commands do not belong in a global
verb, which is also why `:TypeDef*`, `:EslintFix`, `:AstroDevStart`, `:MdFormat`
and `:LuaLsReloadLibrary` are untouched — they are filetype-bound and belong to
the module that owns them.

## When something is wrong

| Symptom | Start here |
| ------- | ---------- |
| A server is not running | `:Lsp doctor health` — configured vs. running vs. executable found |
| It runs but behaves oddly | `:Lsp doctor deep` — capabilities, workspace, provider conflicts |
| Nothing is set up at all | `:Lsp status` — what `setup()` registered, and its warnings |
| Formatting picks the wrong tool | `:Lsp format which` |
| The server is spamming errors | `:Lsp log level warn`, then `:Lsp log open` |
