# Health Check

```vim
:checkhealth lsp
```

Five sections, in the order you need them when something is wrong.

| Section | Answers |
| ------- | ------- |
| Environment | Neovim 0.11+, and lib.nvim — the one dependency the plugin cannot run without |
| lsp.nvim | Whether `setup()` ran, what it registered, and every warning it worked around |
| Servers | Configured vs. set up vs. attached |
| Ecosystem | Which third-party plugins the adapters can see |
| Per-buffer diagnosis | Points at `:LspDoctor`, which answers the buffer-level questions |

## Reading the Servers section

The gap between the three numbers is usually the answer.

- **Configured but not set up** — the name did not resolve to an
  `lsp.servers.<name>` module, or that module's setup threw. The reason is in
  the warnings above it.
- **Set up but not attached** — expected until you open a matching file. If it
  stays that way, `:Lsp doctor health` adds the missing piece: whether the
  server's executable actually resolves.

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
folders, provider conflicts belong there and are shown by `:Lsp doctor deep`.

It does not list the third-party plugins from a table of its own. The list comes
from the adapter registry, because a list written down twice eventually
disagrees with itself.
