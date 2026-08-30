# Health Check

```vim
:checkhealth lsp
```

Five sections, in the order you need them when something is wrong.

| Section | Answers |
| ------- | ------- |
| Environment | Neovim 0.11+, and lib.nvim — the one dependency the plugin cannot run without |
| lsp.nvim | Whether `setup()` ran, which config layers built it, what it registered, and every warning it worked around |
| Servers | Installed vs. configured vs. set up vs. attached — here and in total |
| Ecosystem | Which third-party plugins the adapters can see |
| Per-buffer diagnosis | Points at `:LspDoctor`, which answers the buffer-level questions |

## The two lines above the warnings

The `lsp.nvim` section names the `preset` that was applied and the
`.nvim-lsp.json` that was merged, if any — before the warnings, because the
warnings refer to them: reading `(from .nvim-lsp.json)` is only useful once you
know a project file was found at all, and which one.

This is the answer to "why is `ts_ls` not attaching in this repository". A
project override that nobody can see is a debugging trap, so it is reported
whether or not anything went wrong.

## Reading the Servers section

Four numbers, and the gap between any two of them is usually the answer.

- **Installed but not configured** — Mason has the package on disk and
  `servers` never names it. Not a problem: an installed server that nothing
  sets up is idle. The line exists so the install count is not mistaken for
  something running. Mason's package names are not lspconfig's
  (`lua-language-server` against `lua_ls`), and the mapping between them lives
  in mason-lspconfig, which this plugin does not depend on — so the two lists
  are counts side by side, not a name-for-name comparison.
- **Configured but not set up** — the name did not resolve to an
  `lsp.servers.<name>` module, or that module's setup threw. The reason is in
  the warnings above it.
- **Set up but not attached** — expected until you open a matching file. If it
  stays that way, `:Lsp doctor startup` adds the missing piece: whether the
  server's executable actually resolves.
- **Attached, but not here** — the per-buffer line names which of the running
  clients serve the file you were in when you opened the report. A server can
  be running for a different project root and be irrelevant to the buffer in
  front of you.

### Which buffer is "here"

The one you came from, not the report. Neovim creates the `health://` buffer
and makes it current *before* it runs any check, so the report would otherwise
be describing itself. When there is no file buffer to point at — the report was
opened from an empty session — it says so rather than printing a zero that
looks like a fault.

## The one warning about cost

An installed server costs nothing. A running server costs little. What costs is
a **heavy server held open across many buffers** — `ts_ls`, `pyright`, `jdtls`
and `omnisharp` keep a whole-project model in memory and re-check it per
buffer, so twenty attached buffers is a different machine than two.

That is the only thing in the section that warns, and it warns on the
combination, never on a count alone: five buffers on `ts_ls` is a working set,
and warning about it would train you to skip the section. The warning names the
buffer count and the total line count, so the number is the actual magnitude
rather than an adjective.

## Severity means something

An error is something the plugin cannot work without. Information is something
it uses when present. That is why a missing conform.nvim is an error and a
missing trouble.nvim is not — one is the formatter engine, the other is a UI the
keymap catalogue reaches through command strings.

The same rule applies to keymaps: an entry bound while the plugin it needs is
absent is a **warning**, because it will fail only when pressed, which is the
worst moment to find out.

## It cannot disagree with `:Lsp status`

Both read `require("lsp").status()`. There is no second place where the plugin
describes itself.

## Two things it deliberately does not do

It does not repeat `:LspDoctor`'s per-buffer report — capabilities, workspace
folders, provider conflicts belong there and are shown by
`:Lsp doctor capabilities`.

It does not list the third-party plugins from a table of its own. The list comes
from the adapter registry, because a list written down twice eventually
disagrees with itself.
