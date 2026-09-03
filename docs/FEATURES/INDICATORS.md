# In-buffer indicators

Two displays that follow the cursor rather than answering a request you made.
Both take the same two-level shape — a global default plus a per-filetype
override map — because both are worth having in one language and noise in
another.

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
