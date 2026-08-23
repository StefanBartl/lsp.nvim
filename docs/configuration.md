# Configuration

The full field reference is `:h lsp.nvim-config`; the defaults themselves are
`lua/lsp/config/DEFAULTS.lua`, which is the single source and is commented. This
page covers what those two cannot: why the options are shaped the way they are.

## Everything here is read by code

Options are added when the code that honours them arrives, not before. The
roadmap designs a wider surface (`completion`, `integrations`) and those keys
are deliberately absent — a default nothing reads is a promise the plugin does
not keep, and it is worse than no option at all, because it looks like a knob.

That rule has already caught one case in this codebase: `:LspDoctor`'s
`show_tools` and `semantic_tokens_timeout` were typed, documented and defaulted
while nothing anywhere read them.

## Malformed values degrade, they do not raise

`config/init.lua` normalizes every option before anything downstream sees it. An
unknown `keymaps.preset` becomes `"default"`, a `formatter = false` becomes the
default table, a `servers` list with non-strings loses those entries.

Two rules behind that:

- **A typo should cost a feature, not the startup.** A config error that
  prevents Neovim from loading is a far worse outcome than one that quietly
  reverts to a default.
- **But it must still be visible.** Every fallback records a warning, and those
  show up in `:Lsp status` and `:checkhealth lsp`. Silent correction is how you
  end up debugging a setting you thought you had set.

`servers` is the sharpest case: an empty or malformed list falls back to the
defaults rather than yielding no language server at all, because "no server"
looks exactly like a broken installation and should never be what a typo
produces.

## The two channels

`opts` configures behaviour. `vim.g.lsp_nvim.pack` decides which third-party
plugins get installed — see [installation.md](installation.md) for why they
cannot be the same table.

## Keymaps are data

`lua/lsp/config/KEYMAPS.lua` holds one entry per action; `keymaps.map`
overrides any of them by name without touching the plugin:

```lua
keymaps = {
  preset = "default",       -- "default" | "minimal" | "none"
  map = {
    goto_definition = "gd", -- a string replaces the left-hand side
    rename_leader = false,  -- false drops the mapping
  },
},
```

`docs/BINDINGS.md` is generated from that same table by
`scripts/gen_bindings.lua`, and CI checks it, so the documented list cannot
drift from the bound one. [BINDINGS.md](BINDINGS.md) has the full catalogue and
the two left-hand sides worth knowing about (`ls*`'s `timeoutlen` cost, and the
`gr*` collision with Neovim's own buffer-local defaults).

## rename.provider

One rename action behind both bound keys, with the backend as an option:

```lua
rename = { provider = "auto" }, -- "auto" | "inc_rename" | "native"
```

This exists because the two keys used to run *different* renames — `grn` the
native one, `<leader>rn` inc-rename — which made "which rename am I in?" a real
question. Both keys are kept; what changed is that they can no longer disagree.

## Where the rest lives

| Question | Answer |
| -------- | ------ |
| What does each field mean? | `:h lsp.nvim-config` |
| What are the actual defaults? | `lua/lsp/config/DEFAULTS.lua` |
| Which keys are bound? | [BINDINGS.md](BINDINGS.md) |
| Which commands exist? | [commands.md](commands.md) |
| Why is the code laid out this way? | [architecture.md](architecture.md) |
