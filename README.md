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

The umbrella for everything LSP in a Neovim config, behind one `:Lsp` command.

A config's `lua/lsp/**` is not a pile of settings, it is a stateful subsystem —
a registry, an attach handler, a capabilities merge, runtime toggles. The part
usually left behind when it gets extracted is the ecosystem around it, and what
remains is `trouble.nvim` configured in one file, `conform.nvim` in two
contradicting ones, and `]q` bound twice by modules that do not know about each
other. This one takes the ecosystem with it.

---

## Table of contents

- [Documentation](#documentation)
- [What it does](#what-it-does)
- [Around it](#around-it)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [What you get with the defaults](#what-you-get-with-the-defaults)
- [Integrations](#integrations)
- [Health check](#health-check)
- [Contributing](#contributing)
- [Feedback](#feedback)
- [License](#license)

---

## Documentation

Start with the [documentation index](docs/README.md) — it lists every page and
says what each one answers.

- [Features](docs/FEATURES/README.md) — what the plugin does, one page per area, with the reasoning.
- [Installation](docs/installation.md) — the pack, the two configuration channels, and the two things that will bite you.
- [Configuration](docs/configuration.md) — why the options are shaped this way; the field list is `:h lsp.nvim-config`.
- [Command reference](docs/commands.md) — the shape of `:Lsp`, and where to start when something is wrong.
- [Workflow](docs/WORKFLOW.md) — how the pieces combine day to day, and which route answers which question.
- [Bindings cheatsheet](docs/BINDINGS.md) — every keymap, route, legacy alias and autocommand, generated from the catalogue.
- [Autocommands](docs/autocmds.md) — all 33 of them across 25 groups, not just the four that back keymaps.
- [Architecture](docs/architecture.md) — the three layers, and which way the arrows point.
- [Health](docs/health.md) — how to read `:checkhealth lsp`.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and how to add a server or an integration.

`:h lsp.nvim` is the same reference inside the editor.

---

## What it does

Everything LSP-related lives under one root and answers to one verb, in three
layers — core, integrations, pack — with the arrows pointing one way only.
[docs/architecture.md](docs/architecture.md) has the argument.

| Area | Does |
| --- | --- |
| **Servers** | A registry resolving configured names to modules, merging capabilities, owning attach, and bringing a crashed server back with a bounded backoff |
| **Configuration** | Four layers — defaults, a `preset` profile, your `setup()` options, a per-project `.nvim-lsp.json` — and every warning names the layer the bad value came from |
| **Diagnostics** | Into the quickfix or location list, with a leading-edge throttle on `publishDiagnostics`, and a workspace-wide toggle that refuses above its size gate rather than freezing the editor |
| **Formatter** | conform-first with an LSP fallback, and a format-on-save toggle this plugin owns rather than conform |
| **In-buffer indicators** | Inlay hints and a code-action indicator, each global plus per-filetype, both filtered so they carry information |
| **Roots and workspaces** | A scope switch for the servers that resolve a root themselves, and LSP's own multi-root mechanism for the rest |
| **`:LspDoctor`** | Six per-buffer reports. Five observe; `probe` provokes, which is the only way to tell a clean file from a dead pipeline |
| **Tools and integrations** | ESLint/Prettier, signature help, type lookup, deprecation help, one picker backend, and a context menu built from the resolved keymap catalogue |

Everything the plugin binds is data: `lua/lsp/config/KEYMAPS.lua` is the
catalogue, `keymaps.map` overrides any entry by name without touching the
plugin, and `docs/BINDINGS.md` is generated from that same table by CI — so the
two cannot drift.

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
> dependency — see [Requirements](#requirements).

---

## Requirements

| | |
| --- | --- |
| Neovim | **0.11+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required — the `:Lsp` command is built on its user-command composer and does not register without it |

Optional, each detected at runtime and degrading to nothing when absent — the
pack installs and configures them for you, or bring your own:

| | |
| --- | --- |
| [conform.nvim](https://github.com/stevearc/conform.nvim) | The formatter front end; without it formatting falls back to the LSP |
| [trouble.nvim](https://github.com/folke/trouble.nvim) | The diagnostics list |
| [lazydev.nvim](https://github.com/folke/lazydev.nvim) | Neovim-aware `lua_ls` completion |
| [workspace-diagnostics.nvim](https://github.com/artemave/workspace-diagnostics.nvim) | Diagnostics beyond the open buffers |
| [lspsaga.nvim](https://github.com/nvimdev/lspsaga.nvim) | The winbar breadcrumb, re-cut per filetype by this plugin's adapter |
| [lensline.nvim](https://github.com/oribarilan/lensline.nvim) | Code lenses |
| [inc-rename.nvim](https://github.com/smjonas/inc-rename.nvim) | Live-preview rename |
| [mason.nvim](https://github.com/mason-org/mason.nvim) | Server and tool installation |
| A completion engine | nvim-cmp or [blink.cmp](https://github.com/saghen/blink.cmp), both wired if present |
| [nvzone/menu](https://github.com/nvzone/menu) | A host for the context-menu entries — see [Integrations](#integrations) |

`:checkhealth lsp` reports which of them resolved.

---

## Installation

```lua
-- lazy.nvim
{
  "StefanBartl/lsp.nvim",
  import = "lsp.pack",   -- installs the ecosystem too; drop it to bring your own
  dependencies = { "StefanBartl/lib.nvim" },
  event = { "BufReadPre", "BufNewFile" },
  opts = {},
}
```

With `import = "lsp.pack"` you also get conform, lazydev,
workspace-diagnostics, trouble, lspsaga, lensline and inc-rename, configured.
Without it you get the plugin alone: it wires up whatever of those happens to
be installed and reports the rest in `:checkhealth lsp`.

Two things worth knowing before the first start:

**`opts` and `vim.g.lsp_nvim.pack` are two channels.** `opts` decides *how*
everything is configured; `vim.g.lsp_nvim.pack` decides *whether* the
third-party plugins are installed at all, and has to be set before
`require("lazy").setup()`. Putting `pack` inside `opts` fails quietly.

**The module root is `lsp`**, chosen so that existing `require("lsp.…")` paths
in a config keep resolving after the code moves here. While a config still has
its own `lua/lsp/**`, that directory wins on the runtimepath and shadows this
plugin — nothing looks broken, it is simply not the code running. The two are
meant to swap, not to coexist.

[docs/installation.md](docs/installation.md) has the migration order that
avoids that, and covers packer/pckr and vim-plug.

---

## Quickstart

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

---

## What you get with the defaults

| Route | Does |
| --- | --- |
| `:Lsp status` / `info` / `health` | What `setup()` registered, and every warning it worked around |
| `:Lsp servers` | What is set up, and which clients are attached to this buffer |
| `:Lsp doctor <report>` | `startup`, `resolve`, `buffer`, `capabilities`, `probe`, or `all` |
| `:Lsp start` / `stop` / `restart` / `force-restart` / `recover` | The server lifecycle |
| `:Lsp format` | Format now, and toggle format-on-save |
| `:Lsp diag` | Diagnostics into the quickfix or location list |
| `:Lsp workspace` | The workspace-wide diagnostics toggle, with its size gate |
| `:Lsp root show` / `pick` / `add` / `remove` / `list` | Resolution strategy, and LSP's own workspace folders |
| `:Lsp hints [toggle\|on\|off\|status\|clear] [filetype]` | Inlay hints, globally or per filetype |
| `:Lsp lightbulb …` | The code-action indicator, same argument pair |
| `:Lsp autorestart` | Whether a crashed server comes back, and why the last attempt failed |
| `:Lsp log` | The LSP log |

`:Lsp doctor probe` is the odd one out and stays out of `all` deliberately: it
builds a buffer of deliberately broken content, hands it to this buffer's
clients and waits for an answer. That is the only way to tell a clean file from
a dead pipeline — both look like an empty gutter — and the only report that
costs anything.

The full route table, the ~25 flat legacy aliases and every keymap are in
[docs/BINDINGS.md](docs/BINDINGS.md).

---

## Integrations

One adapter per third-party plugin. Two of them add something rather than only
wiring a plugin up — both are written up in
[docs/FEATURES/INTEGRATIONS.md](docs/FEATURES/INTEGRATIONS.md).

### Context menu

`lsp.integrations.menu` contributes context-aware entries in the shape
[nvzone/menu](https://github.com/nvzone/menu) expects, grouped into fly-outs
(Navigation, Rename, Formatter, Diagnostics, Trouble, Picker). lsp.nvim has
**no** dependency on `menu` and never opens a context menu itself; a host —
typically your own `<RightMouse>` dispatcher — composes these entries into its
own menu.

The entries are built from `require("lsp").status().keymaps`, the same resolved
catalogue the plugin actually registered, so they cannot drift from the keys.
An entry whose `requires` names an uninstalled plugin is skipped: a keymap
nobody presses is harmless, a menu entry that would only error on click is not.
Opt out with `menu.enable = false`.

### Breadcrumb depth

lspsaga's winbar breadcrumb descends into every document symbol containing the
cursor line, which in Markdown means the entire heading hierarchy and in Lua
usually nothing at all — a difference in what the server sends, not in how it
is drawn, and lspsaga has no depth option. The adapter re-cuts the winbar after
lspsaga has written it: path items plus a per-filetype number of symbols.

---

## Health check

```vim
:checkhealth lsp
```

Five sections: the environment, what `setup()` registered, the servers, the
ecosystem plugins that resolved, and a per-buffer diagnosis.
[docs/health.md](docs/health.md) says how to read them — and `:Lsp doctor` is
the deeper version of the last one.

---

## Contributing

Clone the repository and either symlink it or add it to your runtime path.
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) has the ground rules and the
project layout; [docs/architecture.md](docs/architecture.md) says which of the
three layers a change belongs in, and which way the arrows point.

Pull requests very welcome.

---

## Feedback

Your feedback is very welcome. Use the
[issue tracker](https://github.com/StefanBartl/lsp.nvim/issues) to report bugs,
suggest features or ask usage questions; anything more open-ended fits a
[discussion](https://github.com/StefanBartl/lsp.nvim/discussions).

If you find this plugin useful, a ⭐ on GitHub supports its development.

---

## License

MIT — see [LICENSE](LICENSE).
