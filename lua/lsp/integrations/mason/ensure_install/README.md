# config.mason.ensure_install

Ensure-install facade around mason.nvim (and its registry) for LSPs, DAP
adapters, linters and formatters. Exposes granular entry points
(`enable_lsp`, `enable_dap`, `enable_linters`, `enable_formatters`) plus a
high-level `enable(cfg)` orchestrator, de-duplicating installs across
categories to avoid concurrent installs of the same tool.

## `:Lib deps project`

`setup()` also registers these lists with lib.nvim's project scan
(`project.lua`, via `lib.nvim.deps.project.register_tools("lsp.nvim", …)`),
so `:Lib deps project` lists the Mason packages that the filetypes in the
current root want and that are not installed. That installs nothing and does
not need `mason.ensure_install = true`; `:Lib deps project install` asks
before it installs anything.

- The packages are `ensure_install.wanted(mason.overrides)`: the four default
  lists, your overrides on top, minus what the dependency gate refuses here
  (`omnisharp` without `dotnet`, …).
- Which filetypes a package serves is `project.FILETYPES`; a package without
  an entry there (one you switched on through `mason.overrides`) is not
  registered.
- Without Mason the table is empty, rather than a "could not be checked" line
  per package.
- An older lib.nvim without `lib.nvim.deps.project` is no error: the step does
  nothing and `:checkhealth lsp` (section *Project tools*) says to update.
