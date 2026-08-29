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
![Status](https://img.shields.io/badge/status-alpha-orange)

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

---

## Table of contents

- [Why an umbrella](#why-an-umbrella)
- [Installation](#installation)
- [Commands](#commands)
- [Configuration](#configuration)
- [Health](#health)
- [Architecture](#architecture)
- [Documentation](#documentation)
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

Which of them gets installed is a *separate* channel from `opts`, set before
`require("lazy").setup()`:

```lua
vim.g.lsp_nvim = {
  pack = {
    core = true,          -- conform, lazydev, workspace-diagnostics
    ui = true,            -- trouble, lspsaga, lensline, inc-rename
    completion = "blink", -- "cmp" | "blink" | false (default: blink)
    completion_accept = "cr", -- "cr" | "ctrl_y" (default: cr) -- blink only
    disable = { "lspsaga.nvim" },
  },
}
```

It has to be separate: lazy evaluates `import` while collecting specs, long
before `setup(opts)` exists to be read. `vim.g` decides *whether* a plugin is
installed, `opts` decides *how* everything is configured.

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

> The module root is `lsp`, chosen so that existing `require("lsp.…")` paths in
> a config keep resolving after the code moves here. While a config still has
> its own `lua/lsp/**`, that directory wins on the runtimepath and shadows this
> plugin — the two are meant to swap, not to coexist.

## Commands

One verb with subcommands and `<Tab>` completion. Full cheatsheet:
[docs/BINDINGS.md](docs/BINDINGS.md).

| Command | Effect |
| ------- | ------ |
| `:Lsp status` / `servers` / `info` / `health` | What is set up, what is attached, what is wrong |
| `:Lsp doctor [mode]` | Per-buffer diagnosis (`health`, `debug`, `quick`, `deep`, `all`) |
| `:Lsp start` / `stop` / `restart` `[server]` | Lifecycle for this buffer's clients |
| `:Lsp force-restart {server}` | Restart one server with a full cleanup first |
| `:Lsp recover` | Auto-recover servers that should be running here |
| `:Lsp format [action]` | Format once, or control format-on-save |
| `:Lsp diag {qf\|loc\|next\|prev} [qf\|loc]` | Diagnostics into a list, or move within one |
| `:Lsp workspace [action]` | Workspace-wide diagnostics on attach |
| `:Lsp hints [action] [filetype]` | Inlay hints: globally, or for one filetype |
| `:Lsp root [pick\|show]` | Root scope: cwd / git root / file path |
| `:Lsp log open` / `level {level}` | Open the LSP log, or set its level |

Every closed argument set completes with `<Tab>`, and `[server]` completes from
the live set rather than a list frozen at startup.

The ~25 flat commands the migration brought along (`:LspStatus`, `:LspFormat*`,
`:LspWorkspaceDiagnostics*`, `:Diag*`, …) are still registered as aliases onto
the same functions; `usrcmds.legacy_aliases = false` drops them. `:LspDoctor`
and `:LspMdHints` are not aliases and stay either way.

## Configuration

Every option has a default; `setup()` with no arguments is a complete setup.

```lua
require("lsp").setup({
  -- Servers to set up and enable. Each resolves to `lsp.servers.<name>`, with
  -- `lsp.servers.webdev.<name>` as a fallback for dotless names.
  servers = { "lua_ls", "gopls", "bashls", "marksman", "html", "ts_ls" },

  diagnostics = {
    update_in_insert = false,
    severity_sort = true,
    virtual_text = { spacing = 2, prefix = "●" },
    float = { border = "rounded", source = "if_many" },
    ui = "auto",                   -- "auto" | "native" | "trouble" -- ]d/[d's sink
    debounce_ms = 150,             -- publishDiagnostics throttle, leading-edge; 0 = off
  },                                -- the rest passed straight to vim.diagnostic.config()

  formatter = {
    on_save = false,               -- startup default; the runtime toggle owns it after
    timeout_ms = 1500,
  },

  inlay_hints = {
    enable = false,                -- global startup default; the runtime toggle owns it after
    filetypes = {},                -- per-filetype override; absent inherits, false overrides
  },

  attach = {
    use_workspace_diagnostics = true,
    use_lazydev = true,
  },

  mason = { ensure_install = false, overrides = {} },
  tools = {                        -- each extra tool has its own switch
    eslint_prettier = { enable = true, filetypes = { "javascript", "typescript" } },
    lsp_signature = { enable = true },
    ts_type_lookup = { enable = true },
    deprecated_help = { enable = true },
  },
  languages = { enable = true },   -- filetype setup under lsp/languages/**

  keymaps = {
    enable = true,        -- master switch for every key this plugin binds
    preset = "default",   -- "default" | "minimal" | "none"
    map = {},             -- per-action override: "<lhs>" replaces, false disables
  },
  usrcmds = { enable = true },   -- register the `:Lsp` verb
  which_key = { enable = true }, -- label bound prefixes as which-key groups
  menu = { enable = true },      -- <RightMouse> context menu mirroring the
                                  -- keymap catalogue (nvzone/menu, soft dependency)
})
```

The server list used to be a hardcoded `ACTIVE` table inside
`core/registry.lua`, where turning a server on or off meant editing the
plugin. An empty or malformed list falls back to the defaults rather than
leaving you with no language server at all.

Keymaps are data, not code: `lua/lsp/config/KEYMAPS.lua` holds the catalogue,
and `keymaps.map` overrides any entry by name without touching the plugin. The
`default` preset binds 42 entries, `minimal` the 26 with no native equivalent,
`none` nothing. `docs/BINDINGS.md` is generated from the same table, so the two
cannot drift.

```lua
keymaps = {
  map = {
    goto_definition = "gd",   -- rebind
    rename_leader = false,    -- drop
  },
},
rename = { provider = "auto" }, -- "auto" | "inc_rename" | "native"
```

An out-of-range value degrades to the documented default and shows up in
`:checkhealth lsp` rather than raising at startup.

## Health

```vim
:checkhealth lsp
```

Five sections: the environment, what `setup()` registered (including every
warning it had to work around), the servers, the ecosystem around the plugin,
and a pointer to `:LspDoctor` for per-buffer diagnosis.

The servers section runs along four numbers — installed (what Mason has on
disk, whatever `servers` says), configured, set up, attached — plus which of
the running clients serve the buffer you came from. The gap between any two of
them is usually the answer when a server "does not work", and the last two are
also the cost picture: an installed server that is attached to nothing costs
nothing. The section warns about exactly one thing, a server whose cost scales
with attached buffers (`ts_ls`, `pyright`, `jdtls`, `omnisharp`) held open
across many of them — never on a count alone.

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
  core/               -- registry, attach, capabilities, handlers, diagnostics, inlay hints
  servers/            -- one module per language server
  languages/          -- filetype-specific quality-of-life setup
  formatter/          -- on-save toggle, conform strategy, view preservation
  diagnostics/        -- commands, quickfix/loclist, navigation
  lspdoctor/          -- :LspDoctor, five modes
  tools/              -- eslint/prettier, signature help, type lookup, deprecations
  usercmds/           -- the migrated :Lsp* command family
  completion/         -- nvim-cmp source for the config's own plugin names
  integrations/        -- one adapter per third-party plugin, plus the registry
  pack/                -- LazySpec export: what `import = "lsp.pack"` installs
```

The adapters own every third-party `require`. The core does not reach into
them: they hand capability contributors and attach hooks to `lsp/init.lua`,
which passes them into the core as plain functions — so `core/attach.lua` does
not know lazydev or NvChad exist, and `core/capabilities.lua` does not know
which completion engine is installed. `:checkhealth lsp` lists them straight
from the registry rather than a second, hand-kept list.

`pack/` holds specifications and nothing else. Each spec's `config` is a single
call into the matching adapter, so what a plugin is configured *to* never sits
in the layer that decides *whether* it is installed.

## Documentation

| Page | Covers |
| ---- | ------ |
| [installation.md](docs/installation.md) | Managers, the pack, and the two things that will bite you |
| [configuration.md](docs/configuration.md) | Why the options are shaped this way; the field list is `:h lsp.nvim-config` |
| [FEATURES.md](docs/FEATURES.md) | What the plugin does, by area |
| [commands.md](docs/commands.md) | The shape of `:Lsp`, and where to start when something is wrong |
| [WORKFLOW.md](docs/WORKFLOW.md) | How the pieces combine day to day, and which route answers which question |
| [BINDINGS.md](docs/BINDINGS.md) | Every keymap and command, generated from the catalogue |
| [architecture.md](docs/architecture.md) | The three layers, and which way the arrows point |
| [health.md](docs/health.md) | Reading `:checkhealth lsp` |

`:h lsp.nvim` has the same material as a vimdoc.
