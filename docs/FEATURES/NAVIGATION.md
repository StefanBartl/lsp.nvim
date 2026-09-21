# Looking things up without losing your place

`lsd` jumps and loses where you were; `lsr` and `lsi` list. Between "jump" and
"list" sits the question that comes up most — *what does this do, right now, and
can I stay where I am* — and everything on this page is an answer to a version
of it. None of it needs a plugin beyond the ones an LSP setup already has;
where fzf-lua or Trouble makes it better, it says so and works without.

Every key below is a catalogue entry (`keymaps.map.<action> = "<lhs>"` moves it,
`= false` drops it), lives in the `default` preset and is **not** in `minimal`.
The five `ls*` ones extend the prefixless family whose price is a `timeoutlen`
wait on every Normal-mode `l` — see [BINDINGS.md](../BINDINGS.md#keymaps) — and
`minimal` exists to avoid that, so it stays as it was. The family is **Normal
mode only**: a Visual-mode mapping that starts with `l` would make every `l`
there wait too, and `vl` / `vjl` are how a selection gets extended.

| Key | Action | Does |
| --- | --- | --- |
| `lsp` | `peek_definition` | The definition, in an editable float over the code |
| `lsT` | `peek_type_definition` | The same for the type |
| `lsa` | `code_action` | Code actions, with the edit previewed as a diff |
| `gra` (Visual) | `code_action_range` | The same for the selection |
| `<leader>xa` | `diag_code_action` | The quick fix for the diagnostic on this line |
| `lsf` | `picker_finder` | References, implementations and definitions in one list |
| `lsh` / `lsH` | `picker_type_super` / `picker_type_sub` | Type hierarchy, up and down |
| `<leader>xo` | `trouble_outline` | Outline sidebar that follows the cursor |

## Peek

The definition opens in a float over the current window, and the buffer in it is
the **real** buffer: same highlighting, same LSP, editable. Close it and the
cursor is exactly where it was.

Inside the float:

| Key | Does |
| --- | --- |
| `q` | Close it (and anything stacked above it) |
| `<C-o>` | Take the peeked buffer into the window you came from |
| `<C-v>` / `<C-x>` | Take it into a new vertical / horizontal split |
| `<C-t>` | Take it into a new tab |

"Take it" lands at the cursor the peek window has *now*, not where it opened —
you may have scrolled to the bit you wanted — records the jump, so `<C-o>` in
the real window comes back to where the peek started, and closes every peek.
The keys are `peek.keys`; `false` unbinds one. They are buffer-local to the
peeked buffer and given back, including any buffer-local map of your own they
shadowed, when the last peek window over that buffer closes.

The peek keys work in the float too, so a peek from inside a peek stacks another
float on top, offset a little so a stack reads as a stack. Closing a lower one
closes what is above it.

One place opens directly. **Several** go through `vim.ui.select` first, with
file and line, because a float has room for one buffer and picking is the honest
answer to "which".

A buffer that was not open before the peek is unloaded again when the peek
closes, unless it was modified or is shown somewhere else — otherwise ten peeks
leave ten buffers in the list. A buffer that was already open is never touched.

A peek opens its buffer without listing it (`bufadd`), which is right for the
one it unloads again and wrong for one that stays: a buffer you take into a
window, and one you edited so it could not be unloaded, are both **listed** —
`:ls`, the tabline and the buffer pickers show what the editor is holding.

After a peek is taken into a real window the target line flashes
(`peek.beacon`), which is the one moment the eye loses the cursor.

- **Module:** `core/peek/` (`init.lua`, `beacon.lua`)
- **Config:** `peek.width`, `peek.height` (a fraction of the editor up to 1,
  cells above), `peek.border`, `peek.beacon`, `peek.keys`
- **Commands:** `:Lsp peek [definition|type_definition|implementation|declaration]`
  — the two extra kinds have no key, only the command

## Code actions

`lsa` used to be `vim.lsp.buf.code_action`: a list of titles, and no way to see
what a refactor would do before you apply it. With fzf-lua installed it is now
fzf-lua's `lsp_code_actions` — the same request, with a previewer that renders
the `WorkspaceEdit` as a diff. That matters most for `refactor.*` actions
(ts_ls's "Move to a new file", gopls's refactorings), where applying blind is
the uncomfortable case.

`code_actions.picker` decides: `"auto"` (default) is fzf-lua when it is there
and the native list when it is not; `"fzf-lua"` and `"native"` pin one — the
former says so, once, if fzf-lua is missing and the key still works. fzf-lua's
picker is opened with `silent = true`, so it does not warn that it is not your
global `vim.ui.select` backend; it takes that role for this one call only.
A selection asks for the actions of the selection, which is what
`vim.lsp.buf.code_action` does natively and fzf-lua calls it — on **`gra`** in
Visual mode, not on `lsa`. `lsa` is Normal-mode only because a Visual-mode
mapping that starts with `l` makes every `l` there wait out `timeoutlen`
(`vl`, `vjl`), while `g` + `r` is already a prefix in Visual mode, so `gra` adds
no wait to any key. It is the catalogue's entry (`code_action_range`) replacing
Neovim's own Visual-mode `gra` the way `grn` and `grt` replace theirs; in Normal
mode Neovim's `gra` stays as it is.

**Quick fix for a diagnostic.** `]d` already jumps to a diagnostic and shows it.
`<leader>xa` is the missing third step: the same list, asked for the
diagnostics on the cursor line and only for `quickfix` kinds, so the answer is
"how do I fix this", not "what could I refactor". It says so when the line has
no LSP diagnostic — a linter's message has no server to ask.

**gitsigns hunk actions.** With `code_actions.gitsigns = true`, the same list
carries *Stage hunk*, *Reset hunk* and *Preview hunk* whenever the cursor (or
selection) touches a hunk. They arrive the way every code action does — from a
language server, here a small **in-process** one (`cmd` is a Lua function: no
process, no stdio, nothing to install) that answers `initialize` and
`textDocument/codeAction` and nothing else, on buffers gitsigns is attached to.
The commands run client-side. Off by default, because it is one more client in
`:Lsp servers`; on under `preset = "full"`. Their kind is `refactor.gitsigns`,
which the [code-action indicator](INDICATORS.md#code-action-indicator)'s default
allowlist does not light on — a hunk action is neither a fix nor a source
action, and the bulb would otherwise burn on every changed line.

The client is named `lsp.nvim-gitsigns`, and to Neovim it is a client like any
other — attached to every buffer gitsigns tracks, whatever its language. So the
plugin's own consumers look past clients named `lsp.nvim-*`
(`lsp.core.util.server_clients`): the [winbar](INDICATORS.md) draws only where a
language server is attached (not on a `.txt` file that merely sits in a git
repository), and `:Lsp stop` / `:Lsp restart` and their completion leave it
alone. It re-attaches by itself on the next gitsigns update; `:Lsp restart` and
`:Lsp stop` on its name say so instead of trying. Anything *else* that lists
`vim.lsp.get_clients()` — a statusline's LSP indicator, say — will show it.

A hunk that only *removed* lines counts as the one line it sits on, as it does
for gitsigns' own sign — with the two edges gitsigns bends the rule for: a
deletion above the first line belongs to line 1, one after the last line to the
last line. The server also reports each request as answered (the fourth argument
of `request`); one that does not leaves every code-action query registered as
pending on the client for good, and the indicator asks on every `CursorHold`.

- **Modules:** `bindings/actions.lua` (`code_action`, `diag_code_action`),
  `core/gitsigns_actions.lua`
- **Config:** `code_actions.picker`, `code_actions.gitsigns`

## Finder

`lsf`: everything that uses, implements or defines the symbol, in one fzf-lua
list with a preview, and `<C-v>` / `<C-x>` / `<C-t>` from fzf-lua's own actions.
It is `lsp_finder` with the sources chosen by `finder.*` — references,
implementations and definitions by default; `declarations` and `typedefs` are
there when you want them. A flat list, not a tree, which for "where is this
used" is usually faster; `<leader>xlr` (Trouble) is the tree.

Needs fzf-lua (`:checkhealth lsp` says so if the key is bound without it). With
every source off it refuses to open an empty list and tells you why.

- **Config:** `finder.references`, `finder.implementations`,
  `finder.definitions`, `finder.declarations`, `finder.typedefs` — a map of
  switches rather than a list, because a list merges index by index and
  `{ "references" }` over three defaults would still leave you the other two

## Type hierarchy

`lsh` (supertypes) and `lsH` (subtypes), through fzf-lua's `lsp_type_super` /
`lsp_type_sub`, or Neovim's own `vim.lsp.buf.typehierarchy` without it. Few
servers answer this — clangd, jdtls and dartls — so before sending anything it
asks whether an attached client advertises `textDocument/prepareTypeHierarchy`
and, if none does, says which servers usually do, instead of a wait and then
"No results". Measured against lua_ls, marksman and ts_ls: none of the three
advertises `typeHierarchyProvider`, so in Lua, Markdown and TypeScript the key
answers with that sentence and nothing else.

## Outline

`<leader>xo` toggles Trouble's `symbols` mode: the document's symbol tree in a
right-hand panel that follows the cursor. Trouble ships that mode configured
already; the existing `<leader>xls` binds the plain list view, which has none of
those settings. For Markdown it doubles as a table of contents — marksman
reports headings as nested symbols. Needs Trouble.

## Coming from lspsaga

lsp.nvim used lspsaga for the winbar breadcrumb and nothing else, and no longer
does. The plugin is not in the pack any more; `pack.disable = { "lspsaga.nvim" }`
is harmless and can go. What it did, and where that lives now:

| lspsaga | Now |
| --- | --- |
| `symbol_in_winbar` | [the LSP breadcrumb](INDICATORS.md#lsp-breadcrumb-winbar) — `winbar.*`, `:Lsp winbar` |
| `winbar_toggle` | `:Lsp winbar [toggle\|on\|off\|status\|clear] [filetype]`, `<leader>tW` |
| `peek_definition`, `peek_type_definition` | [Peek](#peek), `lsp` / `lsT` |
| `beacon` | `peek.beacon` — lspsaga fired it only from its own definition and call-hierarchy jumps, and so does this |
| `finder` | [Finder](#finder), `lsf` |
| `code_action` (with preview) | [Code actions](#code-actions), `lsa` |
| `code_action.extend_gitsigns` | `code_actions.gitsigns` |
| `diagnostic` → run the fix from the float | `<leader>xa` |
| `outline` | [Outline](#outline), `<leader>xo` |
| `supertypes` / `subtypes` | [Type hierarchy](#type-hierarchy), `lsh` / `lsH` |
| `implement` | [Implementation markers](INDICATORS.md#implementation-markers), `implement.*` — off by default |
| `incoming_calls` / `outgoing_calls` | already `lsc` / `lsC` |
| `hover_doc`, `rename`, `lightbulb`, diagnostic lists, `open_log` | already covered: `tools.lsp_signature`, inc-rename, `core/lightbulb.lua`, Trouble and the pickers, `:Lsp log open` |

Two things lspsaga has that are deliberately not rebuilt. `term_toggle` is not
an LSP feature, and a third terminal path next to the ones a config already has
is damage rather than value. `project_replace` is a search-and-replace over the
project, which belongs to a replace plugin, not to an LSP umbrella.
