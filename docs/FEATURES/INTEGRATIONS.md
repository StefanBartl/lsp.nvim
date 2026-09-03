# Integrations

One adapter per third-party plugin, and these two are the ones that add
something rather than only wiring a plugin up.

## Right-click context menu

`lsp.integrations.menu` builds entries straight from
`require("lsp").status().keymaps` — the resolved keymap catalogue, with the
active `keymaps.preset` and any `keymaps.map` overrides already applied —
in the shape [nvzone/menu](https://github.com/nvzone/menu) expects, grouped
into fly-outs (Navigation, Rename, Formatter, Diagnostics, Trouble, Picker)
derived from each entry's catalogue name. Entries whose `requires` names an
uninstalled plugin are skipped. No `menu` dependency here; a host composes
the entries into its own menu.

- **Module:** `integrations/menu.lua` (`M.items`, `M.submenu`)
- **Config:** `menu.enable` (default `true`)
- **Docs:** [BINDINGS.md](../BINDINGS.md#right-click-context-menu)

## Breadcrumb depth

lspsaga draws the winbar breadcrumb, and it descends into every document
symbol that contains the cursor line. In Markdown that is the whole heading
hierarchy — `folder > file > H1 > H2 > H3` — because marksman reports headings
as a nested outline; in Lua the same code yields `folder > file`, because
lua_ls reports no symbol at all for a line outside a function. The difference
is what the server sends, not how it is drawn, and lspsaga has no depth option
(`ignore_patterns`, the only related knob, matches the buffer name and would
remove the folder and file name too). So the adapter re-cuts the winbar after
lspsaga has written it: path items plus a per-filetype number of symbols.

- **Module:** `integrations/lspsaga.lua` (`M.winbar_max_symbols`,
  `M.set_winbar_max_symbols`, `M.trim_winbar`)
- **Default:** `markdown = 1` — the file's own top heading and nothing below
  it. A filetype not named there keeps the full chain.
