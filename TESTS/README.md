# Tests

Three layers, run by CI and all runnable locally.

| What | File(s) | Needs |
| ---- | ------- | ----- |
| Spec suite | `TESTS/lsp/*_spec.lua` | plenary.nvim, lib.nvim, ui.nvim (`pack_spec.lua`) |
| Live probe gate | `TESTS/lsp/probe_live_spec.lua` | one of `lua-language-server`, `typescript-language-server`, `gopls` (+`go`) |
| Smoke test | `TESTS/smoke.lua` | lib.nvim, ui.nvim (`step("lspdoctor", ...)` runs unconditionally) |

## Run

The suite resolves plenary.nvim, lib.nvim and ui.nvim from environment
variables, so the same command works locally and in CI:

```sh
PLENARY_PATH=~/.local/share/nvim/lazy/plenary.nvim \
LIB_NVIM_PATH=../lib.nvim \
UI_NVIM_PATH=../ui.nvim \
nvim --headless --noplugin -u TESTS/minimal_init.lua \
  -c "PlenaryBustedDirectory TESTS/lsp { minimal_init = 'TESTS/minimal_init.lua', sequential = true }"
```

```sh
nvim --headless -u NONE -c "set rtp^=." -c "set rtp^=../lib.nvim" -c "set rtp^=../ui.nvim" \
  -c "luafile TESTS/smoke.lua" -c "qa!"
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

## Temp directories: resolve before you compare

A case that builds a tree under `vim.fn.tempname()` and then compares a path
the plugin produced against that tempname has to resolve the directory first:

```lua
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")                                   -- realpath needs it to exist
dir = vim.fs.normalize((vim.uv or vim.loop).fs_realpath(dir) or dir)
```

Everything the plugin hands back is already in the spelling the operating
system reports: Neovim canonicalizes a path on the way into a buffer name, and
`uv.cwd()` resolves symlinks, so a root resolved from a buffer or found by
walking up from the working directory comes back resolved. `tempname()` does
not. On macOS `$TMPDIR` sits under the `/var` → `/private/var` symlink, which
makes those two spellings of one directory differ — `/private/var/folders/…`
against `/var/folders/…` — and on Windows `%TEMP%` can be the 8.3 short form
(`C:/Users/STEFAN~1/…`) for the same reason. Fifteen cases across six specs
failed on the macOS runner the first time CI ran there, all of them this and
none of them a defect in the plugin.

It is not only a false red: an assertion comparing the wrong spelling can also
pass for the wrong reason. `workspace_folders_spec.lua`'s "leaves out what is
already a workspace folder" hands a stub client a folder and then requires it
to be absent from the candidates — which it trivially is when the two can no
longer match at all, exclusion or no exclusion.

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
| `lightbulb_spec.lua` | The CodeActionKind allowlist the code-action indicator rests on, the per-filetype resolution, and the draw path against a stub client. |
| `symbols_spec.lua` | `core/symbols`: both response shapes normalized, the cursor-to-path lookup (a range ending at column 0, a one-line symbol, the header line's indentation), and the cache -- keyed to `changedtick`, joining an in-flight request, not dropping a waiter when a newer one supersedes it. |
| `winbar_spec.lua` | `core/winbar`: the parts and the per-filetype depth cap, the three-state resolution, and -- in a real window with a stub client -- that a `'winbar'` it did not write is never cleared, and that it does not draw on floats or special buffers. |
| `winbar_render_spec.lua` | `core/winbar/render` and `kinds`: escaping, the chip groups (defined, backgrounded, redefined after a colorscheme clear), and the result of `nvim_eval_statusline` rather than only the string. |
| `peek_spec.lua` | `core/peek` against real windows and real temp files: what an answer is flattened to, the float, the keys given back (including a buffer-local map they shadowed), unloading a buffer the peek loaded, stacking, and every way of taking a peek into a real window. |
| `implement_spec.lua` | `core/implement`: which symbols it asks about, that it sends nothing without a server that implements the method, the `max_requests` cap, and one round per `changedtick`. |
| `gitsigns_actions_spec.lua` | `core/gitsigns_actions`, with a **real** `vim.lsp.start` on the in-process server: the hunk-overlap rules, the kind the code-action indicator does not light on, and that the commands run. |
| `navigation_features_spec.lua` | The keymap entries, `lsa`'s picker choice, the quick fix, the finder's sources, type hierarchy's capability check, the `:Lsp winbar\|implement\|peek` routes, and the config that feeds them. |
| `supervisor_spec.lua` | The exit classifier: every way a deliberate stop, a quit and a startup failure can be mistaken for a crash, plus the backoff curve and the shared attempt counter. |
| `start_spec.lua` | That the expected-server list is derived from the registered `vim.lsp.config` entries rather than a hardcoded filetype table -- which server declares which filetype, and that a registered-but-not-enabled config is not expected. |
| `symbol_picker_spec.lua` | That `:TypeDefPick` sends its argument as fzf-lua's `lsp_query` (the server-side `workspace/symbol` query) and not as `query` (fzf's local filter over a full workspace dump), plus the `<cword>` fallback and the missing-fzf-lua path. |
| `recovery_spec.lua` | That servers are started through `supervisor.start` rather than `vim.lsp.enable`, and the two counter guards -- a name with no config spends no attempt, and `:Lsp recover` clears a counter the supervisor left exhausted. |
| `attach_spec.lua` | `core/attach.lua`'s `on_init`/`on_attach` pair: the buffer-validity and capabilities guards, that `workspace_diagnostics.enabled()` is read fresh on every attach rather than captured once, and that one throwing adapter hook costs only itself. |
| `filter_spec.lua` | The two pure diagnostic-list helpers under `core/handlers`: `filter`'s Lua-pattern matching and `dedup`'s position key, including the LSP `range.start` vs. `vim.diagnostic` `lnum`/`col` shapes it has to read interchangeably. |
| `mason_node_spec.lua` | `core/mason_node`'s npm `.bin/<name>.cmd` shim parser end to end against a real (redirected) `stdpath("data")`: the Windows-only gate, every way the parse can fail closed to `nil`, and the backslash-to-forward-slash normalization the resolved entry path depends on. |
| `rootresolvers_spec.lua` | `servers/lua_ls/rootresolver`'s `strict_root_from` algorithm against real temp directories: the `<leader>lsp` cwd/git/path scope switch, VCS-before-marker search order, and that the Neovim config directory wins regardless of scope — including when `stdpath("config")` is a **symlink** into a dotfiles repo, which needs a real symlink and skips loudly where one cannot be made (see below); plus `servers/marksman/rootresolver`'s own marker list and `tools/eslint_prettier/core/find_root`'s unnamed-buffer guard. |
| `autocmds_wiring_spec.lua` | `bindings/autocmds.lua`'s `LspAttach` handler: the `keymaps.enable` gate, that re-running `setup()` does not stack a second handler on the group, and that both catalogue entries known to collide with Neovim's `gr*` defaults get a rebind attempt with the firing event's own buffer. |
| `usercmds_wiring_spec.lua` | Three previously-uncovered `:Lsp*` command modules: `usercmds/formatter` (dispatch onto whichever formatter module is handed in, including the `LspFormatWhich` soft-dependency path), `usercmds/workspace_diagnostics` (the toggle commands over `core/workspace_diagnostics`), and `usercmds/mobile_diagnostics` (the environment probe's executable/env-var/platform branches). |
| `probe_live_spec.lua` | The diagnostics chain against a **real** server: start it, hand `:LspDoctor probe` a file with a syntax error, require an answer. The only case in the suite that is not stubbed -- see below. |
| `smoke.lua` | End-to-end: every module loads, `setup()` runs the whole bootstrap, servers and commands are registered. |

The specs run against stubs, not against real servers or plugins: a real
`lsp.servers.*` module calls `vim.lsp.config()` and would leave the test
process configured, and a real adapter's behaviour depends on whether its
plugin happens to be installed. What is worth pinning down is the resolution
and the failure handling around them.

### The one exception: `probe_live_spec.lua`

`:LspDoctor probe` is the only report that verifies the chain end to end rather
than querying a state, and stubbing it would test everything about it except
that. So this case runs it for real: it starts a language server in a temporary
directory, lets `probe` build its broken buffer, and requires diagnostics back.

It needs a server, and not every machine has one. The skip is therefore built
so it cannot be mistaken for a pass:

- it names every candidate it looked for and what was missing about each,
- it writes that to stderr as well as to plenary's `PENDING` line, because
  plenary still tallies a pending case under `Success`,
- and under `CI` it **fails** instead of skipping -- the workflow installs
  `typescript-language-server` for this case, so "no server found" there means
  the workflow broke, not the machine,
- while a server that is present, starts, initializes and then says nothing
  about content it cannot parse is always a failure. That is the state the
  report exists to catch.

Candidates, cheapest first, each verified to answer before being listed:
`lua_ls` (~0.8s), `ts_ls` (~1.1s), `gopls` (~15s cold, and skipped unless `go`
is also on PATH). The first available one runs; the others are not tried.
Timeouts are 30s for start-up and 30s for the probe -- generous, because a
loaded CI runner is slower than a laptop, and finite, because a hanging test
produces no output at all and takes the suite with it.

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

## What a pass over ~176 source files still leaves out

The suite above is large but not exhaustive, and it does not need to be: a
good share of `lua/lsp/**` is already exercised *generically* rather than by
a dedicated spec of its own -- `lsp.languages.enable_all()` calls every
app/documentation/webdev language module's `enable()` in a
loop that `languages_spec.lua` drives end to end, and
`lsp.integrations.setup()`/`.report()` do the same over every adapter in
`ADAPTERS`, which is what `integrations_spec.lua` and
`integrations_adapters_spec.lua` actually exercise. A file with no `_spec.lua`
of its own is not necessarily an untested file for that reason.

What is left for a later pass, by the same risk ordering the rest of this
suite follows, with why:

- Most of `lua/lsp/servers/**`'s individual server modules (`clangd.lua`,
  `csharp.lua`, `gopls.lua`, `zig.lua`, the `webdev/*` and `mobiledev/*`
  entries) -- each is a `vim.lsp.config()` call plus a capabilities/root_dir
  wiring shaped like `bashls.lua`/`marksman/init.lua`, which already have
  dedicated coverage. A generic per-server contract spec (matching
  `dap.nvim`'s language-table approach) would close this at less cost than
  one file per server, and is the natural next step here.
- `lua/lsp/core/root_scope_picker.lua` and `core/workspace_picker.lua` --
  real branching logic (`switchable()`, `announce()`, the "nothing to add"
  early returns) sits directly on top of `ui.kit.select`, which is stubbable
  the way `languages_spec.lua` already stubs it for a different picker. Not
  reached this round; the logic underneath (`core/workspace_folders.lua`,
  `core/root_scope.lua`) already is.
- `lua/lsp/integrations/{cmp,conform,inc_rename,lazydev,lensline,noice,
  trouble,picker,mason,nvchad}.lua`'s *own* internals beyond the adapter
  contract (`setup`/`capabilities`/`on_attach`/`on_init`/`available`) that
  `integrations_spec.lua` already drives generically for all of them.
- `lua/lsp/tools/deprecated_help/**` and `tools/lsp_signature/{format_hover,
  format_signature_help,highlights/parameters}.lua` -- pure formatting/glue
  under a subsystem (`lsp_signature`) that already has a dedicated spec
  covering its cache and request path; these are presentation details under
  that boundary.
- `@types` / `@types/*.lua` throughout the tree -- `---@meta` annotations,
  no runtime code.

None of the above showed a defect while being read for this pass; they are
deferred on cost/risk grounds, not because they were checked and found
clean.
