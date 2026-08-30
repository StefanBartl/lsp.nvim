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

## lspdoctor.formatter_priority does not choose a formatter

It ranks a line in a report. That is all it has ever done, and the namespace
says so — it sits under `lspdoctor`, not under `formatter`.

What actually formats a buffer is `lsp.formatter`: conform's chain for the
filetype, with LSP as the fallback conform falls back *to*. On every filetype
conform covers (`lua`, `ts`, `js`, `json`, `css`, `html`, `cs`, `markdown`,
`sh`) no LSP client formats at all, whatever this list says.

The report used to hide that. On a Lua buffer it printed `Winner: **lua_ls**`
while `stylua` was doing the work — a diagnostic tool naming the wrong culprit,
which is the one thing a diagnostic tool must not do. It now prints what conform
answers for the buffer first, and the ranked LSP clients second, marked as the
report-only line it is.

Enforcing the list instead would mean moving the key out of `lspdoctor.*`,
because an option that changes behaviour has no business in a reporting
namespace — and it would change nothing observable until a filetype has two
formatting LSP clients and no conform formatter.

## diagnostics.debounce_ms

A chatty language server publishes diagnostics several times per keystroke
pause. `ts_ls` is the reference case: every push re-renders virtual text,
re-sorts by severity and re-runs whatever listens on `DiagnosticChanged`, and
the payloads in between are transient — superseded a few milliseconds later.

The window is **leading-edge**, and that is the whole design decision. A pure
trailing debounce would delay the first diagnostics of every burst by the full
interval, which is exactly the push a user is waiting for: the one right after
they stop typing. Instead the first push goes through immediately and only what
arrives inside the window is coalesced. Nothing a user waits for gets slower;
the redraw storm disappears.

Coalescing keeps the **newest** payload and never merges. A diagnostics list is
a complete replacement for a file, not a delta — merging two would put back
entries the server had just cleared.

The window is per `(client, file)`. Per client alone would let a noisy buffer
throttle a quiet one; per file alone would let two servers on the same file
cancel each other out. `debounce_ms = 0` turns the throttle off and restores
plain dedup-and-forward.

## inlay_hints

A global default plus a per-filetype override map:

```lua
inlay_hints = {
  enable = false,
  filetypes = { lua = true, markdown = false },
},
```

The map is not a list, and that is the whole design. Inlay hints are worth
having in a typed language and noise in a dynamic one, so a single global
switch was never going to be enough — but two levels only work if "no opinion"
and "explicitly off" are different things. An absent key inherits `enable`;
`false` overrides it. A list (`filetypes = { "lua" }`) type-checks as a table,
resolves every lookup to `nil`, and would override nothing at all — so it is
rejected with a warning instead.

`<leader>th`, `<leader>tH` and `:Lsp hints` move the same state at runtime, and
the toggle applies to every loaded buffer immediately rather than at the next
attach.

## workspace.markers and workspace.containers

Which directories `:Lsp root add` / `<leader>lsw` offer as workspace folders:

```lua
workspace = {
  markers = { ".git", "go.mod", "package.json", "Cargo.toml", ... },
  containers = { "packages", "apps", "services", ... },
},
```

`markers` answers "is this a place a language server could sensibly be pointed
at". It is deliberately broader than any one server's `root_markers`, which
answer the narrower question of where *that* server's root is.

`containers` is the half an upward walk cannot do. From `packages/api` the
interesting neighbour is `packages/web`, which is never above you -- so after
walking up, the search reads the outermost project's children and descends
exactly one level through these names. One `readdir` per container and no
further: an unbounded descent would stat a whole repository to fill a picker.

Both are **replaced** by what you pass, not merged with the defaults. That is
worth stating because Neovim's `tbl_deep_extend` merges arrays index by index,
which would otherwise turn `markers = { "go.mod" }` into `go.mod` followed by
every default from index two on. The same now holds for `servers`, where it was
a live defect: naming one server used to leave you with most of the defaults.

An explicitly empty list is honoured rather than restored -- "offer me nothing
but the client roots and the cwd" is a coherent wish, and putting eighteen
markers back over it would be the config lying.

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
