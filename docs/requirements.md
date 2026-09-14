# Requirements

## Required

| | |
| --- | --- |
| Neovim | **0.11+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | the `:Lsp` command is built on its user-command composer and does not register without it |

## Optional

Each detected at runtime and degrading to nothing when absent — the pack
installs and configures them for you, or bring your own:

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
| [nvzone/menu](https://github.com/nvzone/menu) | A host for the context-menu entries — see [FEATURES/INTEGRATIONS.md](FEATURES/INTEGRATIONS.md) |
| [ui.nvim](https://github.com/StefanBartl/ui.nvim) | Backs `:Lsp doctor` (`ui.kit`, degrades to a warning if missing), the root-scope and workspace-folder pickers, `:Lsp info`'s viewer, `ts_type_lookup`'s viewer, and astro's scaffold prompts (`ui.kit.select`/`ui.kit.input`/`ui.kit.viewer`) — those specific commands need it if actually invoked, the rest of the plugin does not |

`:checkhealth lsp` reports which of them resolved. See [installation.md](installation.md)
for how `import = "lsp.pack"` installs and configures most of the optional
list in one step.
