# lsp.nvim — Documentation

Everything written down about lsp.nvim, and what each page is for.
The [repository README](../README.md) is the short version; this is the index.

## Start here

| Page | What it answers |
|---|---|
| [installation.md](installation.md) | How do I install it, what does it need, and what is the pack? |
| [FEATURES/](FEATURES/README.md) | What can it actually do, area by area? |
| [WORKFLOW.md](WORKFLOW.md) | Which of the near-identical routes answers which question, day to day? |

## Reference

| Page | What it answers |
|---|---|
| [commands.md](commands.md) | What is the shape of `:Lsp`, and where do I start when something is wrong? |
| [configuration.md](configuration.md) | Why are the options shaped this way, and which layer wins? |
| [BINDINGS.md](BINDINGS.md) | Every keymap, `:Lsp` route, legacy alias and autocommand in one place. |
| [health.md](health.md) | How do I read `:checkhealth lsp`? |

The field-by-field option list is not here: it is `:h lsp.nvim-config`, generated
from the same annotations the code carries, with `lua/lsp/config/DEFAULTS.lua`
as the commented source of every default value.

## Under the hood

| Page | What it answers |
|---|---|
| [architecture.md](architecture.md) | What are the three layers, and which way do the arrows point? |
| Module `README.md`s under `lua/lsp/**` | How does *this* module work, in the detail only its author needs? |

The per-module READMEs are the fifth layer and the deepest one — `lspdoctor/`,
`formatter/`, `diagnostics/`, `languages/`, `servers/lua_ls/`, `servers/marksman/`,
each `tools/` subtree — sitting next to the code they describe. Nothing on this
page duplicates them; go there when the pages above have answered the *what* and
you need the *how*.

## Two things worth knowing once

**The module root is `lsp`.** A Neovim config with its own `lua/lsp/**` wins on
the runtimepath and shadows this plugin completely — nothing looks broken, it
is simply not the code running. [installation.md](installation.md) has the
migration order that avoids it.

**`opts` and `vim.g.lsp_nvim.pack` are two channels.** `opts` decides *how*
everything is configured; `vim.g.lsp_nvim.pack` decides *whether* the
third-party plugins are installed at all, and has to be set before
`require("lazy").setup()`. Putting `pack` inside `opts` fails quietly.

## Generated, not written

`docs/BINDINGS.md`'s keymap tables come from `lua/lsp/config/KEYMAPS.lua` via
`scripts/gen_bindings.lua`, and CI runs it with `--check` — editing them by hand
is pointless, change the catalogue instead.

`docs/map/` is a module map produced by `scripts/gen_map.lua`
([documentation.nvim](https://github.com/StefanBartl/documentation.nvim), or
`:DocMap` in a session). It is derived output and deliberately not committed, so
it exists only where it has been generated.
