# config.mason.ensure_install

Ensure-install facade around mason.nvim (and its registry) for LSPs, DAP
adapters, linters and formatters. Exposes granular entry points
(`enable_lsp`, `enable_dap`, `enable_linters`, `enable_formatters`) plus a
high-level `enable(cfg)` orchestrator, de-duplicating installs across
categories to avoid concurrent installs of the same tool.
