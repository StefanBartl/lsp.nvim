# Requirements

## Required

| | |
| --- | --- |
| Neovim | **0.11+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | the `:Lsp` command is built on its user-command composer and does not register without it |

## Optional

Each detected at runtime and degrading to nothing when absent. The pack installs
and configures most of them for you; mason.nvim, nvzone/menu and ui.nvim it does
not, so those are bring-your-own either way:

| | |
| --- | --- |
| [conform.nvim](https://github.com/stevearc/conform.nvim) | The formatter front end; without it formatting falls back to the LSP |
| [trouble.nvim](https://github.com/folke/trouble.nvim) | The diagnostics list |
| [lazydev.nvim](https://github.com/folke/lazydev.nvim) | Neovim-aware `lua_ls` completion |
| [workspace-diagnostics.nvim](https://github.com/artemave/workspace-diagnostics.nvim) | Diagnostics beyond the open buffers |
| [fzf-lua](https://github.com/ibhagwan/fzf-lua) | The pickers, the finder, and the diff preview in `lsa`'s code-action list; without it `lsa` is the native list |
| [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) | Hunk actions in the code-action list, with `code_actions.gitsigns` |
| [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) | The file icon in the winbar breadcrumb; without it a generic file glyph |
| [lensline.nvim](https://github.com/oribarilan/lensline.nvim) | Code lenses |
| [inc-rename.nvim](https://github.com/smjonas/inc-rename.nvim) | Live-preview rename |
| [mason.nvim](https://github.com/mason-org/mason.nvim) | Server and tool installation |
| A completion engine | nvim-cmp or [blink.cmp](https://github.com/saghen/blink.cmp), both wired if present |
| [nvzone/menu](https://github.com/nvzone/menu) | A host for the context-menu entries — see [FEATURES/INTEGRATIONS.md](FEATURES/INTEGRATIONS.md) |
| [ui.nvim](https://github.com/StefanBartl/ui.nvim) | Backs `:Lsp doctor` (`ui.kit`, degrades to a warning if missing), the root-scope and workspace-folder pickers, `:Lsp info`'s viewer, `ts_type_lookup`'s viewer, and astro's scaffold prompts (`ui.kit.select`/`ui.kit.input`/`ui.kit.viewer`) — those specific commands need it if actually invoked, the rest of the plugin does not |

`:checkhealth lsp` reports which of them resolved. See [installation.md](installation.md)
for how `import = "lsp.pack"` installs and configures most of the optional
list in one step.
