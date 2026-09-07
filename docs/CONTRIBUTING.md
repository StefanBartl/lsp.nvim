# Contributing to lsp.nvim

Thank you for your interest! Bugs, ideas and questions are welcome in the
[issue tracker](https://github.com/StefanBartl/lsp.nvim/issues); pull requests
very welcome.

Read [`architecture.md`](architecture.md) before the first change. This plugin
is three layers with the arrows pointing one way, and most of what could go
wrong here is a require in the wrong direction rather than a bug in a function.

## Getting the repository into a session

Clone it and either symlink the checkout into your plugin directory or add it
to the runtime path directly:

```lua
vim.opt.rtp:prepend("/path/to/lsp.nvim")
require("lsp").setup({})
```

[lib.nvim](https://github.com/StefanBartl/lib.nvim) has to be on the runtime
path too — the `:Lsp` command is built on its user-command composer and does
not register without it.

One trap specific to this repository: **the module root is `lsp`**. A Neovim
config with its own `lua/lsp/**` wins on the runtimepath and shadows the
checkout completely. Nothing looks broken; it is simply not the code running.

## Ground rules

- Lua only, idiomatic Neovim Lua. 2-space indentation, `stylua.toml` decides
  the rest.
- **The core does not know the ecosystem exists.** `core/` never requires an
  adapter or a third-party plugin. It takes plain functions — a list of
  capability contributors, a pair of attach-hook lists — and `lsp/init.lua`,
  which belongs to neither layer, passes them in. `scripts/gen_map.lua`
  declares that as a layer rule, so it is checkable rather than intended.
- **An adapter must not load its plugin during `setup()`.** Under a lazy plugin
  manager a `require` *is* the load trigger, so an adapter reaching for its
  plugin while capabilities are being built pulls that plugin, its validation
  and its keymaps into every startup before the first paint. Read the plugin
  lazily, at the point of use.
- **Adapters are wrapped, not trusted.** Every adapter call goes through
  `pcall` — blast-radius control, not optionality. A failure is recorded in
  `status().warnings` and surfaced by `:checkhealth lsp`, never swallowed and
  never allowed to take the rest of the setup with it. The same holds in the
  core: one server module that throws costs that server, not the other eight.
- **Keymaps are data.** `lua/lsp/config/KEYMAPS.lua` is the catalogue; nothing
  binds a key outside it. `docs/BINDINGS.md` is generated from that table and
  CI checks it with `--check`, so editing the tables by hand is pointless.
- **Every warning names its layer.** Configuration resolves over defaults, a
  `preset`, `setup()` options and a per-project `.nvim-lsp.json`; a message
  about a bad value that does not say which layer it came from is not finished.
- Commands are registered through `lib.nvim.bindings.usercmd.composer`, with
  completion over every closed argument set.
- Descriptive commit messages.

## Project layout

| Path | Contains |
| --- | --- |
| `lua/lsp/core/` | The own code on `vim.lsp.*`: registry, attach, capabilities, handlers, diagnostics, inlay hints, lightbulb, supervisor, root scope and workspace folders |
| `lua/lsp/integrations/` | One adapter per third-party plugin — conform, trouble, lazydev, mason, lspsaga, lensline, inc-rename, noice, nvchad, picker, cmp/blink — plus `menu.lua` |
| `lua/lsp/pack/` | LazySpecs only, no logic: what gets installed when `import = "lsp.pack"` is used |
| `lua/lsp/servers/` | Per-server modules; the larger ones (`lua_ls/`, `marksman/`) carry their own `README.md` |
| `lua/lsp/languages/` | Per-language grouping over the server modules |
| `lua/lsp/lspdoctor/` | The six `:Lsp doctor` reports and their own health module |
| `lua/lsp/tools/` | ESLint/Prettier, signature help, type lookup, deprecation help |
| `lua/lsp/formatter/`, `diagnostics/`, `completion/` | The subsystems behind those routes |
| `lua/lsp/config/` | `DEFAULTS.lua`, `KEYMAPS.lua`, presets and validation |
| `lua/lsp/bindings/`, `usercmds/` | Keymap registration and the `:Lsp` route tree |
| `scripts/` | `gen_bindings.lua` (BINDINGS.md), `gen_map.lua` (module map and the layer rule) |
| `doc/`, `docs/` | The vimdoc, and everything the README links to |
| `TESTS/` | `lsp/` plenary specs, plus `smoke.lua` |

## Adding a server

1. Add the module under `lua/lsp/servers/`. A single file is fine; give it a
   directory with a `README.md` once it carries reasoning worth writing down.
2. Register it through the registry rather than calling `vim.lsp` directly, and
   let it throw if it must — the registry contains the damage.
3. Group it in `lua/lsp/languages/` if it belongs to a language set already
   there.
4. If it needs capabilities, contribute them as a function; do not require a
   completion engine from the server module.
5. Add a spec under `TESTS/lsp/`.
6. Document it in the matching page under [`FEATURES/`](FEATURES/README.md).

## Adding an integration

1. One adapter file under `lua/lsp/integrations/`, named after the plugin.
2. Do not require the plugin at `setup()` time — see the ground rules.
3. Declare what it needs via `requires` so keymaps and menu entries can skip it
   when it is absent.
4. If it should be installed by the pack, add the LazySpec under
   `lua/lsp/pack/` — that is a separate decision from wiring it up, and a
   separate file.
5. Report it in `lua/lsp/health.lua` under the ecosystem section.
6. Write it up in [`FEATURES/INTEGRATIONS.md`](FEATURES/INTEGRATIONS.md) if it
   adds behaviour rather than only wiring a plugin up.

## Adding or changing a keymap

Edit `lua/lsp/config/KEYMAPS.lua` and regenerate:

```
nvim --headless -l scripts/gen_bindings.lua
```

CI runs the same script with `--check`. Never edit the generated tables in
`docs/BINDINGS.md`.

## Tests

Two suites, deliberately separate. The plenary specs stub their way around the
ecosystem so the core is exercised without a plugin manager; the smoke test
runs the real `setup()` against the real modules, which is exactly what the
stubs cannot check.

```
nvim --headless --noplugin -u TESTS/minimal_init.lua \
  -c "PlenaryBustedDirectory TESTS/lsp { minimal_init = 'TESTS/minimal_init.lua', sequential = true }"
```

```
nvim --headless -u NONE -c "set rtp^=." -c "set rtp^=/path/to/lib.nvim" \
  -c "luafile TESTS/smoke.lua" -c "qa!"
```

[GitHub Actions](../.github/workflows/ci.yml) runs stylua, luacheck, the
bindings check, both suites, and then force-pushes `ci-verified` to the tested
commit so dependent repositories can pin a known-good state.

## Workflow

1. Fork the repository.
2. Branch as `feature/<name>`.
3. Make the change, add a spec, regenerate BINDINGS.md if the catalogue moved,
   update the affected pages under `docs/`.
4. Open a PR with a clear description of what changed and why.
