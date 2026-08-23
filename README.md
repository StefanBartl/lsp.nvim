# lsp.nvim

> **Status: Konzeptphase — dieses Repository enthält noch keinen Code.**

Planned umbrella plugin for the whole LSP ecosystem of my Neovim config:
the `lua/lsp/**` subsystem (server registry, attach handling, capabilities,
formatter toggle, workspace-diagnostics toggle, `:LspDoctor`) plus the
LSP-adjacent third-party plugins (`trouble.nvim`, `conform.nvim`,
`lazydev.nvim`, `mason.nvim`, the completion engine, ...) and every
LSP/diagnostics keymap that is scattered across the config today.

Sibling subsystem, same architecture: [dap.nvim](https://github.com/StefanBartl/dap.nvim).
Hard dependency: [lib.nvim](https://github.com/StefanBartl/lib.nvim).

The full concept — architecture, the three layers (core / integrations /
pack), the LazySpec export, the migration plan and the known bugs to fix
along the way — is in [docs/ROADMAP.md](docs/ROADMAP.md) (German).

This README is a placeholder; it does not yet meet the README requirements
laid out in §12 of the roadmap.
