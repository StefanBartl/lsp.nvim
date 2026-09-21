# Integrations

One adapter per third-party plugin, and this is the one that adds something
rather than only wiring a plugin up.

## Right-click context menu

`lsp.integrations.menu` builds entries straight from
`require("lsp").status().keymaps` — the resolved keymap catalogue, with the
active `keymaps.preset` and any `keymaps.map` overrides already applied —
in the shape [nvzone/menu](https://github.com/nvzone/menu) expects, grouped
into fly-outs (Navigation, Diagnostics, Formatter, Toggles, Picker, Rename,
Trouble, Workspace) derived from each entry's catalogue name. Toggles and
Workspace exist because the naming convention alone put the two on/off pairs
and `workspace_folder_add` into Navigation, which came back with fifteen
children, five of which navigate nowhere. Entries whose `requires` names an
uninstalled plugin are skipped, so the groups you actually get are the subset
whose plugins are there. No `menu` dependency here; a host composes the entries
into its own menu.

- **Module:** `integrations/menu.lua` (`M.items`, `M.submenu`)
- **Config:** `menu.enable` (default `true`)
- **Docs:** [BINDINGS.md](../BINDINGS.md#right-click-context-menu)

## The breadcrumb is not an integration any more

This page used to carry two more sections, "Breadcrumb depth" and "Breadcrumb
chips", because the breadcrumb was lspsaga's and this plugin re-cut and re-styled
the string lspsaga had written. lspsaga is gone from the pack, and so is the
adapter (`integrations/lspsaga.lua`, `lspsaga_chips.lua`): the breadcrumb is now
this plugin's own, in [INDICATORS.md](INDICATORS.md#lsp-breadcrumb-winbar). What
replaced each lspsaga feature is in
[NAVIGATION.md](NAVIGATION.md#coming-from-lspsaga).
