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
  (`omnisharp` without `dotnet`, `luaformatter` on Windows -- Mason has no
  Windows build of it, …). The gate is the same for installing and for the
  report. Its `PATH` lookups are cached per `PATH` value, so a report on
  every `DirChanged` stays cheap; a binary added to a directory already on
  `PATH` is seen after a restart.
- Which filetypes a package serves is `project.FILETYPES`; a package without
  an entry there (one you switched on through `mason.overrides`) is not
  registered. The scan maps files by name only, so only filetypes a filename
  can map to are used: `asm-lsp` is reported for `.nasm` files, not for
  `.asm`/`.s` (those need the buffer's content). `asmfmt` and `jsonld-lsp`
  are deliberately not registered (`project.UNSCANNED`): no filename maps to
  their filetypes.
- Without Mason the table is empty, rather than a "could not be checked" line
  per package; `:checkhealth lsp` says Mason is not loadable.
- An older lib.nvim without `lib.nvim.deps.project` is no error: the step does
  nothing and `:checkhealth lsp` (section *Project tools*) says to update.
  After `:Lazy reload lib.nvim` the registration is gone and a second
  `setup()` is refused: the health check says to restart Neovim.
