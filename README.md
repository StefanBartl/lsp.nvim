> **Alpha stage — active development.** This repository is in its development phase — breaking changes are to be expected at any time. Pin a commit or tag if you depend on it.

# lsp.nvim

```
    __
   / /________  ____ _   __(_)___ ___
  / / ___/ __ \/ __ \ | / / / __ `__ \
 / (__  ) /_/ / /_/ / |/ / / / / / / /
/_/____/ .___/\__,_/|___/_/_/ /_/ /_/
      /_/   one roof for the whole LSP setup
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.11%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-alpha-red)
[![CI](https://github.com/StefanBartl/lsp.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/lsp.nvim/actions/workflows/ci.yml)

> Pairs with [dap.nvim](https://github.com/StefanBartl/dap.nvim): the same
> architecture applied to the other protocol. LSP tells you what the code
> means, DAP tells you what it does — one umbrella each, so neither ends up
> scattered across a config.

> **Status: alpha.** The core is here: servers, capabilities, attach handling,
> formatter, diagnostics, the per-language and per-server modules, the extra
> tools and `:LspDoctor` all live in this plugin now.
> All five migration phases are through, including the keymap consolidation
> and the integration and pack layers.

`lsp.nvim` is the umbrella for everything LSP-related in a Neovim config: the
server registry, attach handling, capabilities, the formatter and
workspace-diagnostics toggles and `:LspDoctor` — plus the LSP-adjacent
third-party plugins (`trouble.nvim`, `conform.nvim`, `lazydev.nvim`,
`mason.nvim`, the completion engine) and every LSP and diagnostics keymap that
would otherwise be spread across five files.

A config's `lua/lsp/**` is not a pile of settings, it is a stateful subsystem —
a registry, an attach handler, a capabilities merge, runtime toggles — and the
part usually left behind when one extracts it is the ecosystem around it.
Extracting only the own code leaves `trouble.nvim` configured in one file,
`conform.nvim` in two contradicting ones, and `]q` bound twice by modules that
do not know about each other. This one takes the ecosystem with it, in three
layers — core, integrations, pack — with the arrows pointing one way only.
[architecture.md](docs/architecture.md) has the argument.

---

## Table of contents

- [Quickstart](#quickstart)
- [What it does](#what-it-does)
- [Documentation](#documentation)
- [License](#license)

---

## Quickstart

Requires Neovim **0.11+** and [lib.nvim](https://github.com/StefanBartl/lib.nvim)
as a hard dependency — the `:Lsp` command is built on its user-command composer
and does not register without it.

```lua
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
be installed and reports the rest in `:checkhealth lsp`. *Which* of them get
installed is a separate channel from `opts` (`vim.g.lsp_nvim.pack`, set before
`require("lazy").setup()`) — [installation.md](docs/installation.md) explains
why it has to be, and covers packer/pckr and vim-plug.

Then one verb, with `<Tab>` completion over subcommands and arguments:

```
:Lsp status     -- what setup() registered, and every warning it worked around
:Lsp doctor     -- why the server for this buffer is not running
:Lsp servers    -- what is set up, and which clients are attached here
```

`:Lsp` covers status, the server lifecycle, formatting, diagnostics, inlay
hints, the code-action indicator, roots and workspace folders, auto-restart and
the LSP log. The full route table, the ~25 flat legacy aliases and every keymap
are in [BINDINGS.md](docs/BINDINGS.md); [commands.md](docs/commands.md) is the
shape of it.

Verify your setup any time with:

```
:checkhealth lsp
```

> The module root is `lsp`, chosen so that existing `require("lsp.…")` paths in
> a config keep resolving after the code moves here. While a config still has
> its own `lua/lsp/**`, that directory wins on the runtimepath and shadows this
> plugin — the two are meant to swap, not to coexist.

## What it does

Each of these is a page in [docs/FEATURES/](docs/FEATURES/README.md), with the
reasoning behind it:

- **Servers** — the registry resolves configured names to modules, merges
  capabilities, owns attach, and brings a crashed server back with a bounded
  backoff.
- **Configuration in four layers** — defaults, a `preset` profile, your
  `setup()` options, and a per-project `.nvim-lsp.json`. Every warning names
  the layer the bad value came from.
- **Diagnostics** — into the quickfix or location list, with a leading-edge
  throttle on `publishDiagnostics`, and a workspace-wide toggle that refuses
  above its size gate rather than freezing the editor.
- **Formatter** — conform-first with an LSP fallback, and a format-on-save
  toggle this plugin owns rather than conform.
- **In-buffer indicators** — inlay hints and a code-action indicator, each
  global plus per-filetype, and both filtered so they carry information.
- **Roots and workspace folders** — a scope switch for the servers that resolve
  a root themselves, and LSP's own multi-root mechanism for the rest.
- **`:LspDoctor`** — six per-buffer reports. Five observe; `probe` provokes,
  which is the only way to tell a clean file from a dead pipeline.
- **Tools and integrations** — ESLint/Prettier, signature help, type lookup,
  deprecation help, one picker backend, a context menu built from the resolved
  keymap catalogue.

Everything the plugin binds is data: `lua/lsp/config/KEYMAPS.lua` is the
catalogue, `keymaps.map` overrides any entry by name without touching the
plugin, and `docs/BINDINGS.md` is generated from that same table, so the two
cannot drift.

## Documentation

Start with the [documentation index](docs/README.md) — it lists every page and
says what each one answers.

- [Documentation index](docs/README.md) — the full map of what is written down.
- [Features](docs/FEATURES/README.md) — what the plugin does, one page per area, with the reasoning.
- [Installation](docs/installation.md) — the pack, the two channels, and the two things that will bite you.
- [Configuration](docs/configuration.md) — why the options are shaped this way; the field list is `:h lsp.nvim-config`.
- [Command reference](docs/commands.md) — the shape of `:Lsp`, and where to start when something is wrong.
- [Workflow](docs/WORKFLOW.md) — how the pieces combine day to day, and which route answers which question.
- [Bindings cheatsheet](docs/BINDINGS.md) — every keymap, command and autocommand, generated from the catalogue.
- [Architecture](docs/architecture.md) — the three layers, and which way the arrows point.
- [Health](docs/health.md) — reading `:checkhealth lsp`.

`:h lsp.nvim` has the same material as a vimdoc.

## License

MIT — see [LICENSE](LICENSE).
