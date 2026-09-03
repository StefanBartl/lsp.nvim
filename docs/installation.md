# Installation

Requires Neovim 0.11+ and [lib.nvim](https://github.com/StefanBartl/lib.nvim),
which is a **hard** dependency: `:Lsp` is built on its user-command composer and
does not register without it.

```lua
-- lazy.nvim
{
  "StefanBartl/lsp.nvim",
  import = "lsp.pack",
  dependencies = { "StefanBartl/lib.nvim" },
  event = { "BufReadPre", "BufNewFile" },
  opts = {},
}
```

```lua
-- packer.nvim / pckr.nvim
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

Only lazy.nvim understands `import = "lsp.pack"`. Under the other managers you
install the third-party plugins yourself; lsp.nvim wires up whichever of them
are present and reports the rest in `:checkhealth lsp`.

The full option surface is `:h lsp.nvim-config`, with
[configuration.md](configuration.md) for the reasoning behind its shape.

## With or without the pack

`import = "lsp.pack"` additionally installs and configures conform, lazydev,
workspace-diagnostics, trouble, lspsaga, lensline and inc-rename. Drop it and
you get the plugin alone: it wires up whichever of those happen to be installed
and reports the rest in `:checkhealth lsp`.

Which of them get installed is a **separate channel** from `opts`, and has to
be — lazy evaluates `import` while it is still collecting specs, long before
any `setup(opts)` exists to read:

```lua
-- before require("lazy").setup()
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

`vim.g` decides **whether**, `opts` decides **how** — with one deliberate
exception. `completion_accept` is a *how* question living in the *whether*
channel, because the binding is part of blink's plugin spec and lazy resolves
that long before `setup(opts)` exists to be read. It picks blink's `enter`
preset (`<CR>`, the default) or its `default` one (`<C-y>`), and the difference
is more than the key: `enter` binds `accept`, so Enter takes what is actually
selected and still inserts a newline when nothing is, while `default` binds
`select_and_accept`. It has no effect under nvim-cmp, where this pack
contributes an `opts` fragment to a config's own cmp spec rather than owning
the keymap.

## Two things that will bite you

**The module root is `lsp`.** That is deliberate — every existing
`require("lsp.…")` in a config keeps resolving after the code moves here — but
it means a config with its own `lua/lsp/**` **shadows this plugin completely**.
Neovim's own `lua/` directory wins on the runtimepath, so `require("lsp")` never
reaches the plugin and nothing about it looks broken; it simply is not the code
running. The two are meant to swap, not to coexist. If you are migrating, rename
the old directory rather than deleting it, switch over, verify, and only then
throw it away — you cannot test the switch while both exist.

**setup() ordering matters if you drive it yourself.** Capabilities have to be
applied globally before the first client attaches. With `opts = {}` lazy handles
it. If your config calls `require("lsp").setup()` at a specific point instead,
keep it there and give the plugin `lazy = false` with no `opts`/`config` block —
an `opts` block hands that ordering to the plugin manager.

## Verifying

```vim
:checkhealth lsp
:Lsp status
```

`:Lsp status` reports what `setup()` registered and every warning it worked
around; `:checkhealth lsp` adds the environment, the servers, and the ecosystem.
See [health.md](health.md).
