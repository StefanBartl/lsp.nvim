# Architecture

Three layers. The interesting part is not what is in them but which way the
arrows point.

```
pack/           WHAT gets installed  — LazySpecs, no logic
integrations/   HOW third-party plugins are wired — one adapter each
core/           the own code on vim.lsp.* — registry, attach, capabilities, …
```

## The core does not know the ecosystem exists

`core/attach.lua` does not require lazydev. `core/capabilities.lua` does not
require nvim-cmp. They take **plain functions**: an ordered list of capability
contributors, a pair of attach-hook lists.

The adapters hand those to `lsp/init.lua`, which belongs to neither layer, and
it passes them in. So the dependency runs integrations → init → core, never core
→ integrations, and `scripts/gen_map.lua` declares that as a layer rule so it
stays checkable rather than intended.

Two things fall out of it:

- The core is testable without a plugin manager. The capability chain is
  exercised with three-line stub functions, not by installing a completion
  engine.
- Swapping a completion engine is one adapter file. `blink.cmp` support has
  existed in `integrations/blink.lua` the whole time; what was missing was a way
  to *install* it, which is the pack's job, not the core's.

## Adapters are wrapped, not trusted

Every adapter call goes through `pcall`. That is blast-radius control, not
optionality: an adapter wraps someone else's plugin, so it is the part most
likely to break through no fault of this one. A failure is recorded in
`status().warnings` and surfaced by `:checkhealth lsp` — never swallowed, and
never allowed to take the rest of the setup with it.

The same rule applies inside the core: one server module that throws costs that
server, not the other seven.

## The pack holds specs, not logic

Every `config` in `pack/` is a single call into the matching adapter. What a
plugin is configured *to* never sits in the layer that decides *whether* it is
installed.

`import` names a **directory**: lazy requires every module under `lua/lsp/pack/`
and treats each result as a spec list. Conditional imports therefore gate
nothing — selection is per-spec `enabled`, read from `lsp.config.pack`. That is
also why the helper for it lives in `config/`, not in `pack/`: a module sitting
there would be read as a malformed spec.

## Everything the plugin claims is registered in one place

`bindings/` — keymaps, the `:Lsp` verb, autocommands, which-key labels — with
`bindings/init.lua` as the single entry point. "What does this plugin take over
when it loads" has one answer to read, and the keymaps in it are data
(`config/KEYMAPS.lua`), not code.

## Layout

```
lua/lsp/
  init.lua            setup() and status(); composes the layers
  health.lua          :checkhealth lsp
  @types/             shared annotations
  config/             DEFAULTS, the keymap catalogue, pack selection, merge
  bindings/           keymaps, :Lsp, autocmds, which-key, actions
  core/               registry, attach, capabilities, handlers, diagnostics
  servers/            one module per language server
  languages/          filetype-specific setup, applied before the servers
  formatter/          on-save toggle, conform strategy, view preservation
  diagnostics/        commands, quickfix/loclist, navigation
  lspdoctor/          :LspDoctor, five modes
  tools/              eslint/prettier, signature help, type lookup, deprecations
  usercmds/           the flat command family (aliases onto :Lsp)
  completion/         nvim-cmp source for the config's own plugin names
  integrations/       one adapter per third-party plugin, plus the registry
  pack/               LazySpec export
```

The full design, and the migration that produced it, is in
[ROADMAP.md](ROADMAP.md).
