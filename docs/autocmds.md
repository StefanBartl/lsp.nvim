# The full autocommand inventory

`lua/lsp/bindings/autocmds.lua`'s own doc comment says "One group, `lsp_nvim`"
and names only the formatter as an exception. That understates it: this
plugin registers **34 autocommands across 25 augroups**, spread over
`bindings/`, `core/`, `formatter/`, `languages/`, `tools/`, `servers/` and
`integrations/`. [BINDINGS.md](BINDINGS.md#autocommands) covers only the four
groups that back the keymap/rename layer; this page is the complete list.

Counted are call sites (`autocmd.create` / `nvim_create_autocmd`), not event
registrations — the lightbulb watcher listens on four events from one call
site, and counts once here. Verified against source on 2026-09-18: 34 call
sites, up one from the 33 this page carried, because `markdown.lua` grew a
`ColorScheme` handler on 2026-09-17. Counted two ways and they agree — 34
call sites in source, against 30 records in `lib.nvim.bindings.autocmd`'s own
registry after a bare `setup({ formatter = { on_save = true } })`, which is
the same number once the four that cannot be there are taken out (the two
lspsaga ones, with lspsaga not installed; the per-window signature popup,
created only when one opens; and `LangJava`'s nested `BufWritePre`, created
only when a Java buffer does).

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
so the view restore stays deterministic inside the write chain. The
autocommand itself goes through `lib.nvim.bindings.autocmd` like every other
one in the plugin — this page said "registered via the raw API" long after
that stopped being true; what is still raw here is the *augroup*
(`nvim_create_augroup`) and the clear (`nvim_clear_autocmds`). See below for
what that costs.

## Languages

| Augroup (`clear=true`) | Event | Pattern | Action |
| --- | --- | --- | --- |
| `LangDart` | `FileType` | `dart` | Buffer-local "Flutter: Hot Reload" keymap |
| `LangJava` | `FileType` | `java` | Sets buffer options; registers a buffer-local `BufWritePre` **nested inside** the callback, in the same group and guarded so one buffer never collects two |
| `LangHtml` | `FileType` | `html`, `htmldjango`, `djangohtml` | HTML buffer options |
| `LangTs` | `BufWritePre` | `*.ts`, `*.tsx`, `*.js`, `*.jsx` | TypeScript on-save action |
| `LangMarkdownQoL` | `FileType` | `markdown`, `mdx` | UTF-8, soft defaults, buffer-local format keymap |
| `LangMarkdownQoL` | `ColorScheme` | `*` | Re-applies the three `LspReference*` highlight groups. Added 2026-09-17; it used to run inside the `FileType` callback, where opening a markdown buffer restyled references in every other buffer too |

The five no-op stubs this table used to list (`LangCs`, `LangLua`, `LangC`,
`LangGo`, `LangZig`) were removed on 2026-09-21. They registered a `FileType`
autocommand whose callback did nothing, as "placeholders for future QoL
additions", and none ever got any: `enable_all()` walked five modules to install
six autocommands that never changed a buffer. A language gets a module here when
it has QoL to install, and not before. The servers for those languages are
unaffected -- they come from `lsp.servers.*`.

Not every autocommand here carries a `desc`: `nvim_get_autocmds` reports an empty
`desc` for every registration in `LangDart`, `LangHtml`, `LangJava`, `LangTs`,
`MasonEslintPrettier` and `ToolsNoiceIntegration`. That is 18 of the plugin's
live autocommands -- the earlier figure of 24 included the six stub
registrations.

`LangJava` is the one case of an autocommand registered *inside* another
autocommand's callback (`FileType` registers a `BufWritePre` when it fires).
Since 2026-09-17 that nested one is in `LangJava` too, and guarded by an
`nvim_get_autocmds` lookup for the same event/group/buffer, so re-reading the
file does not stack a second copy on the buffer — it used to be groupless,
which both stacked and put it out of reach of the group's `clear`.

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
| `MasonEslintPrettier` | `BufWritePost` | pattern `*.{js,cjs,mjs,jsx,ts,tsx,vue,svelte}`, plus `ctx._enabled` and filetype ∈ js/jsx/ts/tsx/vue/svelte checked in the callback | ESLint/Prettier on save |
| `ToolsNoiceIntegration` | `BufWinEnter` | Buffer is a Noice preview | Installs type-lookup keymaps in the preview |
| `LspSignaturePopup_<winid>` (per window) | `BufWipeout`, `BufHidden`, `BufLeave` | `once = true`, buffer-local | Closes the signature popup and **deletes its own augroup** |
| `LspLuaLsRootScope` | `User LspRootScopeChanged` | — | Recomputes `root_dir` for open buffers |

`LspSignaturePopup_<winid>` is the one per-window-augroup pattern, deleting
itself via `nvim_del_augroup_by_id` — otherwise every popup opened would
leave a group behind. `WinClosed` was in that event list on this page and in
the code until 2026-09-17, and could never have fired: the registration is
buffer-local, so it compiles to pattern `<buffer=N>`, and `WinClosed`'s
pattern is a *window id*, which no `<buffer=N>` matches. Nothing was lost by
dropping it — the popup buffer is `bufhidden=wipe`, so closing the window
raises `BufWipeout`, which is the event that actually deletes the group.

`ToolsNoiceIntegration` is registered at module level (not inside a `setup()`
function), so it fires as soon as the module is required.

## Breadcrumb depth and chips (`integrations/lspsaga.lua`)

| Augroup (`clear=true`) | Event | Pattern | Condition | Action |
| --- | --- | --- | --- | --- |
| `LspNvimSagaWinbarDepth` | `CursorMoved` | — | Filetype has a depth limit, or chips are on | Trims the winbar lspsaga wrote to path + N symbols, then draws it as chips |
| `LspNvimSagaWinbarDepth` | `User` | `SagaSymbolUpdate` | same | same, after a fresh symbol response |
| `LspNvimSagaWinbarDepth` | `LspAttach`, `BufWinEnter` | — | same | styles the path-only bar lspsaga writes before any symbol arrives |
| `LspNvimSagaWinbarDepth` | `ColorScheme` | — | chips are on | redefines the chip highlight groups under their old names |

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

Every autocommand in this plugin now goes through `lib.nvim.bindings.autocmd`,
the formatter's included — the "except the formatter's" this section carried
is stale. What is *not* uniform is augroup creation. Seven modules build their
group with the raw `nvim_create_augroup` and hand `create()` the integer id:
`formatter/init.lua` (`LspFormatOnSave`), `languages/app/dart.lua`,
`languages/app/java.lua`, `languages/documentation/markdown.lua`,
`languages/webdev/typescript.lua`, `tools/eslint_prettier/autocmds/init.lua`
and `tools/ts_type_lookup/noice_integration.lua`. The rest use
`autocmd.group(name, true)`.

That is not cosmetic, and the registry is where it shows. `autocmd.group`
remembers `id -> name`; `create()` can only fill a record's `group` field from
that table, so an autocmd registered against a raw id is recorded with **no
group name at all**. Measured after `setup({ formatter = { on_save = true } })`:
of the 30 records `autocmd.registered()` returns, 8 have `group = nil` — the
formatter's `BufWritePre`, both of `LangMarkdownQoL`'s, `LangDart`'s,
`LangJava`'s, `LangTs`'s, `MasonEslintPrettier`'s and
`ToolsNoiceIntegration`'s — exactly the seven modules above. Everything
`:checkhealth` and the generated bindings pages read off that registry is
therefore blind to which group those eight belong to, which is the same class
of blindness that let two groupless autocommands (above) stack unnoticed.

## Changelog

- 2026-09-18: this page re-measured against a live `setup()` rather than read.
  Four corrections: the `ColorScheme` row below was missing (34 call sites, not
  33); `LspSignaturePopup_<winid>` no longer registers `WinClosed`;
  `MasonEslintPrettier` is `BufWritePre` no longer, it is `BufWritePost`; and
  the formatter has not been on the raw API for some time. The "five no-op
  stubs are the only autocommands without a `desc`" claim was wrong by a
  factor of five.
- 2026-09-17: `LangMarkdownQoL` gained a `ColorScheme` handler (`6fb79b7`);
  `LangJava`'s nested `BufWritePre` moved into the group and became
  once-per-buffer (`6fb79b7`); `LspSignaturePopup_<winid>` dropped the
  `WinClosed` event that its buffer-local pattern could never match
  (`ea69f4e`); `MasonEslintPrettier` moved from `BufWritePre` to
  `BufWritePost` (`766d165`). 34 call sites across 25 groups.
- 2026-09-21: `LspNvimSagaWinbarDepth` also styles the breadcrumb as chips
  (`lspsaga_chips.lua`): two more events, `LspAttach`/`BufWinEnter` and
  `ColorScheme`.
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
