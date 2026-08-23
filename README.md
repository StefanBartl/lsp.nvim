```
    __
   / /________  ____ _   __(_)___ ___
  / / ___/ __ \/ __ \ | / / / __ `__ \
 / (__  ) /_/ / /_/ / |/ / / / / / / /
/_/____/ .___/\__,_/|___/_/_/ /_/ /_/
      /_/   one roof for the whole LSP setup
```

[![CI](https://github.com/StefanBartl/lsp.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/lsp.nvim/actions/workflows/ci.yml)
![Neovim](https://img.shields.io/badge/Neovim-0.11+-57A143?logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/Made%20with-Lua-2C2D72?logo=lua&logoColor=white)
![Status](https://img.shields.io/badge/status-scaffold-orange)

> Pairs with [dap.nvim](https://github.com/StefanBartl/dap.nvim): the same
> architecture applied to the other protocol. LSP tells you what the code
> means, DAP tells you what it does — one umbrella each, so neither ends up
> scattered across a config.

> **Status: scaffold.** This plugin configures no language servers yet. What
> works today is the part that needs nothing from the migration: configuration,
> the `:Lsp` command, the keymap mechanism and `:checkhealth lsp`. The full
> design and the migration plan live in [docs/ROADMAP.md](docs/ROADMAP.md).

`lsp.nvim` is the umbrella for everything LSP-related in a Neovim config: the
server registry, attach handling, capabilities, the formatter and
workspace-diagnostics toggles and `:LspDoctor` — plus the LSP-adjacent
third-party plugins (`trouble.nvim`, `conform.nvim`, `lazydev.nvim`,
`mason.nvim`, the completion engine) and every LSP and diagnostics keymap that
would otherwise be spread across five files.

---

## Table of contents

- [Why an umbrella](#why-an-umbrella)
- [Installation](#installation)
- [Commands](#commands)
- [Configuration](#configuration)
- [Health](#health)
- [Architecture](#architecture)
- [Roadmap](#roadmap)

---

## Why an umbrella

A config's `lua/lsp/**` is not a pile of settings, it is a stateful subsystem:
a registry of servers, an attach handler, a capabilities merge, runtime
toggles. That makes it the same kind of thing as a debugger integration, and
the same kind of thing that belongs in its own repository.

The part usually left behind is the ecosystem around it. Extracting only the
own code leaves `trouble.nvim` configured in one file, `conform.nvim` in two
contradicting ones, and `]q` bound twice by modules that do not know about each
other. `lsp.nvim` takes the ecosystem with it, in three layers:

| Layer | Contents |
| ----- | -------- |
| Core | Own code on `vim.lsp.*`: registry, attach, servers, formatter, diagnostics, doctor |
| Integrations | One adapter per third-party plugin: how it is configured and wired |
| Pack | A LazySpec export, so one entry in your plugin list installs the whole set |

The core never reaches into the integrations. That is not a style preference —
it is what keeps the core testable without a plugin manager and makes swapping
a completion engine a one-file change. `scripts/gen_map.lua` declares it as a
layer rule, so it stays checkable rather than aspirational.

## Installation

Requires Neovim 0.11+ and [lib.nvim](https://github.com/StefanBartl/lib.nvim)
as a hard dependency — the `:Lsp` command is built on its user-command composer
and does not register without it.

```lua
-- lazy.nvim
{
  "StefanBartl/lsp.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  event = { "BufReadPre", "BufNewFile" },
  opts = {},
}
```

```lua
-- packer.nvim
use({
  "StefanBartl/lsp.nvim",
  requires = { "StefanBartl/lib.nvim" },
  config = function()
    require("lsp").setup()
  end,
})
```

```vim
" vim-plug
Plug 'StefanBartl/lib.nvim'
Plug 'StefanBartl/lsp.nvim'
```

Once the pack layer exists, `import = "lsp.pack"` will additionally install and
configure the third-party plugins; see [docs/ROADMAP.md](docs/ROADMAP.md) §6.

> The module root is `lsp`, chosen so that existing `require("lsp.…")` paths in
> a config keep resolving after the code moves here. While a config still has
> its own `lua/lsp/**`, that directory wins on the runtimepath and shadows this
> plugin — the two are meant to swap, not to coexist.

## Commands

One verb with subcommands and `<Tab>` completion. Full cheatsheet:
[docs/BINDINGS.md](docs/BINDINGS.md).

| Command | Effect |
| ------- | ------ |
| `:Lsp status` | What the plugin has set up, and what it has not |
| `:Lsp servers` | The LSP clients currently attached, with root and buffer count |
| `:Lsp health` | Run `:checkhealth lsp` |
| `:Lsp log open` | Open Neovim's LSP log file in a split |
| `:Lsp log level {level}` | Set the LSP log level (`trace`…`error`, `off`) |

## Configuration

Every option has a default; `setup()` with no arguments is a complete setup.

```lua
require("lsp").setup({
  keymaps = {
    enable = true,        -- master switch for every key this plugin binds
    preset = "default",   -- "default" | "minimal" | "none"
    map = {},             -- per-action override: "<lhs>" replaces, false disables
  },
  usrcmds = { enable = true },   -- register the `:Lsp` verb
  which_key = { enable = true }, -- label bound prefixes as which-key groups
})
```

Keymaps are data, not code: `lua/lsp/config/KEYMAPS.lua` holds the catalogue,
and `keymaps.map` overrides any entry by name without touching the plugin. The
catalogue is empty for now — consolidating the LSP and diagnostics keys is
migration phase 3 — so the mechanism is live while no key is claimed.

An out-of-range value degrades to the documented default and shows up in
`:checkhealth lsp` rather than raising at startup.

## Health

```vim
:checkhealth lsp
```

Reports the Neovim version and `lib.nvim`, what `setup()` actually registered,
the LSP clients Neovim currently has attached, and which of the planned
third-party integrations are installed. The last group is informational: none
of them is wired yet, so a missing one is not a fault of this plugin.

## Architecture

```
lua/lsp/
  init.lua            -- setup() and status(); orchestration only
  health.lua          -- :checkhealth lsp
  @types/init.lua     -- shared annotations
  config/
    DEFAULTS.lua      -- the single source of default values
    KEYMAPS.lua       -- the declarative keymap catalogue
    init.lua          -- merge, normalize, hand out via get()
  bindings/
    init.lua          -- one entry point for everything the plugin claims
    keymaps.lua       -- catalogue -> vim.keymap.set, with user overrides
    usrcmds.lua       -- the `:Lsp` verb
    autocmds.lua      -- augroup owner (no handlers yet)
    which_key.lua     -- group labels, soft dependency
```

`core/`, `integrations/`, `servers/`, `languages/`, `formatter/` and `pack/`
join this tree during the migration; the roadmap describes each.

## Roadmap

[docs/ROADMAP.md](docs/ROADMAP.md) — the full concept: the current state of the
subsystem being extracted, the three-layer architecture, the pack system, the
binding consolidation, a six-phase migration plan, and the bugs found while
surveying the code that is to be moved. Written in German.
