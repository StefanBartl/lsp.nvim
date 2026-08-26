# Roadmap — `lsp.nvim`

> **This is the original.** Until 2026-08-23 it mirrored a concept paper in the
> nvim config; that copy was deleted there together with the roadmaps of the
> other extracted plugins once the migration was through (config commit
> `32d7a760`). An extracted plugin carries its own roadmap — otherwise you
> maintain it in one place and read it in another. The original relative links
> into the config are reduced to plain text, because from here they point
> nowhere.
>
> Status 2026-08-23: **all five migration phases (§13) are through**, and so are
> the individual items after them — step 12, B8, B12, B14, B16–B19, the doc
> pages from §12, the spec suite (124 cases) and count support on the motion
> keys. All three author decisions from §15 are done: `NEW-20`, §15.1 (Trouble
> as the `]d`/`[d` sink, built since 2026-08-24) and §15.2 (completion engine,
> now `blink`). Nothing under §15 is left open.

# `lsp.nvim` — concept (umbrella plugin)

Extraction of `nvim/lua/lsp/**` **and of the config's entire LSP ecosystem**
into a standalone plugin, analogous to `dap.nvim` (`C:\repos\dap.nvim`, module
root `wkddap`) and the other extracted `*.nvim` plugins (`filetree.nvim`,
`sessions.nvim`, `pickers.nvim`, ...).

> **Status 2026-08-23.** All repos now live under `C:\repos\` — the
> `E:\repos\…` paths in this document have been updated accordingly.
>
> `C:\repos\lsp.nvim` (GitHub: `StefanBartl/lsp.nvim`) is on branch `main`.
> **Phases 0, 1 and 2 are complete.**
>
> - Phase 0: B1, B2, B4, B6 done (see the findings table).
> - Phase 1: `gates/NEW_PROJECT.md` walked through, record in
>   `docs/CHECKLISTS/NEW_PROJECT.md`; scaffold, tooling, CI, README, vimdoc,
>   smoke test.
> - Phase 2: the core has moved — 164 files, `core/`, `servers/`,
>   `languages/`, `formatter/`, `diagnostics/`, `lspdoctor/`, `tools/`,
>   `usercmds/`, `completion/`, `integrations/mason/`. The config loads the
>   plugin; `lua/lsp/**` is called `lua/lsp_legacy/**` there now and sits on no
>   require path any more.
>
> From phase 6, the move of `debug_adapters/**` into `dap.nvim` is done as well,
> **phase 3 is through** (all 42 LSP keys come from the catalogue,
> `docs/BINDINGS.md` is generated from it, CI checks with `--check`) and
> **phase 4 for the most part** (12 adapters under `integrations/`, the core
> knows no third-party plugin any more) and **phase 5** — `import = "lsp.pack"`
> installs and configures the ecosystem, `plugins/trouble.lua` and the LSP part
> of `plugins/lsp.lua` are gone.
>
> **All five phases are therefore through**, and by now the individual items
> too: step 12 (the ~30 `:Lsp*` are folded into 15 routes with legacy aliases),
> B8, B12, B14, B16–B19, `lua/lsp_legacy` deleted (163 files), the six doc pages
> from §12, a spec suite with 124 cases and count support on the motion keys
> (`NEW-25`).
>
§15 is thereby fully worked off. `NEW-20` (gen_map `--check` against a
> deliberately uncommitted map) is made precise in the gate; §15.2 (completion
> engine) has been running on `blink` as the default since 2026-08-24; §15.1
> (Trouble as the `]d`/`[d` sink) is implemented — details below under
> "Decided (2026-08-23, second pass)".
> Everything else under §15 "Open" has been settled by what was built.
>
> The migration found six bugs that had been running **live in the config**
> beforehand: the Copilot/cmp bridge was never called, `config_exists()` always
> reported "no config", a `format()` call without an argument would have aborted
> the whole setup at the first server without a module, a warning was discarded,
> a macOS guard was always false, and a global leaked. None of them would have
> been noticed by reading — they came out of specs, out of luacheck, and out of
> being forced to touch every line once during the move.

The basic decision is recorded in nvim.nvim.md (section
"`lsp.nvim` vs. `options.nvim`", 2026-07-17): `lua/lsp/` is structurally the
same thing as `dap.nvim` — a **stateful subsystem** (registry, capabilities,
attach handler, formatter toggle, workspace-diagnostics toggle), not
declarative settings. It therefore does **not** belong in `options.nvim`.

**New compared to the first concept version (2026-07-26):** `lsp.nvim` is not
merely a move of `lua/lsp/**`, but an **umbrella plugin** under which
*everything* LSP-related comes together — including the third-party plugins
(`trouble.nvim`, `conform.nvim`, `lazydev.nvim`, `nvim-cmp`/`blink.cmp`,
`mason.nvim`, `lspsaga.nvim`, `inc-rename.nvim`, `lensline.nvim`,
`workspace-diagnostics.nvim`) and *all* LSP/diagnostics keymaps that are today
scattered across `lua/bindings/mappings/**` and `lua/config/**`
(e.g. `<leader>wq`, `<leader>x*`, `<leader>rn`).

---

## Table of Content

- [1. Current state](#1-current-state)
- [2. Findings from the analysis (bugs & legacy)](#2-findings-from-the-analysis-bugs--legacy)
- [3. Target picture: umbrella plugin in three layers](#3-target-picture-umbrella-plugin-in-three-layers)
- [4. Scope boundaries](#4-scope-boundaries)
- [5. Architecture / directory tree](#5-architecture--directory-tree)
- [6. The pack system (LazySpec export)](#6-the-pack-system-lazyspec-export)
- [7. Integration adapters in detail](#7-integration-adapters-in-detail)
- [8. Bindings: keymaps, usercmds, autocmds](#8-bindings-keymaps-usercmds-autocmds)
- [9. Public API & defaults](#9-public-api--defaults)
- [10. lib.nvim integration](#10-libnvim-integration)
- [11. checkhealth & LspDoctor](#11-checkhealth--lspdoctor)
- [12. Documentation duties](#12-documentation-duties)
- [13. Migration plan](#13-migration-plan)
- [14. Roadmap: new features](#14-roadmap-new-features)
- [15. Open questions / decisions](#15-open-questions--decisions)

---

## 1. Current state

### 1.1 `lua/lsp/**` — 130 files, 11,645 LOC

| Area | Path | LOC | Responsibility |
|---|---|---:|---|
| Core | `core/{registry,attach,capabilities,handlers,filter,diagnostics,treesitter,util}.lua` | 668 | Server registry (`ACTIVE` list), `on_attach`/`on_init`, capabilities merge (cmp/blink/NvChad), publishDiagnostics dedup, treesitter wiring |
| Core (special cases) | `core/workspace_diagnostics.lua`, `core/root_scope.lua`, `core/root_scope_picker.lua` | (within 668) | Runtime toggle for `workspace-diagnostics.nvim` (startup-freeze fix), multi-root handling |
| Formatter | `formatter/{init,conform}.lua` | 408 | Conform-first, LSP fallback, view-preserving format-on-save with toggle |
| Diagnostics | `diagnostics/**` | 415 | Commands (`:Diag*`), keymaps (`<leader>wq`, `]d`/`[d`, `]q`/`[q`), quickfix/loclist, navigation |
| Server configs | `servers/**` (bashls, lua_ls, gopls, marksman, csharp, clangd, zig, webdev/*, mobiledev/*) | 3012 | Per-server setup; `lua_ls` with its own library resolver/reload/root resolver, `marksman` with its own handlers |
| Languages | `languages/**` (app, documentation, scripting, systems, webdev) | 1477 | Filetype-specific QoL (Astro autocmds/keymaps/usercmds, markdown words, ...) |
| Debug doctor | `lspdoctor/**` | 948 | `:LspDoctor {health,debug,quick,deep,all}` — **not** wired into `:checkhealth` |
| Tools | `tools/{eslint_prettier,lsp_signature,ts_type_lookup,deprecated_help}/**` | 2909 | Standalone extra tools, each with its own `setup()`/`attach()` |
| Usercmds | `usercmds/**` | 1170 | `:LspFormat*`, `:LspStart/Stop/RestartHere`, `:LspRecover`, `:LspWorkspaceDiagnostics*`, `:LspMobileDiagnostics`, command completion |
| Debug adapters | `debug_adapters/**` | 183 | **Misplaced** — DAP is its own protocol, belongs to `dap.nvim` |
| Types | `@types/**` + distributed `@types` subfolders | 202 | Already well structured per the guideline |

The entry point `lsp/init.lua` wires everything synchronously in `M.setup(cfg)`,
including host specifics (`machine.is("workstation")`,
`require("config.mason.ensure_install")`, `nvchad.config.lspconfig`).
It is called in init.lua:162: `require("lsp").setup({ ensure_installing = false })`.

### 1.2 LSP-adjacent third-party plugins in `lua/plugins/**`

This is the part the old concept was missing. All of the following plugins
belong, topically, under the `lsp.nvim` umbrella:

| Plugin | Spec location | Role | Coupling to `lua/lsp/**` |
|---|---|---|---|
| `folke/trouble.nvim` | `plugins/trouble.lua` (+ `config/trouble/numbering.lua`) | Diagnostics/quickfix/loclist/LSP list UI, `lazy = false` | none directly, but a **keymap conflict** on `]q`/`[q` (see §2) |
| `stevearc/conform.nvim` | `plugins/lsp.lua` | Formatter engine | `lsp/formatter/{init,conform}.lua` builds on it — **two setups in parallel** |
| `folke/lazydev.nvim` | `plugins/lsp.lua` | lua_ls library for `require` | `lsp/core/attach.lua:62` loads it via `pcall` for ft=lua |
| `hrsh7th/nvim-cmp` | `plugins/lsp.lua`, `config/copilot/cmp.lua` | Completion engine | `lsp/core/capabilities.lua:36` reads `cmp_nvim_lsp` |
| `saghen/blink.cmp` | `plugins/lsp.lua` (**commented out**) | Alternative completion engine | `lsp/core/capabilities.lua:53` already supports it |
| `williamboman/mason.nvim` | `plugins/*` + `config/mason/ensure_install/**` | Package management for LSP/DAP/linters/formatters | `lsp/init.lua:199` calls `config.mason.ensure_install` |
| `artemave/workspace-diagnostics.nvim` | `plugins/lsp.lua` | Workspace-wide diagnostics | `lsp/core/workspace_diagnostics.lua` + `usercmds` |
| `nvimdev/lspsaga.nvim` | `plugins/lsp.lua` | Breadcrumb/LSP UI (almost everything disabled) | none |
| `smjonas/inc-rename.nvim` | `plugins/lsp.lua` + `config/inc_rename/init.lua` | Incremental rename + auto-save | its own keymap `<leader>rn`, redundant with `grn` |
| `oribarilan/lensline.nvim` | `plugins/lsp.lua` | Codelens-like inline info | none |
| `nvim-treesitter` | `plugins/treesitter.lua` | Syntax | `lsp/core/treesitter.lua` wires it to LSP |
| `mrbjarksen/neo-tree-diagnostics.nvim` | `plugins/neotree.lua` | Diagnostics source in the filetree | borderline → stays with `filetree.nvim` |
| `kevinhwang91/nvim-bqf` | `plugins/*` | Better quickfix UI | borderline, quickfix is a diagnostics sink |
| `folke/todo-comments.nvim` | `config/todo_comments/**` | TODO list → Trouble/quickfix | borderline, not LSP |

### 1.3 Scattered LSP keymaps (current state)

Today in **five** different places. Full inventory:

| Keymap | Action | Source |
|---|---|---|
| `grn` | Rename | `bindings/mappings/lsp.lua:21` |
| `grt` | Type definition | `bindings/mappings/lsp.lua:35` |
| `lsr` / `lsi` / `lss` | References / implementations / doc symbols | `bindings/mappings/lsp.lua:27-29` |
| `lsd` / `lsD` / `lst` / `lsa` | Definition / declaration / type def / code action | `bindings/mappings/lsp.lua:30-33` |
| `<M-s>` (insert) | Signature help | `bindings/mappings/lsp.lua:37` |
| `<leader>gtt` | Lua table root — **calls `mylsp.nav.lua_root`, the module does not exist** | `bindings/mappings/lsp.lua:8` |
| `<leader>lsp` | Root-scope picker | `bindings/mappings/lsp.lua:12` |
| `<leader>lb` | Marksman hints toggle | `bindings/mappings/lsp.lua:16` |
| `<leader>tft` / `<leader>ft` / `<leader>fl` | Format-on-save toggle / format once / LSP format | `bindings/mappings/lsp.lua:42-71` |
| `<leader>tq` | Diagnostics → quickfix | `bindings/mappings/lsp.lua:78` |
| `<leader>wq` | Diagnostics → quickfix (workspace) | `lsp/diagnostics/keymaps.lua:15` |
| `<leader>lq` | Diagnostics → loclist (buffer) | `lsp/diagnostics/keymaps.lua:19` |
| `]d` / `[d` | Next/previous diagnostic (buffer) | `lsp/diagnostics/keymaps.lua:24-30` |
| `]q` / `[q` | Next/previous quickfix entry | `lsp/diagnostics/keymaps.lua:33-39` |
| `<leader>xt` / `xx` / `xw` / `xd` | Trouble diagnostics (toggle/all/workspace/buffer) | `bindings/mappings/trouble.lua:11-29` |
| `<leader>xlr` / `xld` / `xlt` / `xli` / `xls` | Trouble LSP views | `bindings/mappings/trouble.lua:32-46` |
| `<leader>xl` / `<leader>xq` | Trouble loclist / quickfix | `bindings/mappings/trouble.lua:49-50` |
| `]q` / `[q` / `]l` / `[l` | **Override** the diagnostics variant | `bindings/mappings/trouble.lua:53-56` |
| `]w` / `[w` | Next/previous workspace diagnostic (Trouble) | `bindings/mappings/trouble.lua:101-102` |
| `<leader>rn` | Incremental rename | `config/inc_rename/init.lua:173` |
| `<leader>dos` / `<leader>wos` | FzfLua document/workspace symbols | `bindings/mappings/fzf.lua:13-14` |
| `<leader>do` / `<leader>wo` | FzfLua document/workspace diagnostics | `bindings/mappings/fzf.lua:16-17` |
| `<leader>fq` | FzfLua quickfix | `bindings/mappings/fzf.lua:19` |

### 1.4 Scattered `lua/config/**` modules with LSP relevance

`config/mason/**`, `config/inc_rename/**`, `config/trouble/**`,
`config/copilot/cmp.lua` — all four belong under the umbrella.

---

## 2. Findings from the analysis (bugs & legacy)

Found while walking through the modules — to be fixed **before** or **during**
the migration, not carried along 1:1:

| # | Finding | Location | Assessment |
|---|---|---|---|
| B1 | **Unresolved git merge-conflict markers** (`<<<<<<< HEAD` / `=======` / `>>>>>>>`) in the source code | `lsp/core/capabilities.lua:61-71, 106-113` | 🔴 **Critical — ✅ DONE (2026-07-26).** The file was syntactically broken → `pcall(require, "lsp.core.capabilities")` failed → `lsp/init.lua:53` silently fell back to `make_client_capabilities()`; **completion capabilities from cmp/blink/NvChad were not applied at all.** Resolved in favour of the `8b6135fd` side (string levels `"error"`/`"warn"`), because `lsp/init.lua:44` compares against exactly those — with `vim.log.levels.ERROR` (a number) every error would silently have been downgraded to a warning. The duplicate `local warnings = {}` declaration was removed as well. |
| B2 | Keymap on the non-existent module `mylsp.nav.lua_root` | `bindings/mappings/lsp.lua:8` | ✅ **DONE (2026-08-23).** `mylsp` exists nowhere — not in `lua/`, not in an installed plugin — so the key threw on every press. Keymap removed, with a comment in its place. The feature itself ("jump to the enclosing Lua table/function root") is too good to throw away and now lives in §14, instead of being kept alive as a broken key. |
| B3 | `]q`/`[q` bound **twice** (diagnostics + trouble); trouble wins through later registration in `bindings/mappings/init.lua` | `lsp/diagnostics/keymaps.lua:33` vs. `bindings/mappings/trouble.lua:53` | ✅ **DONE (2026-08-23)** — with a corrected diagnosis. It was **not a behavioural conflict**: `quickfix.next_qf()` is `pcall(vim.cmd, "cnext")`, Trouble's variant is `<cmd>cnext<cr>`. The only difference: the swallowed E553 at the end of the list. Two owners, one behaviour. Now one catalogue entry, keeping the `pcall` variant. |
| B4 | `require("lsp.lspdoctor").setup()` is called **twice in a row** with contradictory `formatter_priority` | `lsp/init.lua:223-235` | ✅ **DONE (2026-08-23)** — with a corrected diagnosis: "the first one is dead code" was **not** true. `lspdoctor.setup()` merges key by key into a persistent `Opts` (`lspdoctor/init.lua:115`), so *all* keys from both calls took effect; only `formatter_priority` was overwritten. `list_limit`, `semantic_tokens_timeout` and `scratch_filetype` were never lost. Collapsed into one call that carries exactly the previous effective state — visible at the call site instead of inferred from merge semantics. Side finding: `null-ls` in the priority list has no effect, it is installed nowhere (conform does the formatting); left in place deliberately, because that is a decision and not a cleanup. |
| B5 | Conform is configured **twice**: `plugins/lsp.lua:126` (`format_on_save = {…}`) and `lsp/formatter/conform.lua` + `lsp/formatter/init.lua` (`format_on_save = false`, its own autocmd) | both | ✅ **Was already done** (verified 2026-08-23). `plugins/lsp.lua:153-157` today carries an explicit comment that there is **no** `config` block there and that `lsp.formatter.conform.setup()` is the single authoritative `conform.setup()` call. The entry here was stale — the fix landed somewhere between analysis and migration. Format-on-save runs through the plugin's own autocmd, never through conform's option. |
| B6 | `formatter/init.lua` documents itself as "Linux/macOS only; no Windows-specific branches" — the workstation runs on Windows | `lsp/formatter/init.lua:3` | ✅ **DONE (2026-08-23).** A stale comment, not a real limitation. `formatter/init.lua` itself needs nothing platform-dependent (autocmds + view preservation); the places that do live in `formatter/conform.lua` and branch correctly on Windows there (PATH separator `;`, `.cmd` suffix, Mason bin path — `conform.lua:20,40`). Header comment corrected accordingly. |
| B7 | The `ACTIVE` server list is hardcoded in the source, turning a server on or off means editing code | `lsp/core/registry.lua:10-33` | ✅ **DONE (2026-08-23).** List moved to `config/DEFAULTS.lua` as `servers`; `registry.setup_all(shared, servers)` receives it. An empty or broken list falls back to the defaults instead of yielding "no language server at all" — that looks like a broken installation and must never be the result of a typo. |
| B8 | Three homegrown root resolvers (`core/root_scope.lua`, `servers/lua_ls/rootresolver.lua`, `servers/marksman/rootresolver.lua`) despite `lib.nvim.fs` | see §10 | ✅ **DONE (2026-08-23)** — with a corrected finding. There were **two**, not three: `core/root_scope.lua` holds the state of the scope mode, it is not a resolver. And the two are not duplicates **of each other** — only of their wrapper: buffer number or file name → directory, fallback to cwd, the optional callback from the `vim.lsp` root_dir contract. That is exactly what `lib.nvim.fs.polymorphic_rootresolver` can do, but it was unusable for a resolver with its own search logic — so it was copied instead of used. It now has a `resolve` hook (StefanBartl/lib.nvim@6970428), marksman is thereby **the** shared resolver with markdown markers (45→27 lines), lua_ls keeps its algorithm (strict project boundary, scope switch, config-directory special case) and passes it in as a hook (122→97). Fixed along the way: `strict_root_from` returned `root_dir = nil` on nil, which can keep a server from starting — the shared wrapper falls back to the start directory. |
| B9 | `<leader>rn` (inc-rename) and `grn` (`vim.lsp.buf.rename`) do the same thing, differently | `config/inc_rename` vs. `bindings/mappings/lsp.lua` | ✅ **DONE (2026-08-23).** Deviating from the proposal: **both** keys stay instead of being reduced to one — the muscle memory for both is real, and the problem was never the number of keys but that they did different things. They now point at **one** action, and `rename.provider` (`auto\|inc_rename\|native`) decides the backend. inc-rename runs via `feedkeys` instead of an `expr` mapping, because an `expr` mapping cannot decide at press time not to be one. |
| B10 | `lsr`/`lsi`/`lss`/`lsd`/`lsD`/`lst`/`lsa` are **prefix-less** 3-character maps in normal mode | `bindings/mappings/lsp.lua:27-33` | They block `ls…` sequences and do not delay `l` motions, but they collide with the Neovim 0.11 defaults (`grr`, `gri`, `grn`, `gO`). Re-evaluate when defining the presets |
| B11 | `blink.cmp` fully commented out, `nvim-cmp` active — the capabilities module supports both | `plugins/lsp.lua:96-118` | ✅ **DONE (2026-08-23)** — but as `vim.g.lsp_nvim.pack.completion`, **not** as `opts.completion.engine` as proposed. The reason is the timing split from §6.2: whether a plugin gets *installed* must be settled before `setup(opts)` exists. `lsp.integrations.blink` could always merge blink's capabilities — what was missing was a way to **install** it. The two engines exclude each other via `enabled`. |
| B12 | `lspdoctor/health.lua` wrote into a bare `Opts`, i.e. into a **global** variable | `lsp/lspdoctor/health.lua:10` | ✅ **DONE (2026-08-23).** The finding was phrased too broadly: `inspect.lua` (quick/deep) does read its options — only `health.lua` did not. Which options *belong* there follows from the division of labour: `show_capabilities`/`show_workspace`/`show_conflicts` are deep sections per `doc/help.txt` and are served by `inspect.lua`; repeating them in `health` would mean implementing the same report twice. `health` now serves the three that fit it: `list_limit` (caps the detail, not the summary), `show_tools` (resolves the executable of every expected server — the most common reason for "configured, not running", and nobody was checking it) and `semantic_tokens_timeout` (a probe for clients that announce the capability and then do not answer). **`show_tools` and `semantic_tokens_timeout` were previously read nowhere in the plugin** — typed, documented, defaulted, unused. |
| B13 | `not X == "Darwin"` instead of `X ~= "Darwin"` — parses as `(not X) == "Darwin"` and is always false | `lsp/servers/mobiledev/sourcekit.lua:12` | ✅ **DONE (2026-08-23).** The macOS guard never took hold; the function fell through to the executable check on every platform. |
| B14 | The `handlers` table is filled and passed nowhere — the reason for the note "FIX: filtering does not work" next to it | `lsp/servers/webdev/htmx/init.lua:35` | ✅ **DONE (2026-08-23)** — removed, not wired up. `handlers` maps LSP *methods* to response handlers; a server's stderr stream never runs through there. Neovim reads it itself and offers no client-config hook for it, so filtering would mean wrapping `cmd` in a filtering process. I first left the attempt in place "as a record" — the wrong call: dead code that cannot work reads like code that does, and the next person has to re-derive why the obvious repair is not one. `filter_stderr` went with it, because after the removal nobody read it any more. The JSON filter itself stays in `htmx/filter_logs.lua`. |
| B15 | The core was never linted — the config has no lint gate | 23 findings in 15 files | ✅ **DONE (2026-08-23)** on the first CI run inside the plugin. Besides B12–B14: two empty `else` branches, dead `= nil` initialisations, unused callback arguments, an `_err, _config = _err, _config` self-assignment (a workaround for a *different* linter). The gate alone found four real defects — an argument that the extraction pays for itself on that ground alone. |
| B16 | `config_exists()` checked `lsp.config.get`, which does not exist — `vim.lsp.config` is a table with an `__index` resolver, not a module with a getter | `lsp/lspdoctor/health.lua` | ✅ **DONE (2026-08-23).** The guard therefore *always* triggered: `:LspDoctor health` reported "Config: ❌ No" for **every** server, running ones included. Found because I ran the check instead of reading it — in code the line looks plausible. Both accesses now go through a `config_for()` helper. |
| B17 | `config.setup()` cleared `_warnings` **after** recording the "expected a table" warning | `lsp/config/init.lua` | ✅ **DONE (2026-08-23).** Exactly the one warning the caller needs most urgently — they passed no table — was discarded again immediately. Found by the first spec I wrote for this file. |
| B18 | `("… '%s' …"):format()` without an argument, nested inside a second `format()` | `lsp/core/registry.lua:66` | ✅ **DONE (2026-08-23).** The expression **throws**, and nothing on that path is wrapped in `pcall`: **a single configured server without a module would have aborted the entire server setup** and taken `setup()` down with it. Never noticed because every name in `servers` happened to resolve — entering a server before its module exists would have been enough. |
| B19 | `lib.nvim.bindings.autocmd.group` memorised augroup IDs and never checked them again | `lib.nvim` | ✅ **DONE (2026-08-23).** Whoever deletes the group behind the cache — `nvim_del_augroup_by_name`, the only way for a plugin to give up its autocommands — left a dead ID in it, and **every** further `create()` against that group failed with "Invalid 'group'" until Neovim restarts. Noticed because this very plugin calls `clear()` first and `group()` second. Fixed upstream instead of worked around here (LUA-02), with a spec. |

---

## 3. Target picture: umbrella plugin in three layers

**Basic decision (2026-07-26): hard dependencies are wanted, not to be
avoided.** An LSP umbrella plugin that touches `trouble.nvim`, `conform.nvim`,
`mason.nvim` & co. only "if present" would, in case of doubt, have to rebuild
their functionality itself — that buys nothing and would be 10,000 lines of
worse code. `lsp.nvim` depends hard on `lib.nvim` anyway; the ecosystem joins on
the same terms. The umbrella claim is explicit: **whoever installs `lsp.nvim`
gets the complete LSP setup including the third-party plugins.**

The three-way split remains nonetheless — not as a dependency gradation, but as
a **separation of responsibilities**, so that the codebase stays navigable and
individually testable:

```
┌──────────────────────────────────────────────────────────────────┐
│ Layer 3 — PACK   lua/lsp/pack/**                                 │
│   LazySpec export: WHAT gets installed, in which version, with   │
│   which presets. `{ “StefanBartl/lsp.nvim”, import=”lsp.pack”}   │
│   Contains NO logic, only specs + opts.                          │
├──────────────────────────────────────────────────────────────────┤
│ Layer 2 — INTEGRATIONS   lua/lsp/integrations/**                 │
│   HOW the third-party plugins are wired: config, keymaps,        │
│   handler bridges, capabilities. One module per plugin.          │
├──────────────────────────────────────────────────────────────────┤
│ Layer 1 — CORE   lua/lsp/{core,servers,languages,formatter,…}    │
│   Own code on `vim.lsp.*`: registry, attach, server configs,     │
│   formatter core, diagnostics core, LspDoctor, tools.            │
└──────────────────────────────────────────────────────────────────┘
```

**Rules:**

- Layer 1 does not know layer 2 (`core/attach.lua` never calls
  `require(“lazydev”)` directly — the adapter does that). Not because of
  optionality, but so the core stays testable on its own and a third-party
  plugin swap (cmp → blink) touches exactly one file.
- Layer 2 knows layer 1 and may assume that "its" plugin is there.
- Layer 3 knows both, but is loaded by neither.

**`pcall` stays everywhere nonetheless** — but with a different rationale than
before: not "the plugin is optional", but **blast-radius containment**. If
`lensline.nvim` is broken after an update, that must not take the server
registry down with it. A failed adapter reports itself in `:checkhealth lsp` as
an `error` (not as an incidental `info` the way an optional feature would) and
the rest keeps running.

**Declared hard dependencies** (in the `lsp.nvim` spec):
`lib.nvim`, `conform.nvim`, `trouble.nvim`, `mason.nvim`, `lazydev.nvim`,
`workspace-diagnostics.nvim` + the chosen completion engine.
**Soft** are only those that are genuine *alternatives* or pure extra UI:
`lspsaga`, `lensline`, `inc-rename`, `noice`, `which-key`, the picker
(fzf-lua/telescope/snacks/`pickers.nvim`) and `nvchad`.

---

## 4. Scope boundaries

### Moves along into `lsp.nvim`

- Everything from `lua/lsp/**` **except** `debug_adapters/**`
- `lua/bindings/mappings/lsp.lua` (in full)
- `lua/bindings/mappings/trouble.lua` (in full — Trouble is pure
  diagnostics/LSP UI)
- `lua/config/inc_rename/**`
- `lua/config/trouble/**`
- `lua/config/mason/**` (as an optional `integrations/mason` + pack spec)
- `lua/config/copilot/cmp.lua` (completion-menu interaction → `integrations/cmp`)
- The LSP-related lines from `lua/bindings/mappings/fzf.lua`
  (`<leader>dos`, `<leader>wos`, `<leader>do`, `<leader>wo`) — as
  `integrations/picker` with a backend choice (fzf-lua / telescope / snacks /
  `pickers.nvim`), so that fzf-lua is not hardwired
- The plugin specs from `lua/plugins/lsp.lua` and `lua/plugins/trouble.lua`
  → `lua/lsp/pack/**`

### Does NOT move along, but goes to `dap.nvim` — ✅ done 2026-08-23

`lua/lsp/debug_adapters/**` (bash, node, go, dotnet, webdev/browser). DAP is
topically independent of LSP — the only thing in common is "Mason installs
both". `lsp/debug_adapters/init.lua` is only a collection of commented-out
`require`s anyway, so effectively inactive. **"A pure move without loss of
functionality" was not possible, though** — that assumption was wrong.
`dap.nvim` has its own architecture (`registry` + `languages/<lang>.lua` with
`setup()`/`load()`, binary resolution via `config.get_adapter_path`) that the
old modules did not fit into: they registered everything at module load time.
Result:

- **Ported** as `wkddap.languages.{bash,csharp,browser}` — the three targets
  `dap.nvim` did not have yet. Two real bugs were fixed along the way: the
  netcoredbg path was hardwired to **one machine**
  (`C:/tools/DebugAdapterProtocol/netcoredbg/netcoredbg.exe`), and
  `set noshellslash` ran as a global side effect on the mere `require`.
- **Discarded** instead of ported: `go` and `node`. `wkddap.languages.go` and
  `.javascript` cover them with more configurations and proper adapter
  resolution — the old copies would have been duplicates, not a migration.
- Registry, `adapter_binaries` and `language_aliases` extended
  (`sh|zsh|ksh` → `bash`, `cs|fsharp|dotnet` → `csharp`); `browser`
  deliberately without an alias, because it is not a filetype but an
  independently selectable target.
- Side finding: `dap.nvim`'s CI was **red** on `main`, for two mutually
  independent reasons — `rust.lua` was not stylua-formatted, and the zig
  "launch (build first)" specs still checked against a
  `vim.system(...):wait()` stub, even though the implementation had long since
  moved to the callback form (so that the build no longer freezes the editor).
  Both fixed, suite 12/12.

**Mason (decided 2026-07-26): `ensure_install` moves into `lsp.nvim`
completely.** Not into `lib.nvim` — it is not a generic building block but
package management for language tooling, and therefore exactly what an LSP
umbrella plugin is responsible for. `mason.nvim` becomes a hard dependency.

Concretely, `config/mason/**` (facade + `defaults/{lsp,linter,formatter}.lua`,
session aggregation, dedup across categories, external dependency guards) moves
to `lua/lsp/integrations/mason/`. Two consequences:

- `defaults/dap.lua` belongs, by content, to `dap.nvim`. `lsp.nvim` offers a
  registration API for it, so that `dap.nvim` needs no Mason facade of its own
  and the two do not produce "Package is already installing" for each other:

  ```lua
  require("lsp.integrations.mason").register("dap", {
    ["js-debug-adapter"] = true, ["netcoredbg"] = true, …
  })
  ```

  That keeps the dedup logic in **one** place. `dap.nvim` thereby gains a soft
  dependency on `lsp.nvim` (pcall-guarded: if it is missing, `dap.nvim` does
  its installs itself as before).
- Today's call `lsp/init.lua:198-220` (`cfg.ensure_installing`) becomes
  `opts.mason` (see §9), including the `overrides` table.

### Stays in the host (`nvim/`)

- The `machine.is("workstation")` gating → passed into `setup()` as an option,
  never referenced internally
- The NvChad coupling (`nvchad.config.lspconfig.on_attach/on_init/capabilities`)
  → an optional adapter `integrations/nvchad`, not an implicit fallback path
- `neo-tree-diagnostics.nvim` → stays with `filetree.nvim`/the neotree config
- `todo-comments.nvim`, `nvim-bqf` → stay in the host (not LSP), but
  `nvim-bqf` is mentioned in `docs/` as a recommended addition

---

## 5. Architecture / directory tree

The module root stays `lsp` (not `wkdlsp` as in `dap.nvim`): Neovim only
occupies `vim.lsp`, `nvim-lspconfig` occupies `lspconfig` — the top-level name
`lsp` is free. Advantage: **all existing `require("lsp.…")` paths in the config
stay valid** (e.g. `autocmds/events/utils/filetype.lua:46-106`).

```
lsp.nvim/
├── lua/lsp/
│   ├── init.lua                    -- M.setup(opts): orchestration only
│   ├── health.lua                  -- :checkhealth lsp  (mandatory)
│   ├── @types/
│   │   ├── init.lua                -- LspNvim.Config, LspNvim.Opts, …
│   │   ├── servers.lua
│   │   ├── formatter.lua
│   │   ├── languages.lua
│   │   ├── keymaps.lua             -- NEW: LspNvim.KeymapSpec / KeymapName
│   │   └── integrations.lua        -- NEW
│   ├── config/
│   │   ├── init.lua                -- merge user opts over DEFAULTS, validation
│   │   └── DEFAULTS.lua            -- ONE source for all defaults
│   ├── core/                       -- layer 1
│   │   ├── registry.lua            -- ACTIVE list from opts.servers instead of hardcoded
│   │   ├── attach.lua              -- without direct NvChad access
│   │   ├── capabilities.lua        -- conflict markers out (B1), engine via opts
│   │   ├── handlers.lua
│   │   ├── filter.lua
│   │   ├── diagnostics.lua
│   │   ├── treesitter.lua
│   │   ├── workspace_diagnostics.lua
│   │   ├── root_scope.lua          -- reduce to lib.nvim.fs where possible
│   │   └── util.lua
│   ├── formatter/                  -- layer 1, conform as an integration
│   ├── diagnostics/                -- layer 1 (core), UI via integrations
│   ├── servers/                    -- 1:1 move
│   ├── languages/                  -- 1:1 move
│   ├── lspdoctor/                  -- + bridge to health.lua
│   ├── tools/
│   │   ├── eslint_prettier/
│   │   ├── lsp_signature/
│   │   ├── ts_type_lookup/
│   │   ├── deprecated_help/
│   │   └── _test/                  -- NEW: test entry point (guideline §6)
│   ├── integrations/               -- layer 2 — pcall = blast radius, not optionality
│   │   ├── init.lua                -- registry + ordering + available() report
│   │   ├── trouble.lua             -- [hard]
│   │   ├── conform.lua             -- [hard]
│   │   ├── lazydev.lua             -- [hard]
│   │   ├── cmp.lua                 -- nvim-cmp + Copilot menu bridge  [hard, alternative]
│   │   ├── blink.lua               -- [hard, alternative]
│   │   ├── mason/                  -- [hard] formerly config/mason/**
│   │   │   ├── init.lua            -- facade + register(kind, pkgs) for dap.nvim
│   │   │   ├── ensure_install.lua  -- session aggregation, dedup, dependency guards
│   │   │   └── defaults/{lsp,linter,formatter}.lua
│   │   ├── workspace_diagnostics.lua  -- [hard]
│   │   ├── lspsaga.lua
│   │   ├── inc_rename.lua
│   │   ├── lensline.lua
│   │   ├── picker.lua              -- fzf-lua | telescope | snacks | pickers.nvim
│   │   ├── which_key.lua
│   │   ├── noice.lua
│   │   └── nvchad.lua
│   ├── pack/                       -- layer 3 — pure LazySpecs
│   │   ├── init.lua                -- imports core/ui/completion depending on vim.g
│   │   ├── core.lua                -- conform, mason, workspace-diagnostics
│   │   ├── ui.lua                  -- trouble, lspsaga, lensline, inc-rename
│   │   └── completion.lua          -- lazydev + (cmp | blink)
│   └── bindings/
│       ├── init.lua
│       ├── keymaps.lua             -- ALL LSP/diagnostics keymaps, user-overridable
│       ├── usercmds.lua            -- :Lsp composer + legacy aliases
│       ├── autocmds.lua
│       └── which_key.lua           -- group labels, soft dependency
├── plugin/lsp_nvim.lua             -- only if a command is needed before setup()
├── doc/lsp.txt                     -- English, `:h lsp.nvim`
├── docs/
│   ├── BINDINGS.md                 -- mandatory: all keymaps/usercmds/autocmds
│   ├── ROADMAP.md
│   ├── installation.md
│   ├── configuration.md
│   ├── features.md
│   ├── commands.md
│   ├── architecture.md
│   ├── health.md
│   └── UMBRELLA.md                 -- NEW: how the pack system works
├── .luarc.json
├── stylua.toml
└── README.md                       -- English, ASCII art + badges + ToC (H2 only)
```

The internal structure of layer 1 stays largely 1:1 — it is already organised
along [Arch&Coding-Regeln.md](file:///C:/repos/WKDBooks/Development/wkdbook-Lua/Checklists/archiv/Arch&Coding-Regeln.md)
(SRP per module, `@types` subfolders, `pcall` discipline). The extraction is
mostly **moving + decoupling from host specifics**, not a rewrite. What gets
newly built is essentially `config/`, `integrations/`, `pack/`, `bindings/`,
`health.lua`.

---

## 6. The pack system (LazySpec export)

This is the mechanism that makes `lsp.nvim` an umbrella plugin.

### 6.1 How it works

lazy.nvim can import specs from a plugin's `lua/` directory when the import
hangs off the plugin's own spec (LazyVim uses the same technique with
`{ "LazyVim/LazyVim", import = "lazyvim.plugins" }`). That way **one entry** in
the user config is enough:

```lua
-- lua/plugins/personal/init.lua
{
  "StefanBartl/lsp.nvim",
  import = "lsp.pack",                     -- ← installs the whole ecosystem
  dependencies = { "StefanBartl/lib.nvim" },
  event = { "BufReadPre", "BufNewFile" },
  opts = {
    -- everything else: see §9
  },
}
```

Without `import = "lsp.pack"` you get only layers 1+2 — `lsp.nvim` then wires up
whatever is installed anyway and ignores the rest.

### 6.2 Timing problem and solution

`import` is evaluated by lazy.nvim while **collecting** the specs — long before
`require("lsp").setup(opts)` runs. The pack therefore cannot read from `opts`.
Two channels, deliberately kept apart:

| Channel | Point in time | Controls |
|---|---|---|
| `vim.g.lsp_nvim` (table, set before `require("lazy").setup()`) | spec collection time | **Whether** a third-party plugin gets installed, version pins, engine choice (`cmp` vs. `blink`) |
| `opts` in the plugin spec | setup time | **How** everything is configured: servers, keymaps, formatter, tools |

```lua
-- before require("lazy").setup(...)
vim.g.lsp_nvim = {
  pack = {
    core       = true,             -- conform, mason, workspace-diagnostics
    ui         = true,             -- trouble, lspsaga, lensline, inc-rename
    completion = "cmp",            -- "cmp" | "blink" | false
    -- fine-grained: deselect individual plugins
    disable    = { "lspsaga.nvim" },
  },
}
```

`require("lsp").setup(opts)` reads `vim.g.lsp_nvim` as the base and merges
`opts` over it, so that at runtime there is still **one** resolved config
(`require("lsp.config").get()`). Contradictions (e.g. `pack.completion = false`
but `opts.completion.engine = "blink"`) are reported by `:checkhealth lsp` as a
warning.

### 6.3 Use without the pack

The pack is the **recommended path** — it is the reason the plugin is an
umbrella. Whoever still wants to manage the specs themselves (e.g. because they
pin a different Trouble version) leaves `import` out and keeps their own
`plugins/*.lua`; layer 2 finds the plugins via `require` and wires them
identically. If a **hard** dependency (§3) is then missing, `:checkhealth lsp`
reports that as an `error` with the missing plugin's name — instead of silently
delivering half a setup.

That is also the migration path (§13): first move without the pack (today's
`plugins/lsp.lua` / `plugins/trouble.lua` stay in place), then transfer the
specs into the pack in phase 5.

---

## 7. Integration adapters in detail

Every adapter has the same signature:

```lua
---@class LspNvim.Integration
---@field name string
---@field available fun(): boolean          # is the third-party plugin there?
---@field setup fun(cfg: LspNvim.Config): boolean, string?   # wire it up
---@field health fun(report: LspNvim.HealthReport): nil      # for :checkhealth
```

`integrations/init.lua` holds the registry and calls the adapters in a defined
order. An adapter whose plugin is missing or whose `setup()` fails takes nothing
down with it (§3, blast radius) — it reports itself in the health report, never
via `notify()` (rule: no `notify()` in low-level code). The severity follows the
dependency hardness from §3: a **hard** dependency missing → `error`, a **soft**
one missing → `info`.

| Adapter | What `lsp.nvim` takes over |
|---|---|
| `trouble` | The complete setup block (preview split on the right at 30 %, index formatter from `config/trouble/numbering.lua`, modes `diagnostics`/`qflist`/`loclist`) **plus all `<leader>x*` keymaps**. The Neovim 0.12 patch for `TSHighlighter._on_win/_on_line` (`plugins/trouble.lua:86-114`) moves along — with a version guard instead of unconditionally. Trouble becomes the **default sink** for diagnostics: if it is there, `]d`/`[d`/`]q`/`[q` go through Trouble, otherwise through the core loclist/quickfix implementation. That solves B3 structurally |
| `conform` | **One** conform configuration (two today, B5): `formatters_by_ft` from `opts.formatter.by_ft`, `format_on_save` **always** through the plugin's own view-preserving toggle in `lsp/formatter/init.lua`, never through conform's `format_on_save` |
| `lazydev` | Library list (today `plugins/lsp.lua:34-44`) as a default in `DEFAULTS.lua`, extendable via `opts.lua.lazydev.library`. The `pcall(require, "lazydev")` from `core/attach.lua:62` moves here |
| `cmp` | `cmp_nvim_lsp` capabilities, `lazydev` source (`group_index = 0`), Copilot menu bridge (`config/copilot/cmp.lua`) |
| `blink` | `get_lsp_capabilities()`, `lazydev` provider (`score_offset = 100`), `signature.enabled`. The commented-out block from `plugins/lsp.lua:96-118` becomes a real, selectable alternative here |
| `mason` | `ensure_install` facade (today `config/mason/ensure_install/**`), package lists from `opts.mason.ensure` with `overrides` |
| `workspace_diagnostics` | Populate-on-attach behind the runtime toggle (`core/workspace_diagnostics.lua`) — unchanged, just an adapter wrapper |
| `lspsaga` | Today's setup block (only breadcrumb active), as a default preset |
| `inc_rename` | `setup()` + `post_hook` (auto-save of the touched buffers, `config/inc_rename/init.lua`). Solves B9: `opts.rename.provider = "auto"` takes inc-rename when present, otherwise `vim.lsp.buf.rename` — **one** keymap for both |
| `lensline` | Profile `minimal`, `render = "focused"` |
| `picker` | Abstraction for symbol/diagnostics pickers: `fzf-lua` \| `telescope` \| `snacks` \| `pickers.nvim` \| `auto`. Replaces the four keymaps hardwired to FzfLua in `bindings/mappings/fzf.lua` and the ad-hoc telescope binding in `tools/ts_type_lookup/ts_telescope_picker.lua` |
| `which_key` | Group labels for all prefixes (`<leader>l`, `<leader>x`, `<leader>f`, …), v2 and v3 API, analogous to `dap.nvim/bindings/which_key/init.lua` |
| `noice` | `ts_type_lookup/noice_integration.lua` + inc-rename cmdline preset |
| `nvchad` | `on_attach`/`on_init`/`capabilities` bridge, **only** if `opts.integrations.nvchad = true` |

---

## 8. Bindings: keymaps, usercmds, autocmds

### 8.1 Keymaps — one preset, fully overridable

All keymaps from §1.3 move into `lua/lsp/bindings/keymaps.lua`. Requirement from
[NEW_PROJECT.md](file:///C:/repos/WKDBooks/Development/wkdbook-Lua/Checklists/gates/NEW_PROJECT.md): *"all keymaps must be easily
modifiable / disableable by the user"* and *"have a which-key
implementation"*.

```lua
opts = {
  keymaps = {
    enabled = true,              -- false = no keymaps at all
    preset  = "default",         -- "default" | "minimal" | "none"

    -- individually: string = new lhs, false = disabled, nil = default
    goto_definition   = "lsd",
    goto_references   = "lsr",
    rename            = "grn",
    code_action       = "lsa",
    format_buffer     = "<leader>ft",
    format_toggle     = "<leader>tft",
    diag_next         = "]d",
    diag_prev         = "[d",
    diag_to_qflist    = "<leader>wq",
    diag_to_loclist   = "<leader>lq",
    trouble_toggle    = "<leader>xt",
    -- …
  },
}
```

Implementation: a **declarative table** `KEYMAPS = { <name> = { lhs, mode, rhs,
desc, requires? } }` in `config/DEFAULTS.lua`; `bindings/keymaps.lua` iterates
over it, applies the user overrides and registers via `lib.nvim.bindings.keymap`.
`requires = "trouble"` makes sure a keymap is only set when the adapter is
available — including an automatic fallback to the core variant. Side effect:
`docs/BINDINGS.md` can be **generated from that table** (no doc drift), and
`:checkhealth lsp` can report collisions with existing mappings.

**Decided (2026-07-26, B10): the `ls*` assignment stays.** `lsr`/`lsi`/`lss`/
`lsd`/`lsD`/`lst`/`lsa` are adopted as preset `default`. They are not a
replacement for the Neovim 0.11 defaults but sit next to them: `grr`, `gri`,
`grn`, `grt`, `gO` keep working, because Neovim sets them buffer-locally on
`LspAttach` while the `ls*` maps are global — no conflict, just two paths to the
same destination.

Two points that nevertheless belong in `docs/BINDINGS.md`:

- `lsd`/`lsr`/… delay every normal-mode input beginning with `l` by
  `timeoutlen`, because Neovim waits for the sequence to continue. That is the
  price of the prefix-less maps and is already the case today — just documented
  nowhere so far.
- `grn` is bound twice: once by Neovim (buffer-local, `LspAttach`) and once
  globally in `bindings/mappings/lsp.lua:21`. The global one does not win —
  buffer-local maps take precedence. Both point at `vim.lsp.buf.rename`, so it
  is inconsequential; with `rename.provider = "inc_rename"` (B9) they would
  diverge, though. The adapter must therefore override the **buffer-local** map
  on `LspAttach`, not merely set the global one.

### 8.2 Usercmds — the `:Lsp` composer

Requirement: one composite user command `:Cmd [options?]` with autocompletion
via `lib.nvim.bindings.usercmd.composer`.

```
:Lsp status                      :Lsp doctor [health|debug|quick|deep|all]
:Lsp start|stop|restart [here]   :Lsp format [on|off|toggle|status|which]
:Lsp diag [qf|loc|next|prev]     :Lsp workspace [on|off|toggle|status|now]
:Lsp servers                     :Lsp root [pick|show]
:Lsp log [open|level <lvl>]      :Lsp recover
```

Today's ~30 individual commands (`:LspFormat*`, `:LspWorkspaceDiagnostics*`,
`:LspStartHere`, `:DiagQF`, …) are kept as **thin aliases**
(`opts.usercmds.legacy_aliases = true`, default `true`) — muscle memory beats
purity, and the aliases cost one line each. `:LspDoctor` additionally stays
standalone (a justified exception, analogous to `:Surround` in
`replacer.nvim`): it is a diagnostic tool with its own renderer, not an LSP
control command.

Server-specific commands (`:AstroDevStart`, `:MdFormat`, `:LuaLsReloadLibrary`,
`:TypeDef*`, `:EslintFix`, …) stay as they are — they are filetype-bound and do
not belong in a global composer.

### 8.3 Autocmds

`bindings/autocmds.lua` bundles: `LspAttach` wiring, the format-on-save group
(`LspFormatOnSave`), diagnostics refresh, Astro autocmds. All via
`lib.nvim.bindings.autocmd` + `lib.nvim.augroup`, every group deletable/reloadable
(central principles §4).

---

## 9. Public API & defaults

`config/DEFAULTS.lua` is the single source; `config/init.lua` merges and
validates. Goal per the requirement: **maximum user experience with minimal
initial config** — `require("lsp").setup()` without arguments must yield a
complete, sensible setup.

```lua
require("lsp").setup({
  ---@type string[]  replaces the hardcoded ACTIVE list (B7)
  servers = { "lua_ls", "gopls", "bashls", "marksman", "html", "ts_ls",
              "tailwindcss", "csharp" },
  server_opts = { lua_ls = { … } },       -- per-server overrides

  diagnostics = {
    virtual_text = { spacing = 2, prefix = "●" },
    severity_sort = true,
    update_in_insert = false,
    float = { border = "rounded", source = "if_many" },
    ui = "trouble",                       -- "trouble" | "native" | "auto"
  },

  formatter = {
    on_save = false,                      -- view-preserving toggle
    timeout_ms = 1500,
    engine = "conform",                   -- "conform" | "lsp" | "auto"
    by_ft = { lua = { "stylua" }, … },
  },

  completion = { engine = "auto" },       -- "cmp" | "blink" | "auto" | false
  rename     = { provider = "auto" },     -- "inc_rename" | "native" | "auto"

  workspace_diagnostics = { enabled = false },   -- the host passes the machine role
  inlay_hints           = { enabled = false, filetypes = {} },   -- NEW

  tools = {
    eslint_prettier = { enabled = true, filetypes = { "javascript", … } },
    lsp_signature   = { enabled = true },
    ts_type_lookup  = { enabled = true },
    deprecated_help = { enabled = true },
  },

  integrations = {
    trouble = true, conform = true, lazydev = true, mason = false,
    lspsaga = true, inc_rename = true, lensline = true,
    picker = "auto", which_key = true, noice = true,
    nvchad = false,                       -- default OFF: reusability
  },

  mason = { ensure_install = false, packages = { … }, overrides = { … } },
  keymaps = { … },                        -- see §8.1
  usercmds = { legacy_aliases = true },
  lspdoctor = { use_notify = false, list_limit = 8, … },
})
```

Every key gets a type in `@types/` (requirement: "for a good LSP experience:
every key needs a type"), e.g.:

```lua
---@alias LspNvim.CompletionEngine "cmp"|"blink"|"auto"|false
---@alias LspNvim.DiagnosticsUi   "trouble"|"native"|"auto"
---@alias LspNvim.RenameProvider  "inc_rename"|"native"|"auto"
```

On the host side the call then looks like this (replacing `init.lua:156` **and**
the specs in `plugins/lsp.lua` / `plugins/trouble.lua`):

```lua
{
  "StefanBartl/lsp.nvim",
  import = "lsp.pack",
  dependencies = { "StefanBartl/lib.nvim" },
  event = { "BufReadPre", "BufNewFile" },
  opts = {
    integrations = { nvchad = true },
    workspace_diagnostics = { enabled = not require("machine").is("workstation") },
    mason = { ensure_install = false },
  },
}
```

---

## 10. lib.nvim integration

Mandatory per [Arch&Coding-Regeln.md §NVIM config specific](file:///C:/repos/WKDBooks/Development/wkdbook-Lua/Checklists/archiv/Arch&Coding-Regeln.md)
and [Checklist.md](file:///C:/repos/WKDBooks/Development/wkdbook-Lua/Checklists/archiv/Checklist.md). Available modules in
`C:\repos\lib.nvim`: `autocmd, buf_win_tab, buffer, cache, core, cross,
debounce, docmap, dotrepeat, fs, git, harvest, logger, lua_ls, map, neotree,
net, normalize, notify, progress, require, safe_api, selection, store, system,
terminal, token, treesitter, ui, usercmd, window` as well as `lib.lua.{lazy,
memo, tables, strings, error, json, …}`.

| Currently in `lua/lsp/**` | Replace with | Note |
|---|---|---|
| `require("lib.nvim.notify").create(…)` | already in use ✅ | keep it consistent |
| `vim.keymap.set` (`diagnostics/keymaps.lua`) | `lib.nvim.bindings.keymap` | currently inconsistent |
| homegrown `nvim_create_user_command` (`usercmds/formatter.lua:5`) | `lib.nvim.bindings.usercmd` | partly already (`usercmd.create` in `diagnostics/commands.lua`) |
| ~30 individual commands | `lib.nvim.bindings.usercmd.composer` | exists (`lua/lib/nvim/bindings/usercmd/composer`) → `:Lsp` composer, see §8.2 |
| homegrown `nvim_create_autocmd` (`formatter/init.lua`) | `lib.nvim.bindings.autocmd` / `lib.nvim.augroup` | partly already |
| `core/root_scope.lua`, `servers/lua_ls/rootresolver.lua`, `servers/marksman/rootresolver.lua` | `lib.nvim.fs.find_root` / `polymorphic_rootresolver` | **dedup candidate B8**: three re-implementations of the same problem |
| Library profile caching (`servers/lua_ls`, `lspdoctor`) | `lib.nvim.cache` | check whether it is `stdpath("cache")`-conformant |
| Format-on-save timing, diagnostics refresh | `lib.nvim.debounce` / `debounce.buffer` | no debouncing today → performance candidate |
| `get_installed_lsps()` (`usercmds/completion.lua`) queries Mason afresh on every tab-complete | `lib.lua.memo` | a clear candidate |
| All tools are loaded synchronously in `init.lua`, regardless of filetype | `lib.lua.lazy` | `ts_type_lookup`, `deprecated_help` are rarely needed |
| `vim.ui.select` (`root_scope_picker`, LspDoctor mode) | `lib.nvim.selection` / `lib.nvim.ui` | check the API before using it — `hover_select` was not findable in the repo |
| Windows path in the formatter (B6) | `lib.nvim.cross` | cross-platform rule |
| `lspdoctor` renderer, progress on Mason installs | `lib.nvim.ui`, `lib.nvim.progress` | requirement §10 NEW_Project |
| Structured errors / `safe_call` | `lib.lua.error`, `lib.nvim.safe_api` | replaces the many ad-hoc `pcall` chains in `lsp/init.lua` |
| Doc generation `docs/BINDINGS.md` | `lib.nvim.docmap` | check whether it can render the keymap table |

---

## 11. checkhealth & LspDoctor

Mandatory per the requirement: *"every plugin should have `:checkhealth`
functionality"*. Today only `:LspDoctor health` exists — **no**
`:checkhealth` provider.

`lua/lsp/health.lua` becomes a **thin second interface onto the same core**
(`lspdoctor/health.lua`), not a code duplicate. It reports via
`vim.health.{start,ok,warn,error,info}`:

1. **Environment**: Neovim version ≥ 0.11, `lib.nvim` present
2. **Config**: resolved opts valid, contradictions `vim.g.lsp_nvim` ↔ `opts` (§6.2)
3. **Servers**: configured vs. actually attached vs. executable on `$PATH`
4. **Integrations**: per adapter `available()` + whether `setup()` succeeded
5. **Keymaps**: registered maps, collisions with foreign mappings
6. **Formatter**: which formatter would take effect for the current buffer,
   priority conflicts (verify the `lspdoctor` option `formatter_priority`
   against the actual behaviour of `formatter/conform.lua`)
7. **Performance**: workspace-diagnostics state, number of loaded buffers
8. Optional: results from `docs/TESTS/**` resp. `tools/_test`

---

## 12. Documentation duties

From [NEW_PROJECT.md](file:///C:/repos/WKDBooks/Development/wkdbook-Lua/Checklists/gates/NEW_PROJECT.md):

- `README.md` — **English**, ASCII art + badges at the top, table of content
  (H2 only). Directly after the ASCII art a `>` paragraph linking to the plugin
  that complements it best → **`dap.nvim`** (sister subsystem, same
  architecture) or `lib.nvim` (hard dependency). Proposal: `dap.nvim`.
- `/doc/lsp.txt` — English, `:h lsp.nvim`-capable, generate `doc/tags`
- `/docs/ROADMAP.md` — future features (see §14)
- `/docs/BINDINGS.md` — **all** keymaps, usercmds, autocmds; generated from the
  keymap table (§8.1)
- `/docs/UMBRELLA.md` — the pack system explained (§6): what gets installed, how
  to deselect, how to use `lsp.nvim` without the pack
- An installation spec for several package managers, with an explicit
  `event`/`cmd`/`ft`; **no** `dir = vim.env…`, **no** licence references
- `.luarc.json` + `stylua.toml` in the project root
- Finally, enter all usercmds/keymaps/autocmds in
  [NEW_PROJECT.md](file:///C:/repos/WKDBooks/Development/wkdbook-Lua/Checklists/gates/NEW_PROJECT.md)

---

## 13. Migration plan

Deliberately in phases, so that the config stays runnable between them.

### Phase 0 — preparatory work in the host (before any move)

1. ✅ **B1 fixed** (2026-07-26): merge-conflict markers resolved out of
   `lsp/core/capabilities.lua`, the module loads again, warn level as a string.
   Remaining verification in a running Neovim: that with `cmp_nvim_lsp` loaded
   no warning appears any more and `caps.textDocument.completion` comes from cmp
   rather than from the fallback.
2. ✅ **B4 and B2 cleaned up** (2026-08-23): the duplicate `lspdoctor.setup`
   collapsed into one call (effective state unchanged, see the corrected B4
   row), the dead key `<leader>gtt` removed.
3. ✅ **B6 decided** (2026-08-23): a stale comment, not a real limitation — the
   platform-dependent places sit in `formatter/conform.lua` and already handle
   Windows.

Phase 0 is thereby complete — **including** the runtime verification from point
1. It ran alongside the switch into phase 2 against the real config:
`capabilities.get()` yields **0 warnings**, `snippetSupport = true` and a
`resolveSupport` with the five fields from `cmp_nvim_lsp`
(`documentation`, `additionalTextEdits`, `insertTextFormat`, `insertTextMode`,
`command`) instead of the bare fallback structure. The B1 fix therefore takes
effect in a
loaded config, not only on paper.

Side finding: the assumption "headless takes too long to load the full config"
was wrong. `nvim --headless "+qa!"` loads it in **roughly 1.0-1.2 s**. The
earlier three-minute hang came from a `vim.defer_fn` that kept Neovim alive, not
from the config. Verifications against the real config are therefore cheap —
that holds for all further phases.

### Phase 1 — scaffold

4. Build up `C:\repos\lsp.nvim`: `lua/lsp/{init,health}.lua`, `config/`,
   `bindings/`, `integrations/`, `@types/`, `doc/`, `docs/`, `.luarc.json`,
   `stylua.toml`, README skeleton — modelled on `dap.nvim`/`filetree.nvim`.

   *Done 2026-08-23.* Branch `main` (renamed from `master`, GitHub default
   switched, `origin/master` deleted), repo description and topics set.
   Created: `lua/lsp/{init,health}.lua`, `config/{init,DEFAULTS,KEYMAPS}.lua`,
   `bindings/{init,keymaps,usrcmds,autocmds,which_key}.lua`, `@types/` per
   level, `.luarc.json`, `stylua.toml`, `.luacheckrc`, `.gitattributes`,
   `.gitignore`, `scripts/gen_map.lua`, `.github/workflows/ci.yml`,
   `TESTS/smoke.lua`, `README.md`, `doc/lsp.nvim.txt`, `docs/BINDINGS.md`,
   `docs/CHECKLISTS/NEW_PROJECT.md`.

   Three deviations, all justified in the checklist record: the vimdoc is called
   `lsp.nvim.txt` instead of `lsp.txt` (Neovim's runtime already occupies the
   name), the keymap catalogue lives in `config/KEYMAPS.lua` instead of
   `DEFAULTS.lua` (§8.1), and `NEW-20`'s `--check` CI job is missing, because
   `docs/map/` is not checked in here — as in `dap.nvim` and `cascade.nvim`.

### Phase 2 — move the core (layer 1) — ✅ done 2026-08-23

5. ✅ 164 files copied, `debug_adapters/**` deliberately not.
6. ✅ Host couplings dissolved — there were fewer than expected:
   - `machine.*` had **already** been removed from `core/attach.lua` earlier
     (the comment there explains why the machine role was a poor proxy for "big
     repo"). Nothing to do.
   - `config.mason.*` moved along as `lsp/integrations/mason/` (E2), not as an
     adapter onto a host module.
   - `nvchad.*` is `pcall`-guarded in three places and stays that way for now;
     the adapter from phase 4 can clean that up later.
   - **Newly found:** `lua/@types/lsp.lua` (used only by the LSP subsystem)
     moved along as `lsp/@types/vim_lsp.lua`, and `completion/personal_names`
     no longer reaches into `plugins.personal.list` — the list is config data,
     the plugin gets it handed in via `setup({ labels = fn })`.
7. ✅ `ACTIVE` → `servers` (B7). B8 (root resolvers against `lib.nvim.fs`) is
   **not** done and stays open — a pure move was the right size here, dedup is
   a change of its own.
8. ✅ `config/DEFAULTS.lua` + `config/init.lua`: `servers`, `diagnostics`,
   `formatter`, `attach`, `mason`, `lspdoctor`, `tools`, `languages`. Every key
   is read by code; `completion`/`rename`/`integrations` from §9 are still
   deliberately missing.
9. ✅ `health.lua` extended (servers section: configured vs. set up vs.
   attached) and points at `:LspDoctor` for the buffer diagnosis instead of
   rebuilding it.
10. ✅ Switched over — with one deviation from the plan:
    `require("lsp").setup(...)` stays inside `startup.now("lsp", ...)` and does
    **not** move into an `opts` block. The step is deliberately synchronous and
    ordered (capabilities must be set globally before the first client
    attaches); `opts` would leave that ordering to the plugin manager. The spec
    is therefore `lazy = false, priority = 900` without `opts`/`config`.

    The old folder is `lua/lsp_legacy/**` — renamed, not deleted, because a
    `lua/lsp/` in the config shadows the plugin completely and the rename is the
    precondition for being able to test the rework at all. It sits on no require
    path. Throw it away as soon as a real session has confirmed the rework.

    Verified (headless, against the real config): `require("lsp")` resolves to
    `C:/repos/lsp.nvim/lua/lsp/init.lua`, all 8 servers set up, **0** setup
    warnings, `:Lsp`/`:LspDoctor`/`:LspStatus`/`:DiagQF` registered, and the two
    modules that still touch the config's own keymaps
    (`lsp.core.root_scope_picker`, `lsp.servers.marksman.hints`) resolve out of
    the plugin.

    On `autocmds/events/utils/filetype.lua`: the file no longer references
    `lsp.languages.*` at all today — the note was stale.

### Phase 3 — centralise the bindings — ✅ done 2026-08-23

11. ✅ 42 entries in `config/KEYMAPS.lua`, pulled together from five sources
    (the four named above plus the plugin's own `diagnostics/keymaps.lua`,
    which bound the same `]q`/`[q` — the catalogue lives in `config/`, not in
    `bindings/`, because it is configuration data and `bindings/keymaps.lua`
    merely executes it). Presets are name lists over **one** entry table, not
    three copies of it. The behaviour sits in `bindings/actions.lua`: an entry
    *names* an action, it does not implement one.
12. ✅ **Done 2026-08-23.** `:Lsp` now has 15 subcommands
    (`status servers info health doctor start stop restart force-restart
    recover format diag workspace root log`), the flat ~25 commands are aliases
    onto them — switchable via `usrcmds.legacy_aliases = false`, on by default,
    because muscle memory weighs more than tidiness and an alias costs one line.
    Both paths call the same functions in `bindings/actions.lua` resp.
    `lsp.usercmds.*`, so they can no longer diverge.

    Two deviations from the draft: `force-restart` is its own subcommand instead
    of a flag on `restart` (a literal after `restart` would be ambiguous with a
    server actually named "force"), and `:LspMdHints` is **not** folded in — it
    is marksman-specific, and server commands do not belong in a global verb.
    `:LspDoctor` keeps its own verb as planned and is additionally reachable as
    `:Lsp doctor`.

    Server names complete out of the **living** set — attached clients first,
    then everything from `servers` — via a dedicated composer argument type.
    That is exactly what `NEW-26` demands: a value set that changes at runtime
    must be computed at completion time; an enum frozen at registration would be
    stale as soon as a server is added.
13. ✅ `docs/BINDINGS.md` is **generated** from the catalogue by
    `scripts/gen_bindings.lua`, CI checks with `--check` — the docs can no
    longer drift. which-key deliberately labels only `<leader>x`: labels derived
    from the bound prefixes would also have called `<leader>f` (the config's
    find prefix) "LSP".
14. ✅ `bindings/mappings/{lsp,trouble}.lua` deleted and deregistered, the four
    FzfLua LSP lines removed (`<leader>fq` stays — a quickfix picker is not
    LSP), `config/inc_rename` binds no key any more but keeps its setup (the
    `post_hook` auto-save).

**New along the way, not in the plan:** `bindings/autocmds.lua` re-binds `grn`
and `grt` buffer-locally on `LspAttach`. Neovim 0.11 sets its own `gr*` maps
buffer-locally in exactly that spot, and buffer-local beats global — without
this the catalogue rename would be shadowed in precisely the buffers it is meant
for. Harmless as long as both called `vim.lsp.buf.rename`, wrong as soon as
`rename.provider` picks inc-rename. §8.1 had noted this as a requirement.

Verified against the real config: 42 keymaps bound, 0 setup warnings, and
`]q`/`[q`/`grn`/`<leader>rn`/`lsd`/`<leader>xt`/`<leader>dos`/`<leader>wq`/`]w`
all resolve to catalogue entries.

### Phase 4 — integrations (layer 2) — ✅ mostly done 2026-08-23

15. ✅ 12 adapters: nvchad, cmp, blink, lazydev, conform, trouble, inc_rename,
    picker, lspsaga, lensline, noice, mason. which-key is deliberately **not**
    one — `bindings/which_key.lua` has done that since phase 3, and a second
    place for it would be exactly the duplication the layer is meant to remove.
    workspace-diagnostics likewise not: `core/workspace_diagnostics.lua` is
    **own** code, not a wrapper around a third-party plugin.

    **The real gain is the direction of dependency.** The adapters are not
    *called* by the core — that would be exactly the layering violation that
    `scripts/gen_map.lua` declares a rule against. They hand their contributions
    to `lsp/init.lua` (which belongs to neither layer), and that passes them
    into the core as **plain functions**:

    - `core/capabilities.get(contributors)` instead of three
      `pcall(require, …)` on NvChad, cmp and blink. The order is deliberately
      preserved (NvChad first, completion engine after), because
      `tbl_deep_extend("force", …)` lets the later one win. What stays in the
      core is what is core: base capabilities, the check that anyone contributed
      completion at all, and the
      fallback — that is, exactly the check that made B1 visible in the first
      place.
    - `core/attach.build({ hooks = … })` instead of lazydev and NvChad inline.

    Consequence: `capabilities.apply_globally()` needs the contributors passed
    in and cannot look them up itself. `require("lsp").apply_capabilities()` is
    the entry point that does so; the config now calls that one.
    `:checkhealth lsp` reads the list from the registry instead of from a
    second, hand-maintained one.
16. ✅ Nothing to do — B5 was already solved, see the corrected row above.
17. ⚠️ **Only partly.** `config/mason/**` moved along in phase 2 and was
    deleted. `config/{trouble,inc_rename,copilot}` remain: they hang off the
    lazy specs in `plugins/*.lua`, and moving specs is phase 5 (§6), not this
    one. Until then the plugin configures its own behaviour and the third-party
    plugins configure theirs.

**Deliberately not built:**

- `mason.register(kind, packages)` from E2 — `dap.nvim` does not call it, and an
  API without a caller is not an API. It comes when `dap.nvim` needs it.
- The picker abstraction over telescope/snacks/pickers.nvim from §7. fzf-lua is
  still hardwired; an indirection with exactly one implementation behind it only
  obscures that the choice has not been made.

Verified against the real config: 0 setup warnings, 0 capability warnings,
`snippetSupport = true` and `resolveSupport` still carrying cmp's five
properties (the B1 regression this rework could plausibly have triggered), 8
servers, 42 keymaps, 2 `on_attach` and 1 `on_init` hook wired, and `lua_ls`
attached on a Lua buffer.

### Phase 5 — pack (layer 3) — ✅ done 2026-08-23

18. ✅ `pack/{init,core,ui,completion,completion_blink}.lua`. The plugin
    configuration moved into the adapters along the way, so that the pack really
    contains only specs: Trouble's preview/formatter/0.12 patch, lspsaga's
    option table, lensline's profile and inc-rename's post_hook (moved along
    from `config/inc_rename/` and wrapped in `configure()` — it used to run its
    `setup()` and set a global option as a side effect of the mere `require`).
19. ✅ `import = "lsp.pack"` in `init.lua`, next to the lib.nvim `dir` pin and
    for the same reason plus one: `import` makes lazy require `lsp.pack`
    **during spec collection**, so the directory has to be settled beforehand.
    `plugins/trouble.lua`, `config/trouble/` and `config/inc_rename/` deleted;
    `plugins/lsp.lua` keeps only what is genuinely config-owned (the
    personal-names completion source and the Copilot bridge).

**Correction to §6.1/§6.2 — the first draft was wrong and installed a plugin
nobody wanted.** `import` names a **directory**: lazy requires *every* module
under `lua/lsp/pack/` and treats every result as a spec list. A `pack/init.lua`
that returns conditional `{ import = "lsp.pack.completion" }` entries therefore
gates **nothing** — the siblings are imported anyway, it would only read them a
second time. On the first test run blink.cmp was consequently cloned into the
config (removed again). Consequences:

- Selection happens per spec via `enabled`, read from `lsp.config.pack`.
- The helper had to move **out of** `pack/`, because a module there would be
  read as a spec. It lives in `config/pack.lua` — which is more coherent
  anyway, since it reads configuration.
- `pack/init.lua` returns `{}` and records this restriction.

The two-channel split from §6.2 (`vim.g` = *whether*, `opts` = *how*) holds
unchanged — only the mechanism behind it is a different one than assumed.

**Side finding:** the Trouble 0.12 patch overwrote
`TSHighlighter._on_win`/`_on_line` **unconditionally**. On a Neovim that still
has them, it replaced working methods with the identically named fallbacks. Now
with a guard — §7 had demanded exactly that ("with a version guard instead of
unconditionally").

Verified against the real config: all seven pack plugins in the spec, blink
correctly absent, 8 servers, 42 keymaps, 0 warnings, and the configuration
really applied (Trouble's preview on the right with the index formatter,
`inccommand=split`, `:IncRename` registered, lspsaga configured).

### Phase 6 — wrap-up

20. ✅ **Done 2026-08-23** — as a port, not as a move; see §4.
21. Finalise `docs/**`, `doc/lsp.txt`, README, ROADMAP; `gh repo edit`
    (description, topics), commit & push.
    (Branch `main` has been done since 2026-08-23 — see phase 1.)
22. Set this roadmap entry to "complete", create a memory note analogous to
    `lib-nvim-extraction.md`.

---

## 14. Roadmap: new features

For the new plugin's `docs/ROADMAP.md` — not everything to be implemented at
once:

| Feature | Benefit | Effort |
|---|---|---|
| **Inlay-hints toggle** (`vim.lsp.inlay_hint`, global + per filetype) | Referenced nowhere in `lua/lsp/`, although native since Neovim 0.10 | small |
| **Code-action indicator** (sign/virtual text when `textDocument/codeAction` returns something) | Visibility without a blind `lsa` | medium |
| **`:Lsp log`** | ✅ **DONE (2026-08-23)** — `:Lsp log open` opens the file in a split, `:Lsp log level` switches the level, with completion over the closed set. No dedicated tail renderer: the log *is* a file, and a split on it can do everything a scratch buffer could, plus `:e` |
| **Auto-restart with backoff** on client crash | `core/attach.lua` has no crash handling | medium |
| **Formatter priority audit** | `lspdoctor` has `formatter_priority` + `show_conflicts` — unclear whether that is enforced in `formatter/conform.lua` | small (audit) |
| **Workspace-symbol / call-hierarchy picker** via the `picker` adapter | Consistent picker UI instead of ad-hoc telescope in `ts_type_lookup` | medium |
| **Per-project override** (`.nvim-lsp.json` in the repo root) | Disable server X in project Y without a global config change | medium-large |
| **Multi-root/monorepo workspace switcher** as its own feature | Formalises what half exists in `root_scope_picker` | small |
| **Hover cache** via `lib.lua.memo` | Repeated hover on the same position/version saves a roundtrip | small |
| **Jump to the Lua table/function root** (formerly `<leader>gtt`) | Rescued from B2: jump from a deeply nested Lua table to the head of the enclosing structure, optionally centred. The key was mapped for years onto a module that never existed — so the feature was wanted, just never built | medium |
| **Diagnostics debounce** on `publishDiagnostics` | `core/handlers.lua` deduplicates but does not debounce (chatty servers like `ts_ls`) | small |
| **Test entry point** (`tools/_test`) | ✅ **DONE (2026-08-23)** — as `TESTS/lsp/*_spec.lua` on plenary's busted harness (like `dap.nvim`), not as `tools/_test`: the location from the concept would have hung the tests under *one* tool, while they belong to the whole plugin. 124 specs across config normalisation, the keymap catalogue, the capabilities chain, the adapter registry, pack gating, the `:Lsp` routes and the server registry — that is, exactly the places this migration's bugs came from. Alongside that, `TESTS/smoke.lua` remains as an end-to-end run. |
| **Make the plugin's own completion sources engine-neutral + frequency ranking** | ✅ **DONE (2026-08-24)** — `lsp.completion.usage` (shared counter), `lsp.completion.register` (registrar) and `lsp.completion.blink` (adapter); neither source knows its engine any more, and `md_words` has the ranking. Details and the three findings from building it are in §16 |
| **Shrink the signature-help module** | `tools/lsp_signature/**` is a complete homegrown implementation (~800 LOC) | large (just observe for now) |
| **Keymap collision checker** in `:checkhealth lsp` | Half done: `keymaps_spec.lua` checks that no two catalogue entries claim the same key in the same mode — at build time, where a mistake costs nothing. What stays open is the runtime question only `:checkhealth` can see: does the catalogue collide with a key *you* or another plugin have set | small |
| **Profile presets** (`preset = "lean"\|"default"\|"full"`) | One switch instead of 20 individual options for "lean on a weak machine" | medium |

---

## 15. Decisions & open questions

### Decided (2026-07-26)

| # | Question | Decision |
|---|---|---|
| E1 | **Dependency model** | Hard dependencies are wanted **by design**. Rebuilding third-party plugins buys nothing. `pcall` stays as blast-radius containment, not as a promise of optionality. → §3 |
| E2 | **Mason responsibility** | `ensure_install` moves **completely into `lsp.nvim`** (`integrations/mason/`), not into `lib.nvim`. `dap.nvim` announces its DAP packages via `register("dap", …)`. → §4 |
| E3 | **Keymap preset** (B10) | The `ls*` assignment **stays**. The Neovim 0.11 defaults (`grr`/`gri`/`grn`/`grt`/`gO`) keep running buffer-locally in parallel — no conflict. → §8.1 |
| E4 | **B1 (merge conflict in `capabilities.lua`)** | **Done**, fixed in the host before the migration. |

### From the NEW_PROJECT walkthrough (2026-08-23)

- **The module root `lsp` shadows itself.** As long as the config has its own
  `lua/lsp/**`, it wins on the `runtimepath` and `require("lsp")` lands there,
  not in the plugin. The first test run did exactly that and silently checked
  the wrong code. That is not an argument against the naming from §5 — the
  advantage (all `require("lsp.…")` paths stay valid) is the same — but it is a
  condition that was missing there: **deleting the config folder and installing
  the plugin have to be the same step.** A transitional state of "both present"
  is not neutral, it is invisibly broken. For phase 2 (§13, step 10) that means:
  the order envisaged there — "switch over first, delete the old folder later
  once tested" — does not work that way; testing is only possible *after* the
  deletion. Proposal: rename the config folder to `lua/lsp_legacy/**` instead of
  deleting it, then switch over, test, and only throw it away afterwards.
- **`doc/lsp.txt` is taken.** Neovim's runtime ships one itself (`:h lsp`). The
  vimdoc is therefore called `doc/lsp.nvim.txt`, all tags are prefixed
  `lsp.nvim-…`, `*lsp*` stays untouched. §5 still says `doc/lsp.txt`.
- **`NEW-20` contradicts the more recent map decision.** The gate demands
  `scripts/gen_map.lua` **plus** `--check` in CI; but `--check` compares
  byte-exactly against a **checked-in** map (see
  `documentation.nvim/docs/REUSE.md`), and that has deliberately not been
  committed since `dap.nvim`/`cascade.nvim`. The two cannot both hold —
  confirmed when re-checking on 2026-08-23: `documentation.nvim` itself is the
  only exception (3 files committed, dogfooding, ~3 MB), while `docmap-desktop`,
  `dap.nvim`, `cascade.nvim`, `gopath.nvim` and `lsp.nvim` all have `docs/map/`
  gitignored. This belongs decided in the gate, not silently resolved per repo
  in one direction.

  **Adopted into the gate on 2026-08-24** (`WKDBooks` commit `10b03c4`):
  `NEW-20` now demands "adopt `gen_map.lua` per REUSE.md; `docs/map/`
  is not committed except in `documentation.nvim` and `docmap-desktop`
  (dogfooding); `--check` in CI only where the map is committed". Also recorded:
  at that point `--check` ran in **none** of the five existing repos, not even
  in `documentation.nvim`, where it would have worked.
- **The gate names two stale paths**: `e:\repos\` in `NEW-01`,
  `C:\Users\bartl\…` in `NEW-35`.

- **The checklist ages faster than the code.** On the first pass the repo was a
  scaffold, and close to a third of the items were answered with "still empty"
  or "not applicable yet" — `NEW-15` (no keymaps), `NEW-21` (empty catalogue),
  `NEW-25` (no count, because there was no key), `NEW-29`. After the migration
  none of that held any more: the record described a repo that no longer exists.
  For the next extraction: an item whose answer is "does not exist yet" is
  **not ticked off, it is deferred**, and belongs on a list that comes up again
  at the end of the migration.
- **`NEW-25` was exactly such an item** and is done. `v:count1` applies to the
  eight motion keys (`]d`/`[d`, `]q`/`[q`, `]l`/`[l`, `]w`/`[w`); `3]q` jumps
  three quickfix entries. Not via a loop: `:{count}cnext` and
  `vim.diagnostic.jump({ count = N })` can do it natively, fire the autocommands
  once instead of N times, and run as far as they get instead of stopping at the
  first `E553`. The leader-prefixed actions get none — filling a list or
  toggling a setting has no ordered target for a count to index into.
- **A linter sees what a reviewer reads past.** `steps()` sat as a `local`
  *below* the closure that calls it — in Lua the name is a global there, i.e.
  `nil`. It reads perfectly right and runs into a wall. The specs did not find
  it, because trouble.nvim is missing in the test run and the function returns
  earlier at the `pcall(require, ...)`; luacheck saw it immediately. That is why
  the lint invocation now stands in `TESTS/README.md` next to the suite.

### Decided (2026-08-23, second pass)

- **Trouble as the default sink for `]d`/`[d`: yes, implemented 2026-08-24.**
  Anything else would mean rebuilding half the plugin — Trouble brings a lot
  along, and most users reach for it anyway. `diagnostics.ui`
  (`"auto"|"native"|"trouble"`, default `"auto"`) decides; `"trouble"` and
  `"auto"` behave identically at runtime as long as Trouble is installed. Not
  part of `vim.diagnostic.config()` — `lsp/init.lua` removes the field before it
  goes there, otherwise the native API would get a key it does not know.

  Deliberately more than one config line: `]d`/`[d` should behave exactly like
  Trouble's own `next`/`prev` (the panel opens, focus switches) — the obvious
  implementation would have been to call Trouble's public `next(opts)`/`prev(opts)`
  wrappers. Those read `vim.v.count1` **themselves**, though, inside the action.
  The already existing code for `]w`/`[w` (`trouble_move`) called exactly those
  wrappers in a loop over `steps(count)` — on `3]w`, `steps` resolved from
  `v:count1` (=3), and each of the 3 loop iterations read the same, not yet
  consumed `v:count1` again: net 3×3=9 movements instead of 3. A real,
  already-shipped bug, found while reading Trouble's own source for this
  feature — fixed by calling `view:move({down/up=n, jump=true})` directly (the
  same primitive Trouble's `next`/`prev` use internally) instead of going
  through the counting wrapper. `]w`/`[w` keep their semantics unchanged (they
  only move within an already open list) but are affected by the same fix.

  `view:move()` needs an already mounted window; Trouble mounts it
  asynchronously, though, in a promise callback (`view:refresh({opening=true})
  :next(...)`), not synchronously inside `trouble.open()`. That is why the
  plugin's own move call also goes through `view:wait(fn)` — the same deferral
  `trouble.next()`/`.prev()` use internally.
- **Completion engine: `blink` has been the plugin default since 2026-08-24**
  (`lua/lsp/config/pack.lua`), after a real live test of both engines. Both
  adapters have existed since phase 5 and have been genuinely switchable via
  `vim.g.lsp_nvim.pack.completion = "cmp"|"blink"` since 2026-08-23 — before
  that blink was only a commented-out block in `plugins/lsp.lua`, never actually
  reachable. The config tested it via an override at first; the override has
  been removed again since blink became the actual default.

  The first real test run found a bug immediately: `lsp.integrations.cmp` warned
  unconditionally "nvim-cmp not found!", even when blink had deliberately been
  chosen — a leftover from the time when cmp was the only engine.
  `lsp.integrations.blink` was already symmetric (silent when absent);
  `cmp.lua` is now too. `core.capabilities.get()` keeps its own aggregate
  warning for when really **no** contributor supplies completion capabilities —
  that is where B1 (the silently degraded completion from the original config)
  stays caught. Fixed in `lsp.nvim` (commit `ba4ecb8`).

  The gap mentioned — `personal_names` had no blink counterpart — is closed with
  §16 (see there): both sources have run through `lsp.completion.register` under
  both engines since 2026-08-24.
### Settled by what was built (2026-08-23 / 2026-08-24)

The following points stood under "Open" until just now and no longer do — not
because they were decided, but because the code answers the question:

| # | Question | How it turned out |
|---|---|---|
| 3 | **Module root `lsp`** | Kept. All `require("lsp.…")` paths stayed valid; the collision from the `dap.nvim` case did not occur. The real pitfall was a different one and stands above: as long as the config has its own `lua/lsp/**`, it wins on the `runtimepath` |
| 4 | **Windows formatter** (B6) | Was never a limitation, only a stale header comment. `formatter/conform.lua` has always branched on the PATH separator, the `.cmd` suffix and the Mason bin path |
| 5 | **`lspdoctor` vs. `:checkhealth`** | They cannot diverge: both read `require("lsp").status()`, there is no second place where the plugin describes itself. `:checkhealth` points at `:LspDoctor` for the buffer level instead of repeating it |
| 6 | **`dap.nvim` ↔ `lsp.nvim`** | As proposed: `integrations/mason/` accepts registrations, `dap.nvim` registers pcall-guarded and stays runnable standalone |
| 7 | **Scope of phase 1** | As proposed: the pack only in phase 5. That paid off — the first pack draft installed blink.cmp into the config, because lazy's `import` reads a *directory* and the conditional imports shielded nothing. In phase 1 this mistake would have blocked the core migration |
| 3 (NEW-20) | **gen_map `--check` against a non-committed map** | Not a repo decision, as first assumed, but a gap in the gate itself — confirmed across all five existing repos (see above) and fixed there on 2026-08-24 |

---

## 16. The plugin's own completion sources: engine-neutral + frequency ranking

**Status: done 2026-08-24.** Recorded 2026-08-23 out of two observations during
the blink test, built a day later. The section stays because building it found
three things the draft below did not anticipate.

### The finding

There were exactly two hand-written completion sources, both **cmp-only**:

| Source | What it supplies | Frequency ranking? |
|---|---|---|
| `lsp.completion.personal_names` | the ~30 dotted `*.nvim` plugin names, each as *one* candidate | **yes** — a persistent counter in `stdpath("state")/personal_names_usage.json`, encoded as a zero-padded `sortText` rank |
| `lsp.languages.documentation.markdown_words` | the project-wide word dictionary for markdown | **no** — `table.sort` purely alphabetical (`words_to_items`) |

Both hung off `cmp.register_source` and warned when nvim-cmp was missing. Under
blink that was the message that triggered this item in the first place:
`[md_words] nvim-cmp not found – source will not appear in completions.`

The desired feature — "frequently used suggestions further up" — therefore did
**not** need inventing, only extracting from `personal_names` and applying to
`markdown_words`.

### What was built

| File | Role |
|---|---|
| `lua/lsp/completion/usage.lua` | the persistent counter, pulled out of `personal_names`: `bump`/`count`/`ranked` plus the `sortText` encoding. One file (`stdpath("state")/lsp_completion_usage.json`), two top-level namespaces — the question left open below, decided that way. The old `personal_names_usage.json` is folded in once on first load, otherwise counters collected over months would silently be gone |
| `lua/lsp/completion/register.lua` | the registrar. A source passes `{ name, items, namespace?, filetypes?, keyword_pattern?, on_pick? }` and never learns which engine won |
| `lua/lsp/completion/blink.lua` | the blink provider that serves a registered spec. blink resolves providers via a `module` path and cannot be given a closure — that is why `opts.source` carries the name and the spec is looked up at request time |
| `lua/lsp/pack/completion_blink.lua` | declares both sources as providers; `md_words` via `per_filetype` with `inherit_defaults` instead of globally |
| `TESTS/lsp/completion_spec.lua` | 19 specs on the seam: ranking engine-independent, namespaces sealed, a pick is counted no matter which engine reports it |

The options live under `completion.personal_names` (`enable`, `labels`), and
`labels` is a *reader*, not a list: the plugin names are data of the host config,
which passes them in, rather than this plugin reaching into `plugins.personal`.

### Three findings from building it

1. **The registration must not sit in the engine spec.** `personal_names` was
   called out of nvim-cmp's `opts` function — which never runs under blink.
   Result on the first live test: `sources = {}`, the source was still absent
   under blink even though the whole registrar had been built for it. The call
   belongs in `lsp.setup()`, i.e. where no engine can see it.
2. **A pick must not rebuild the dictionary.** The first attempt set
   `items = nil` after every accepted word. That triggered a complete project
   rescan — file I/O per word, and because a running rebuild returns nothing,
   the menu would have been empty right after the pick. After that it only
   re-sorted instead of re-scanning: measured **31 ms per word** for 24,703
   entries, still too expensive. Now only the labels *with* a counter get a rank
   stamped, in place: **0.003 ms**.
3. **A missing `sortText` means "no opinion", not "all the way to the back".**
   Both engines skip the pair and hand it to the next comparator
   (`blink/cmp/fuzzy/sort.lua:35`, `cmp/config/compare.lua:97`). The obvious
   saving — giving unused items no `sortText` at all — would therefore have lost
   exactly the property the module exists for. Unused items therefore carry
   `"~" .. label`: alphabetical among themselves, behind every rank, and behind
   what an LSP server typically sends.

### What made the port easy

Checked against the installed blink.cmp v1.x, not assumed:

- **`sortText` works identically in both engines.** blink's default is
  `fuzzy.sorts = { "score", "sort_text" }` (`lua/blink/cmp/config/fuzzy.lua`),
  cmp's default chain contains `compare.sort_text`. The ranking mechanics are
  therefore **engine-neutral** — only registration and the accept hook differ.
- **blink's accept hook is cleaner than cmp's.** A blink source implements
  `execute(ctx, item, callback, default)` on its own item; cmp needs the global
  `cmp.event:on("confirm_done")` with filtering on the source name.
- **The item structure is the same** (`label`/`kind`/`filterText`/`insertText`/
  `sortText`) — blink takes LSP `CompletionItem`s exactly like cmp.

### The open questions, answered

- **One file or two?** One, with two top-level keys — the tendency from the
  draft, and the namespaces are not optional: a markdown word and a plugin name
  can be identical, and a shared counter would let writing prose re-sort the
  plugin list.
- **Is `personal_names` needed under blink at all?** Yes. Measured before the
  port, as the draft demands: blink's fuzzy matcher likewise does not get from
  "do" to "documentation.nvim".

---

## From `MyPlugin-Notes/LSPDoctor/` (analysis 2026-08-08)

Source: `MyPlugin-Notes/LSPDoctor/{lspdoctor,lsprelive}.md` — **no longer
exists**: under `C:\repos\Notes\MyPlugin-Notes\` there are today only
`README-TEMPLATES/`, `_archive/`, `cmdlog/` and `nvim_cfg_patches/`. The content
relevant to `lsp.nvim` is recorded below, the original is gone.

**Finding: the note is outdated.** It sketches a ~30-line `M.check()` (Mason
there? LSP attached? diagnostics present? trouble loaded?). The real state is
`lspdoctor/**` with 948 lines and five modes
(`:LspDoctor {health,debug,quick,deep,all}`) — see §11 of this document.

Kept because it contains two things that are not yet in the concept:

### 1. The "installed vs. attached" metric

`lsprelive.md` records why the common worry is unfounded: an installed server
costs nothing as long as it is attached to no buffer. It only gets expensive
with "many large buffers × a heavy server" (tsserver, pyright).

- [ ] Output as a line in the `:checkhealth lsp` report: *installed: N,
      currently attached: M, of those in this buffer: K* — plus a warning only
      when a known-heavy server hangs over many buffers.

That answers the question one actually asks, instead of merely listing.

**Effort:** quick win
**Benefit:** medium.

### 2. Provoking errors as a testing aid

The note contains deliberately broken snippets (Go: a missing brace, JS:
`const x =`) to check whether diagnostics arrive at all.

- [ ] Adopt into the test suite resp. into `:LspDoctor deep`: create a scratch
      buffer with guaranteed-faulty content and check whether diagnostics arrive
      within a timeout. That distinguishes "no errors" from "diagnostics do not
      arrive at all" — exactly the case that otherwise costs hours.

**Effort:** medium
**Benefit:** high — the only check that verifies the chain end-to-end instead of
just querying states.
