# The full autocommand inventory

`lua/lsp/bindings/autocmds.lua`'s own doc comment says "One group, `lsp_nvim`"
and names only the formatter as an exception. That understates it: this
plugin registers **43 autocommands across 29 augroups**, spread over
`bindings/`, `core/`, `formatter/`, `languages/`, `tools/`, `servers/` and
`integrations/`. [BINDINGS.md](BINDINGS.md#autocommands) covers only the groups
that back the keymap/rename layer and the indicators; this page is the
complete list.

Counted are call sites (`autocmd.create` / `nvim_create_autocmd`), not event
registrations -- the lightbulb watcher listens on four events from one call
site, and counts once here. The figure is the 2026-09-18 one, which was
verified against source and against a live registry, carried forward by what
changed since: **-4** for the lspsaga breadcrumb (`LspNvimSagaWinbarDepth`,
removed when lspsaga was) and **+13** for the four modules that replaced its
features (`lsp_nvim_winbar` 7, `lsp_nvim_symbols` 2, `lsp_nvim_implement` 2,
`lsp_nvim_peek` 1) plus the opt-in `lsp_nvim_gitsigns_actions` 1. It was not
re-counted from scratch. What was measured on 2026-09-21: a bare
`setup({ formatter = { on_save = true } })` leaves **35** records from this
plugin's own files in `lib.nvim.bindings.autocmd`'s registry (36 with ui.nvim's
`lib_kit_toast_resize`, which is not ours). Six of the difference to 43 are
named -- `lsp_nvim_symbols` (2) and `lsp_nvim_peek` (1) are created lazily, on
the first request and the first peek; `lsp_nvim_gitsigns_actions` (1) only with
`code_actions.gitsigns`; the per-window signature popup and `LangJava`'s
nested `BufWritePre` only when one opens -- and two are not traced to a file.

29 groups = 19 named string literals + `lsp_nvim`, `lsp_nvim_inlay_hints`,
`lsp_nvim_lightbulb`, `lsp_nvim_supervisor`, `lsp_nvim_winbar`,
`lsp_nvim_symbols`, `lsp_nvim_implement`, `lsp_nvim_peek`,
`lsp_nvim_gitsigns_actions` (built from `M.GROUP` constants) +
`LspSignaturePopup_<winid>`, whose name is built at runtime -- a grep for the
literal string finds the first 19 and none of the last 10. That one exists only
while its popup is open: the hook deletes itself -- its record in `lib.nvim`'s
autocmd registry included -- and the group when the popup closes, so a session
that shows a thousand popups does not carry a thousand records.

## Core

| Augroup (`clear=true`) | Event | Pattern | Condition | Action |
| --- | --- | --- | --- | --- |
| `lsp_nvim` | `LspAttach` | — | `cfg.keymaps.enable` | Re-binds the catalogue's `rename` and `goto_type_definition_gr` buffer-locally |
| `lsp_nvim_inlay_hints` | `LspAttach` | — | `vim.lsp.inlay_hint` exists | Applies the resolved hint state (global + filetype override) to the freshly attached buffer, `vim.schedule`d because the buffer's filetype is not reliably set yet at `LspAttach` on a session's very first attach |
| `lsp_nvim_lightbulb` | `CursorMoved`, `BufEnter`, `InsertLeave`, `DiagnosticChanged` | — | — | Asks `textDocument/codeAction` for the cursor position, debounced (`lightbulb.debounce_ms`, default 150ms), marks the line on a hit |
| `lsp_nvim_lightbulb` | `InsertEnter` | — | — | Clears the mark, **without** debounce — hiding is never what rate-limiting is for |
| `lsp_nvim_lightbulb` | `LspAttach` | — | — | Asks once as soon as a client is there |
| `lsp_nvim_winbar` | `CursorMoved` | — | — | Repaints the LSP breadcrumb for the current window, debounced (`winbar.debounce_ms`, default 60ms); reads the symbol cache, sends nothing |
| `lsp_nvim_winbar` | `BufWinEnter`, `WinEnter`, `BufEnter` | — | — | Repaints the window that just changed and asks for symbols if the cache is stale (not debounced: entering a buffer is one event, not a burst) |
| `lsp_nvim_winbar` | `TextChanged`, `InsertLeave` | — | filetype enabled | Re-requests `textDocument/documentSymbol`, debounced per buffer (`winbar.refresh_ms`, default 300ms) |
| `lsp_nvim_winbar` | `LspAttach` | — | — | Draws the path-only bar at once and asks for symbols |
| `lsp_nvim_winbar` | `LspDetach` | — | — | Drops the bar when the last client leaves (`vim.schedule`d: the client is still listed while this fires) |
| `lsp_nvim_winbar` | `BufWipeout` | — | — | Forgets that buffer's refresh timer |
| `lsp_nvim_winbar` | `ColorScheme` | — | — | Redefines the chip highlight groups under their old names |
| `lsp_nvim_symbols` | `BufWipeout`, `BufUnload` | — | — | Drops a buffer's cached document symbols and cancels its request. Registered on the first symbol request |
| `lsp_nvim_symbols` | `LspDetach` | — | the client was the one that answered | Drops symbols that came from a client that is leaving |
| `lsp_nvim_implement` | `TextChanged`, `InsertLeave`, `BufEnter`, `LspAttach` | — | filetype enabled | Asks for implementations after an edit, debounced (`implement.debounce_ms`, default 600ms); one round per `changedtick` |
| `lsp_nvim_implement` | `BufWipeout` | — | — | Cancels and forgets that buffer's round |
| `lsp_nvim_peek` | `WinClosed` | `*` | window is a peek | Gives back the peek's keymaps, closes what was opened from it, unloads a buffer the peek loaded. Registered on the first peek |
| `lsp_nvim_gitsigns_actions` | `User` | `GitSignsUpdate` | `code_actions.gitsigns` | Starts the in-process server on a buffer gitsigns is attached to |
| `lsp_nvim_supervisor` | `LspAttach` | — | — | Records server name, buffer and start time per client id |
| `lsp_nvim_supervisor` | `VimLeavePre` | — | — | Sets the flag that keeps client exits during `:qa` from counting as crashes |

`lsp_nvim_inlay_hints`, `lsp_nvim_lightbulb`, `lsp_nvim_winbar` and
`lsp_nvim_implement` are their own groups rather than folded into `lsp_nvim`
because that group is cleared whenever `keymaps.enable = false` — hints, the
lightbulb and the breadcrumb are not a keymap concern and must not disappear
with the keymaps.

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

## The breadcrumb (`core/winbar/`)

The rows are in the Core table above. What is worth knowing that a table does
not say:

**One `CursorMoved` handler, and it sends nothing.** Moving the cursor only
reads the cached symbol tree (`lsp.core.symbols`) and writes `'winbar'` when
the string changed. The request is a separate path, off `TextChanged` and
`InsertLeave`, debounced per buffer -- a single shared debounce would drop the
refresh of buffer A when buffer B changed inside the window.

**It draws the string instead of rewriting one.** The breadcrumb used to be
lspsaga's, and this plugin trimmed its depth and styled it as chips by
rewriting what lspsaga had written, from an autocommand that had to defer with
`vim.schedule` because lspsaga installed its own per-buffer `CursorMoved`
handler at `LspAttach` time and ordering between the two could not be relied
on. That whole class of problem is gone with lspsaga: there is one writer.

**Ownership of `'winbar'`.** Written over on any window that shows a normal,
LSP-attached buffer; cleared only when the string in it carries the
`LspNvimWinbar` group names every string this module writes. A window whose
`'winbar'` another plugin set is never cleared, and on release the window goes
back to the *global* value (`setlocal winbar<`) rather than to `""`, so a
plugin that sets `vim.o.winbar` does not lose it on the windows this module
had drawn on.

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

- 2026-09-21: lspsaga removed. `LspNvimSagaWinbarDepth` (4 call sites) is gone;
  `lsp_nvim_winbar` (7), `lsp_nvim_symbols` (2), `lsp_nvim_implement` (2),
  `lsp_nvim_peek` (1) and, opt-in, `lsp_nvim_gitsigns_actions` (1) are new.
  43 call sites across 29 groups; see the top of the page for what was
  measured and what was carried forward.
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
