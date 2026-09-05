# The full autocommand inventory

`lua/lsp/bindings/autocmds.lua`'s own doc comment says "One group, `lsp_nvim`"
and names only the formatter as an exception. That understates it: this
plugin registers **33 autocommands across 25 augroups**, spread over
`bindings/`, `core/`, `formatter/`, `languages/`, `tools/`, `servers/` and
`integrations/`. [BINDINGS.md](BINDINGS.md#autocommands) covers only the four
groups that back the keymap/rename layer; this page is the complete list.

Counted are call sites (`autocmd.create` / `nvim_create_autocmd`), not event
registrations — the lightbulb watcher listens on four events from one call
site, and counts once here. Verified against source on 2026-09-05: still 33
call sites.

25 groups = 20 named string literals + `lsp_nvim`, `lsp_nvim_inlay_hints`,
`lsp_nvim_lightbulb`, `lsp_nvim_supervisor` (built from `M.GROUP` constants)
+ `LspSignaturePopup_<winid>`, whose name is built at runtime — a grep for
the literal string finds the first 20 and none of the last 5.

## Core

| Augroup (`clear=true`) | Event | Pattern | Condition | Action |
| --- | --- | --- | --- | --- |
| `lsp_nvim` | `LspAttach` | — | `cfg.keymaps.enable` | Re-binds the catalogue's `rename` and `goto_type_definition_gr` buffer-locally |
| `lsp_nvim_inlay_hints` | `LspAttach` | — | `vim.lsp.inlay_hint` exists | Applies the resolved hint state (global + filetype override) to the freshly attached buffer, `vim.schedule`d because the buffer's filetype is not reliably set yet at `LspAttach` on a session's very first attach |
| `lsp_nvim_lightbulb` | `CursorMoved`, `BufEnter`, `InsertLeave`, `DiagnosticChanged` | — | — | Asks `textDocument/codeAction` for the cursor position, debounced (`lightbulb.debounce_ms`, default 150ms), marks the line on a hit |
| `lsp_nvim_lightbulb` | `InsertEnter` | — | — | Clears the mark, **without** debounce — hiding is never what rate-limiting is for |
| `lsp_nvim_lightbulb` | `LspAttach` | — | — | Asks once as soon as a client is there |
| `lsp_nvim_supervisor` | `LspAttach` | — | — | Records server name, buffer and start time per client id |
| `lsp_nvim_supervisor` | `VimLeavePre` | — | — | Sets the flag that keeps client exits during `:qa` from counting as crashes |

`lsp_nvim_inlay_hints` and `lsp_nvim_lightbulb` are their own groups rather
than folded into `lsp_nvim` because that group is cleared whenever
`keymaps.enable = false` — hints and the lightbulb are not a keymap concern
and must not disappear with the keymaps.

**Why the supervisor bookkeeps at attach at all:** the actual trigger is not
an autocommand but `on_exit` from the `vim.lsp.config("*")` setup, which only
receives `code`, `signal` and a client id — at a point where the client is
already tearing down. Without these two entries the handler would not know
which server died or which buffer it belonged to. `on_exit` also runs in the
fast-event context (confirmed on 0.12.2: `vim.in_fast_event()` is `true`
inside it), so it only collects there and decides via `vim.schedule` on the
main loop.

## Formatter

| Augroup (`clear=true`) | Event | Condition | Action |
| --- | --- | --- | --- |
| `LspFormatOnSave` | `BufWritePre` | `STATE.enabled` and `buftype == ""` | Synchronous format-on-save with view preservation |

The toggle (`:Lsp format on/off/toggle`, `<leader>tft`) deletes and
re-registers rather than checking a flag —
`create_autocmd_if_enabled()` clears the group first, so when it is off there
is no autocommand at all, not one that does nothing. Synchronous, not async,
so the view restore stays deterministic inside the write chain. Registered
via the raw API, not `lib.nvim.bindings.autocmd`.

## Languages

| Augroup (`clear=true`) | Event | Pattern | Action |
| --- | --- | --- | --- |
| `LangCs` | `FileType` | `cs` | No-op stub |
| `LangLua` | `FileType` | `lua` | No-op stub |
| `LangC` | `FileType` | `c`, `cpp` | No-op stub |
| `LangGo` | `FileType` | `go` | No-op stub |
| `LangZig` | `FileType` | `zig` | No-op stub |
| `LangDart` | `FileType` | `dart` | Buffer-local "Flutter: Hot Reload" keymap |
| `LangJava` | `FileType` | `java` | Sets buffer options; registers a `BufWritePre` **nested inside** the callback |
| `LangHtml` | `FileType` | `html`, `htmldjango`, `djangohtml` | HTML buffer options |
| `LangTs` | `BufWritePre` | `*.ts`, `*.tsx`, `*.js`, `*.jsx` | TypeScript on-save action |
| `LangMarkdownQoL` | `FileType` | `markdown`, `mdx` | UTF-8, soft defaults, buffer-local format keymap |

The five no-op stubs are deliberate, not an oversight — `go.lua` says so
itself: "registers the `go` FileType group but the callback is a no-op, the
same stub shape as c.lua/zig.lua next to it." Placeholders for future QoL
additions; they are the only autocommands in the plugin without a `desc`.
`LangJava` is the one case of an autocommand registered *inside* another
autocommand's callback (`FileType` registers a `BufWritePre` when it fires).

## Markdown word completion (`markdown_words`)

| Augroup (`clear=true`) | Event | Pattern | Action |
| --- | --- | --- | --- |
| `MdWordsCompletionSource` | `FileType` | `markdown`, `mdx` | Registers the completion source on the first markdown buffer |
| `MdWordsInitialScan` | `FileType` | `markdown`, `mdx` | Initial word-cache build on the first markdown buffer opened |
| `MdWordsDirChanged` | `DirChanged` | — | Debounced rebuild on a cwd change |

The first two are deliberately separate groups rather than two handlers in
one: same event/pattern, different lifetimes (the scan uses `once`).

## Astro

| Augroup (`clear=true`) | Event | Pattern | Action |
| --- | --- | --- | --- |
| `AstroQoL` | `BufWritePre` | `*.astro` | Format on save |
| `AstroQoL` | `BufWritePre` | `*.astro` | Organize imports on save |
| `AstroQoL` | `FileType` | `astro` | Astro buffer options |
| `AstroQoL` | `FileType` | `astro` | Astro's own syntax highlighting |
| `LangAstro` | `FileType` | `astro` | Astro keymaps, autotag fallback, `commentstring` + 2-space indent |

`AstroQoL` is four handlers in one group — the clean counter-example to the
one-group-per-concern pattern above.

## Tools and servers

| Augroup (`clear=true`) | Event | Condition | Action |
| --- | --- | --- | --- |
| `MasonEslintPrettier` | `BufWritePre` | `ctx._enabled` and filetype ∈ js/jsx/ts/tsx/vue/svelte | ESLint/Prettier on save |
| `ToolsNoiceIntegration` | `BufWinEnter` | Buffer is a Noice preview | Installs type-lookup keymaps in the preview |
| `LspSignaturePopup_<winid>` (per window) | `BufWipeout`, `BufHidden`, `BufLeave`, `WinClosed` | `once = true`, buffer-local | Closes the signature popup and **deletes its own augroup** |
| `LspLuaLsRootScope` | `User LspRootScopeChanged` | — | Recomputes `root_dir` for open buffers |

`LspSignaturePopup_<winid>` is the one per-window-augroup pattern, deleting
itself via `nvim_del_augroup_by_id` — otherwise every popup opened would
leave a group behind. `ToolsNoiceIntegration` is registered at module level
(not inside a `setup()` function), so it fires as soon as the module is
required.

## Breadcrumb depth (`integrations/lspsaga.lua`)

| Augroup (`clear=true`) | Event | Pattern | Condition | Action |
| --- | --- | --- | --- | --- |
| `LspNvimSagaWinbarDepth` | `CursorMoved` | — | Filetype has a depth limit | Trims the winbar lspsaga wrote to path + N symbols |
| `LspNvimSagaWinbarDepth` | `User` | `SagaSymbolUpdate` | same | same, after a fresh symbol response |

Registered from `M.configure()`, which the plugin spec calls on
`event = "LspAttach"` when lspsaga loads — without lspsaga installed, the
group never exists. Two call sites, two events, one group.

**Why an autocommand and not an option:** lspsaga has no depth limit of its
own. `find_in_node` descends into every child containing the cursor line, and
marksman returns Markdown headings as a nested outline, so the cursor can sit
inside three symbols at once and the winbar reads
`folder > file > H1 > H2 > H3`. `ignore_patterns`, the only related switch,
matches on the buffer name and would take the folder and filename with it —
so this trims what lspsaga already wrote instead.

**Why `vim.schedule` and not autocommand ordering:** lspsaga installs its own
per-buffer `CursorMoved` handler at `LspAttach` time. An autocommand
registered here at `config` time cannot rely on running after it, so
deferring to the event loop makes it order-independent. Cost on the hot
path: the callback exits after one table lookup when the filetype has no
limit (i.e. for everything but markdown); the trim itself only runs inside
`vim.schedule`.

Fixed 2026-09-02 (lsp.nvim `ab79a0b`): this pair used to be the one exception
to "every autocommand in this plugin goes through
`lib.nvim.bindings.autocmd`" — introduced on the raw API by `fa6d97a`, caught
and corrected the same day. It is on `lib.nvim.bindings.autocmd` now, same as
every other group in this file except the formatter's (see below).

## Two autocommands that used to stack

Both had **no augroup at all**, for the same reason: their `setup()`/
`enable()` has no idempotency guard and runs again on every config reload.
The user commands next to them survive that because `usercmd.create` sets
`force = true`; a groupless autocommand has no equivalent and simply stacks.
Measured before and after, not just read:

| Affected | Before | After | Consequence of the bug |
| --- | --- | --- | --- |
| `servers/lua_ls/reload.lua` → now `LspLuaLsRootScope` | 1 → 2 → 3 | constant 1 | N × `recompute_root()` per scope change |
| `languages/webdev/astro/init.lua` → now `LangAstro` | 1 → 2 → 3 | constant 1 | N × keymap attach + buffer options per Astro buffer |

The Astro case shows how it happened: the line
`-- local grp = api.nvim_create_augroup("LangAstro", ...)` was commented out,
but the autocommand next to it stayed — so `LangAstro` appeared in the name
list without the group ever existing at runtime.

## Raw API vs. `lib.nvim.bindings.autocmd`

All autocommands in this plugin go through `lib.nvim.bindings.autocmd`
**except** the formatter's, which uses the raw API
(`lua/lsp/formatter/init.lua`). Functionally identical — `autocmd.group`/
`autocmd.create` wrap the same two API calls and add the registry entry that
`:checkhealth` and the generated bindings pages read — but it is worth
tracking because the inconsistency is exactly where two groupless
autocommands (above) went unnoticed for a while, and where the lspsaga pair
briefly slipped onto the raw API (also above) before this page's own count
caught it.

## Changelog

- 2026-09-02: `LspNvimSagaWinbarDepth` moved onto `lib.nvim.bindings.autocmd`
  (`ab79a0b`) after having briefly landed on the raw API (`fa6d97a`) — this
  page's "everything goes through lib.nvim" claim was false for one commit.
- 2026-09-02: `LspNvimSagaWinbarDepth` added (two call sites, two events).
  33 call sites across 25 groups.
- 2026-08-30: `lsp_nvim_supervisor` added (two call sites, two events). 31
  across 24.
- 2026-08-30: `lsp_nvim_lightbulb` added (three call sites, six events). 29
  across 23.
- 2026-08-25: this inventory built from scratch during the plugin sweep —
  lsp.nvim was the one personal plugin with no autocommand page at all, and
  its own docstring undercounts to this day (see the note at the top of
  [BINDINGS.md](BINDINGS.md#autocommands)).
