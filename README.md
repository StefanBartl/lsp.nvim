> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# lsp.nvim

```
    __                        _
   / /________    ____ _   __(_)___ ___
  / / ___/ __ \  / __ \ | / / / __ `__ \
 / (__  ) /_/ / / / / / |/ / / / / / / /
/_/____/ .___(_)_/ /_/|___/_/_/ /_/ /_/
      /_/   one roof for the whole LSP setup
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.11%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)
[![CI](https://github.com/StefanBartl/lsp.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/lsp.nvim/actions/workflows/ci.yml)
[![wkd](https://img.shields.io/badge/wkd-family-c6ff3d)](https://stefanbartl.github.io/wkd/p/lsp/)

> Part of the [wkd](https://stefanbartl.github.io/wkd/) family — see this plugin's [page](https://stefanbartl.github.io/wkd/p/lsp/) on the site.

The umbrella for everything LSP in a Neovim config, behind one `:Lsp` command.
A config's `lua/lsp/**` is usually a pile of settings with the ecosystem left
behind when it gets extracted — this one takes the ecosystem with it.

---

## Around it

> **[dap.nvim](https://github.com/StefanBartl/dap.nvim)** — the same
> architecture applied to the other protocol. LSP tells you what the code
> means, DAP tells you what it does; one umbrella each, so neither ends up
> scattered across a config.
>
> **[insights.nvim](https://github.com/StefanBartl/insights.nvim)** — the
> questions no language server answers: who imports this module, which imports
> are unused, where the magic numbers are.
>
> **[documentation.nvim](https://github.com/StefanBartl/documentation.nvim)** —
> generates the module map this repository deliberately does not commit.
>
> All of the above are soft: without them everything else works unchanged.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) is the one real
> dependency — see [Requirements](docs/requirements.md).

---

## Documentation

Start with the [documentation index](docs/README.md) — it lists every page and
says what each one answers.

### The Basics

- [Requirements](docs/requirements.md) — Neovim version, `lib.nvim`, and what each optional integration buys you.
- [Installation](docs/installation.md) — the pack, the two configuration channels, and the two things that will bite you.
- [Quickstart](docs/quickstart.md) — the first thing to run after installing.

### Configuration

- [What you get with the defaults](docs/what-you-get.md) — the full `:Lsp` route surface at a glance.
- [Configuration](docs/configuration.md) — why the options are shaped this way; the field list is `:h lsp.nvim-config`.
- [Command reference](docs/commands.md) — the shape of `:Lsp`, and where to start when something is wrong.
- [Bindings cheatsheet](docs/BINDINGS.md) — every keymap, route, legacy alias and autocommand, generated from the catalogue.

### The Rest

- [Features](docs/FEATURES/README.md) — what the plugin does, one page per area, with the reasoning, including [navigation](docs/FEATURES/NAVIGATION.md) (peek, code actions with a diff preview, the finder), the [in-buffer indicators](docs/FEATURES/INDICATORS.md) (winbar breadcrumb, implementation markers) and the [context-menu integration](docs/FEATURES/INTEGRATIONS.md).
- [Workflow](docs/WORKFLOW.md) — how the pieces combine day to day, and which route answers which question.
- [Autocommands](docs/autocmds.md) — all 34 of them across 25 groups, not just the four that back keymaps.
- [Architecture](docs/architecture.md) — the three layers, and which way the arrows point.
- [Health check](docs/health.md) — how to read `:checkhealth lsp`.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and how to add a server or an integration.
- [Feedback](https://github.com/StefanBartl/lsp.nvim/issues) — bugs, feature requests and usage questions; broader discussion in [Discussions](https://github.com/StefanBartl/lsp.nvim/discussions).

`:h lsp.nvim` is the same reference inside the editor.

---

## License

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

lsp.nvim is released under the [MIT License](https://opensource.org/licenses/MIT).
