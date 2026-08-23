# Tests

Two layers, run by CI and both runnable locally.

| What | File(s) | Needs |
| ---- | ------- | ----- |
| Spec suite | `tests/lsp/*_spec.lua` | plenary.nvim, lib.nvim |
| Smoke test | `tests/smoke.lua` | lib.nvim |

## Run

The suite resolves plenary.nvim and lib.nvim from environment variables, so the
same command works locally and in CI:

```sh
PLENARY_PATH=~/.local/share/nvim/lazy/plenary.nvim \
LIB_NVIM_PATH=../lib.nvim \
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/lsp { minimal_init = 'tests/minimal_init.lua', sequential = true }"
```

```sh
nvim --headless -u NONE -c "set rtp^=." -c "set rtp^=../lib.nvim" \
  -c "luafile tests/smoke.lua" -c "qa!"
```

## Lint

CI runs `stylua --check` and `luacheck` before the suite, and luacheck is worth
having locally: it is scope-aware, so it catches a `local function` used above
its own declaration — which reads fine, passes review, and is `nil` at runtime.
It found exactly that in `bindings/actions.lua`, in a branch the specs could
not reach because trouble.nvim is not installed in the test environment.

```sh
luarocks install luacheck
export LUA_PATH="$(luarocks path --lr-path);;" LUA_CPATH="$(luarocks path --lr-cpath);;"
lua "$(luarocks path --lr-bin)/luacheck" lua scripts tests
```

`rtp^=` and `rtp:prepend` are not cosmetic: `-u NONE` still leaves the user's
config directory on the runtimepath, and while a config carries its own
`lua/lsp/**` an appended entry loses — the tests would silently exercise that
instead of this plugin.

## What is covered

| Spec | Covers |
| ---- | ------ |
| `config_spec.lua` | Merge and normalization: every way an option can be malformed, and that it degrades rather than raising or being passed through. |
| `keymaps_spec.lua` | Catalogue invariants (no entry claimed twice in one mode, presets name real entries, `minimal` is a subset) and the binder's override/disable/rebind mechanics. |
| `capabilities_spec.lua` | The contributor chain: order, warning propagation, and that one throwing contributor costs its contribution and nothing else. |
| `integrations_spec.lua` | The adapter contract, contribution order, and that a broken adapter is recorded rather than propagated. |
| `pack_spec.lua` | The `vim.g.lsp_nvim.pack` gating, and that the two completion engines exclude each other. |
| `registry_spec.lua` | Server-name resolution, the `webdev.*` fallback, and what happens to a name whose module is missing or throws. |
| `usrcmds_spec.lua` | The `:Lsp` route table: every route reachable, the legacy aliases mapping onto real routes, and the argument completion. |
| `smoke.lua` | End-to-end: every module loads, `setup()` runs the whole bootstrap, servers and commands are registered. |

The specs run against stubs, not against real servers or plugins: a real
`lsp.servers.*` module calls `vim.lsp.config()` and would leave the test
process configured, and a real adapter's behaviour depends on whether its
plugin happens to be installed. What is worth pinning down is the resolution
and the failure handling around them.

## Why these areas

They are where the bugs actually were. Writing the suite found four more:

- `config.setup()` cleared its warning list *after* recording the "expected a
  table" warning, so the one case where the caller most needs telling was the
  one case that stayed silent.
- `core/registry.lua` called `("… '%s' …"):format()` with no argument inside
  another `format()`. Nothing there is `pcall`-wrapped, so a single configured
  server without a module would have aborted the whole setup — it never fired
  only because every configured name happened to resolve.
- Two more in `lspdoctor/health.lua`, found by running the check rather than
  reading it (see the roadmap's B12/B16).

All four look correct on the page.
