# In-buffer indicators

Four displays that follow the cursor or the text rather than answering a request
you made. All four take the same two-level shape — a global default plus a
per-filetype override map — because each is worth having in one language and
noise in another.

## Inlay hints

Neovim ships `vim.lsp.inlay_hint` natively but ships it off and per buffer, so
"hints on for Go, off for Lua" is something every config builds itself. This is
that switch: a global default plus a per-filetype override map, applied to every
loaded buffer at once and to later ones through an `LspAttach` handler.

An absent filetype key inherits the global; `false` overrides it. The two are
deliberately different states — a list where the map belongs would override
nothing, so it is rejected with a warning rather than accepted silently. Only
clients advertising `inlayHintProvider` are asked, which is also what `status`
reports: switched on and will-show-something are separate questions.

- **Module:** `core/inlay_hints.lua`
- **Config:** `inlay_hints.enable`, `inlay_hints.filetypes`
- **Commands:** `:Lsp hints [toggle|on|off|status|clear] [filetype]`
- **Keys:** `<leader>th` (global), `<leader>tH` (this filetype)

## Code-action indicator

`lsa` used to be a blind grab: press it and find out afterwards whether the
server had anything. The indicator asks `textDocument/codeAction` for the cursor
position ahead of the keypress and marks the line when the answer is non-empty.

The kind allowlist is the design, not a refinement of it. An unfiltered
lightbulb is lit permanently under `ts_ls` and `gopls` — both offer refactors on
nearly every line — and a permanently lit indicator carries no information. The
default allowlist is `quickfix` and `source`, so the mark means *something here
is broken and fixable*. Add `"refactor"` for the noisy version; `kinds = {}`
switches the filter off. An action with no `kind` always counts: `kind` is
optional in the protocol, and dropping those would hide every action from a
server that does not classify.

Both obvious places to draw are already taken — the sign column carries
diagnostic signs, `virtual_text` sits at end of line — so `render = "sign"`
borrows the sign column on the cursor line only, at a priority above the
diagnostic signs, and `render = "virtual_text"` draws at the window edge
instead. Requests are debounced, sent only to clients advertising
`codeActionProvider`, marked `triggerKind = 2` (Automatic) so servers that
distinguish it can answer more cheaply, and skipped entirely in insert mode.

- **Module:** `core/lightbulb.lua`
- **Config:** `lightbulb.enable`, `lightbulb.filetypes`, `lightbulb.kinds`,
  `lightbulb.render`, `lightbulb.text`, `lightbulb.debounce_ms`,
  `lightbulb.priority`
- **Commands:** `:Lsp lightbulb [toggle|on|off|status|clear] [filetype]`
- **Keys:** `<leader>tb` (global), `<leader>tB` (this filetype)

## LSP breadcrumb (winbar)

`folder > file > Class > method`: the file's path, then every symbol that
contains the cursor, outermost first, drawn as rounded chips in the window bar.
It is what lspsaga's `symbol_in_winbar` used to be here, and it is now this
plugin's own — one writer for `'winbar'`, instead of a string lspsaga wrote and
this plugin rewrote.

**What it costs.** One `textDocument/documentSymbol` request per text change,
debounced (`refresh_ms`), cached per buffer against `changedtick` in
`core/symbols.lua`, and shared with the implementation markers below. Moving the
cursor is a walk over the cached tree and, when the result did not change, no
write at all. The cache is stale-while-revalidate: after an edit the previous
tree stays on screen until the new answer lands, so the bar does not blink out
while the server thinks.

**Where the cursor is.** By line, with the column consulted only where the line
alone would be wrong: a symbol that starts and ends on one line, and the last
line of one. A cursor anywhere on the header line of a function — indentation
included — is inside it. A range that ends at column 0 of a later line is read
as ending on the line *before*, which is how a section-shaped symbol (a Markdown
heading) says "up to, not including, the next heading"; read inclusively it puts
the cursor on `## Next` inside the previous section as well. Both flat
(`SymbolInformation[]`) and hierarchical (`DocumentSymbol[]`) answers work; the
tree of a flat one is rebuilt from range containment.

**The depth cap.** `max_symbols` says how many symbols may follow the file, per
filetype, and only `markdown = 1` is set by default. The reason is the shape of
what the servers send, not anything about drawing: marksman reports headings as
a *nested* outline, so a cursor in the body of an H3 is inside three symbols and
the bar would read `folder > file > H1 > H2 > H3`. lua_ls reports no symbol at
all for a line outside a function, so the same code yields `folder > file`. The
value that reads best is the file's own top heading and nothing below it —
deeper levels are a table of contents, and a breadcrumb is not one.
`markdown = false` lifts it; a filetype not named has no cap. Measured against
real servers: in a Markdown file with three nested headings the bar shows the
first only, and all three with the cap lifted.

**Headings** arrive as SymbolKind `String` — the protocol has no "Heading" kind —
so for Markdown that one kind is drawn with a hashtag instead of the
boxed-letter data-type icon, which reads as "a heading" rather than as a type
badge. Icons for every other kind are the set lspsaga shipped, so nothing on
screen changed with the switch.

**Chips.** Three roles, coloured from the colourscheme and tinted towards the
window background (`M.tint`, default 0.2): `folder` from `Special`, `file` from
`Function` (bold), `symbol` from `String`. Those three are picked because
`Directory`, `Function` and `Title` are one and the same blue in tokyonight. The
file keeps its devicon's own colour on the chip background. The role comes from
what the part *is*, not from its position, so a file in the project root is
still a file chip. `chips = false` draws one flat string instead, coloured by
highlight groups that are *linked* (`LspNvimWinbarFolder`, `…File`, `…Symbol`,
`…Sep`), so a `:hi link` of your own wins. A colorscheme change clears every
group; the derived chip groups are redefined under the same names, because the
strings already in a window's `'winbar'` keep naming them.

**Alignment.** `align = "right"` or `"center"` (default `"left"`) push the
whole breadcrumb to the window's right edge, or split it evenly between both.
Neither is a padding calculation: Neovim's `'statusline'` format, which
`'winbar'` inherits, has `%=` as a built-in split-point item -- text after
one is right-aligned, text between two is centred -- and `render.lua` just
wraps the string it already built in the number of `%=` each value needs.
Whatever a symbol's own text contains is escaped before that (a literal
`%` doubled) exactly as it always was — `%=` is a format item this module
writes, not user text, so it needs no escaping of its own.

**The underline some colorschemes draw under the winbar is not this module's.**
There is no `underline` anywhere in `core/winbar/`; what you see is the active
colorscheme's own `WinBar` highlight group. `:hi WinBar gui=NONE` (or an
equivalent colorscheme override) removes it, independent of `align` or `chips`.

**Who owns `'winbar'`.** It is window-local, and this module writes it only on
windows showing a normal buffer with a language server attached (`buftype` is
empty, not a float — a peek window is a float and has its own title; the
in-process client of `code_actions.gitsigns` does not count as a server). It
writes over whatever was there, which is the contract lspsaga had. What it
clears is only its own: a
string is recognised as ours by the `LspNvimWinbar` group names every string
carries, so a winbar another plugin put on a help or terminal window is never
touched, and a released window goes back to the *global* `'winbar'` rather than
to an empty one.

- **Modules:** `core/winbar/` (`init.lua`, `render.lua`, `kinds.lua`),
  `core/symbols.lua`
- **Config:** `winbar.enable`, `winbar.filetypes`, `winbar.show_file`,
  `winbar.folder_level`, `winbar.separator`, `winbar.chips`, `winbar.align`,
  `winbar.max_symbols`, `winbar.debounce_ms`, `winbar.refresh_ms`
- **Commands:** `:Lsp winbar [toggle|on|off|status|clear] [filetype]`
- **Keys:** `<leader>tW` (global)
- **Presets:** off under `lean` — a request per edit pause for a bar that only
  decorates the window

## Implementation markers

`interface Repository` — and nothing on the line says that two classes implement
it. This asks: for every symbol of a configured kind (`Interface` by default) it
sends `textDocument/implementation`, and when the answer is not empty it puts a
count at the end of the line: `interface Repository  2 impl`. Measured against
ts_ls on a file with one interface and two implementing classes, that is exactly
what appears, on the interface's line and nowhere else.

**Off by default, and that is the design.** It is one request per marked symbol
per edit pause — the same shape of load that was measured at ~214ms in a startup
sample for the code-action indicator — and it earns its keep only in languages
that have interfaces: TypeScript, Go, Java, C#. Markdown's server (marksman) has
no `implementationProvider`, which is checked before a single request is sent;
lua_ls has one but reports no `Interface` symbols, so there is nothing to ask
about. `max_requests` caps a round, so a generated file with two hundred
interfaces costs twenty requests. Rounds are keyed to `changedtick`: entering
the buffer, an attach and the schedule in `setup()` all lead to the same round,
and only the first sends anything for text that has not changed. The old
markers stay on screen until the new answers replace them together, so an edit
does not blink every marker off and on.

Two guards keep a marker on the line it describes. The refresh is debounced **per
buffer** — one shared timer keeps only the last call's buffer, so editing one
buffer and moving to another inside the window would leave the first with
markers for text it no longer has. And an answer for text that has changed since
the request went out is not acted on: typing in Insert mode fires no
`TextChanged`, so a late answer would mark the wrong lines, and because a round
counts as handled per `changedtick` it would also turn the right round away.
That holds for both stages of a round — the symbols, and the
`implementation` answers, which are checked once more when the last one lands:
a stale round draws nothing and takes nothing away, and the markers already on
screen keep following their lines. `InsertLeave` and `TextChanged` ask again
once the edit is over.

A buffer whose name ends in `.d.ts` or sits under a `node_modules` path asks
nothing at all — declaration files and library code, not the code someone is
writing. Measured against a real ts_ls on the real `lib.dom.d.ts` (2.3MB,
1540 interfaces): `textDocument/documentSymbol` on the whole file took ~1.1s,
and asking about `HTMLElement` specifically — one symbol, not a round — took
~395ms for 144 locations. A round of `max_requests` such symbols on every
edit pause is exactly the load this feature stays off by default to avoid,
and the count is rarely what anyone wants while reading a type declaration
rather than writing one.

`kinds` is a map of SymbolKind names (`Interface`, `Class`, `Method`, …), not a
list — a list would merge index by index over the default.

- **Module:** `core/implement.lua`
- **Config:** `implement.enable`, `implement.filetypes`, `implement.kinds`,
  `implement.text` (`%d` is the count; `%%` is a literal percent sign),
  `implement.debounce_ms`, `implement.max_requests`
- **Commands:** `:Lsp implement [toggle|on|off|status|clear] [filetype]`
- **Presets:** on under `full`
