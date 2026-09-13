# Quickstart

Open a file the server should attach to and ask what actually happened:

```vim
:Lsp status
```

Then, when something is not right:

```vim
:Lsp doctor      " why the server for this buffer is not running
:Lsp servers     " what is set up, and which clients are attached here
:Lsp format      " format now, or toggle format-on-save
:Lsp diag        " diagnostics into the quickfix or location list
```

Every route completes with `<Tab>`, over subcommands and arguments both —
`[server]` completes from the live set of clients rather than a list frozen
when the verb was registered.

Verify your setup any time with:

```vim
:checkhealth lsp
```

See [what-you-get.md](what-you-get.md) for the rest of the surface at a
glance, or [commands.md](commands.md) for the full reference.
