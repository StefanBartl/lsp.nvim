# Tools

The extras that are not part of the LSP core but ship with it, each behind its
own switch — plus the two pieces of editor furniture the plugin owns outright.

## The four extras

ESLint/Prettier integration, signature help, TypeScript type lookup, and
deprecation help.

- **Module:** `tools/`
- **Config:** `tools.<name>.enable`

## One picker, not two

The four picker keymaps (`<leader>dos`, `<leader>wos`, `<leader>do`,
`<leader>wo`) are fzf-lua, and so is `:TypeDefPick`. It used to be 171 lines of
hand-rolled Telescope — its own finder, entry maker, buffer previewer and
single `<CR>` action — answering the same `workspace/symbol` request fzf-lua
answers with `lsp_workspace_symbols`. Two backends for one kind of list meant
two sets of keys inside the picker, two preview behaviours, and two plugins to
have installed.

Telescope is not gone from the plugin: `languages/webdev/astro` still uses
`telescope.builtin` for component, layout and page navigation, behind a
`FileType astro` autocommand. What is gone is a second picker for the same
list.

`integrations/picker.lua` is still presence-reporting rather than an
abstraction, and says so. An adapter over fzf-lua, telescope, snacks and
pickers.nvim is worth building when there is a second backend to abstract;
removing the second backend was the cheaper half of that trade.

Call hierarchy rides on the same picker and is the reason it was worth
consolidating first: `lsc` asks who calls the symbol under the cursor, `lsC`
what it calls. Neovim ships `vim.lsp.buf.incoming_calls`, but it dumps into the
quickfix list and loses the tree the protocol actually returns; fzf-lua's
providers keep it browsable. `lsc`/`lsC` follow `lsd`/`lsD` — lowercase is the
direction one asks for far more often.

- **Module:** `tools/ts_type_lookup/symbol_picker.lua`, `integrations/picker.lua`
- **Commands:** `:TypeDefPick [symbol]`
- **Keys:** `<leader>dos`, `<leader>wos`, `<leader>do`, `<leader>wo`, `lsc`, `lsC`

## Completion source

An nvim-cmp source that completes dotted plugin names as one atomic candidate
each, ranked by a disk-persisted use counter. The name list is supplied by the
host through `setup({ completion = { personal_names = { labels = fn } } })` —
it is the config's data, not the plugin's. Without a reader the source falls
back to its own `extra.lua` word list.

- **Module:** `completion/personal_names/`
- **Config:** `completion.personal_names.enable`,
  `completion.personal_names.labels`
