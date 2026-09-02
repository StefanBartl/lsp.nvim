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

## Four layers, and why they are in that order

`config/init.lua` resolves the options from four sources:

| | source | what it answers |
| - | ------ | --------------- |
| 1 | `config/DEFAULTS.lua` | the documented values |
| 2 | `config/PRESETS.lua`, selected by `preset` | how much of this should run on **this machine** |
| 3 | the `setup()` options | what **you** wrote |
| 4 | `.nvim-lsp.json` | what **this checkout** needs |

The order is the whole argument for the feature. A preset sits *below* your
options because it moves the floor rather than overruling you -- `preset =
"lean", inlay_hints = { enable = true }` gives you a lean setup with hints on,
which is the only reading that makes both lines mean something. The project
file sits *above* them because "here, not globally" is the one thing it is for.

Resolution happens in **two stages**, not one: layers 1-3 are merged first,
because they are where `project.enable` and `project.file` come from. A project
file cannot decide whether project files are read, and cannot rename its own
successor.

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

With four layers, "the value was wrong" stops being enough. Every warning now
names the layer the value came from -- `(from setup())`, `(from preset "lean")`,
`(from .nvim-lsp.json)` -- because *where* is the question that turns a warning
into a fix. A value that nothing supplied gets no suffix; there is no layer to
name.

## preset: one word for twenty fields

`preset = "lean" | "default" | "full"`. `lean` exists for the machine where
`ts_ls` on a large repo is already the budget. What it turns down is the
**continuous** work -- virtual text redrawn per push, the `signatureHelp` round
trip fired per keystroke inside an argument list, the workspace scan on attach,
the ~25 legacy command registrations at startup. What it does not touch is the
on-demand work: `gd`, hover, rename and code actions behave exactly as they do
under `default`. That split is what makes it usable rather than merely smaller.

`full` is the inverse trade: `update_in_insert`, inlay hints on, a 50ms
throttle instead of 150, and the code-action indicator unfiltered rather than
narrowed to `quickfix`/`source`.

Two things no preset ever sets, whatever its name suggests:

- **`mason.ensure_install`** — installing software is a side effect outside the
  editor. A profile is a performance dial, not consent to download.
- **`formatter.on_save`** — it writes to files. "Turn everything on" must not
  quietly start rewriting buffers on save.

Both stay opt-in under every preset, which is what makes `full` safe to pick
without reading `PRESETS.lua` first.

`default` is an **empty table**, not a copy of the defaults. Duplicating them
would create a second place to change them and a first opportunity for the two
to disagree.

Not to be confused with `keymaps.preset`, which picks a set of *keys*. This one
picks a set of *options* — one of which is `keymaps.preset`.

## .nvim-lsp.json: the project layer

The nearest `.nvim-lsp.json` at or above the working directory, merged over
everything else:

```jsonc
{
  "servers": ["lua_ls", "gopls"],
  "attach": { "use_workspace_diagnostics": false }
}
```

**JSON, not Lua.** A project file is written by whoever wrote the repository,
and Neovim reads it because you opened a directory. Lua would make cloning a
repository enough to run its code. JSON cannot express a function, so there is
nothing to execute — the format *is* the boundary, not a convention on top of
one.

**An allowlist, not a filter.** `servers`, `diagnostics`, `formatter`,
`inlay_hints`, `lightbulb`, `attach`, `workspace`, `tools`, `languages` are
accepted; everything else is dropped with a warning. The line is not "what
could break" but *whose question is this*. Those nine describe the codebase, so
the codebase may answer them. `keymaps`, `usrcmds`, `which_key` and `menu` describe
you — opening a repository must not move a key. `mason` installs software.
`preset` is a property of the machine. `completion.personal_names.labels` is a
function and could not be expressed anyway.

**Read once, at `setup()`.** Nearly everything here is consumed while the
plugin bootstraps: servers are enabled, tools are set up, commands are
registered. Re-reading after a `:cd` would produce a config that no longer
matches what is running — worse than not re-reading it. The file that counts is
the one above the directory Neovim started in, and both `:Lsp status` and
`:checkhealth lsp` name it, because an override you cannot see is a debugging
trap.

Lists replace rather than merge here too, for the same `tbl_deep_extend`
reason as everywhere else — and a malformed value in the project file is *not*
answered by the `setup()` value underneath it. `"servers": "lua_ls"` degrades
to the defaults and warns; letting the layer below quietly cover for it would
make the typo invisible, which is the one outcome worth avoiding.

JSON `null` reads as "no opinion" and leaves the key absent, rather than
setting it to a sentinel.

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

## lightbulb

The code-action indicator. Same two-level shape as `inlay_hints`, plus the
allowlist that makes it usable:

```lua
lightbulb = {
  enable = true,
  filetypes = { typescript = false },
  kinds = { "quickfix", "source" },
  render = "sign",           -- or "virtual_text"
  text = "󰌵",
  debounce_ms = 150,
  priority = 20,
},
```

**`kinds` is why this can be on by default.** An unfiltered code-action
indicator is lit permanently under `ts_ls` and `gopls` — both offer refactors on
nearly every line — and an indicator that is always on says nothing. The
allowlist narrows it to *something here is broken and fixable*. A kind matches
exactly or as a dotted child (`source` covers `source.organizeImports`), an
action with no `kind` always counts because `kind` is optional in the protocol,
and `kinds = {}` turns the filter off. Add `"refactor"` if you want the noisy
version back.

**`render` exists because both obvious places are occupied.** The sign column
carries diagnostic signs and `virtual_text` sits at end of line, so `"sign"`
borrows the sign column on the cursor line only, at a priority above the
diagnostic signs (`priority`, default 20 against `vim.diagnostic`'s 10), and
`"virtual_text"` draws at the window edge instead.

**`debounce_ms` is what the feature costs.** One `textDocument/codeAction`
request per cursor position, sent only to clients advertising
`codeActionProvider`, marked `triggerKind = 2` (Automatic) so servers that
distinguish it can answer more cheaply, and not sent at all in insert mode.
`preset = "lean"` switches the whole thing off for the same reason it switches
off the other continuous costs.

`<leader>tb`, `<leader>tB` and `:Lsp lightbulb` move the same state at runtime.

## auto_restart

Bringing a crashed server back:

```lua
auto_restart = {
  enable = true,
  max_attempts = 4,
  initial_delay_ms = 1000,
  max_delay_ms = 30000,
  reset_after_ms = 60000,
},
```

**On by default, and bounded.** It restores the state you already asked for,
and it cannot run away: four attempts at 1s, 2s, 4s, 8s and then it says so and
stops. `preset = "lean"` leaves it on — it costs nothing while nothing crashes,
and a weak machine is where a server gets OOM-killed in the first place.

**What does not count as a crash**, and each for its own reason:

- **A stop you asked for.** A force-stop is a SIGTERM, which looks exactly like
  a kill. Every deliberate stop in the plugin declares itself first, so `:Lsp
  stop` and `:Lsp restart` are never fought.
- **A clean exit nobody asked for.** Ambiguous by construction; restarting
  risks a loop against a server that has decided it is done.
- **An exit during `:qa`.**
- **A client that died before it ever attached.** There is no buffer to bring
  it back onto, and a server failing *at startup* is the one case where a retry
  loop is a hazard. `:Lsp recover` owns it.

**`reset_after_ms` is survival, not success.** The counter clears when a
relaunched client is still alive that much later. Clearing it on attach instead
would let a server that crashes two seconds after every attach restart forever,
because each attach would forgive the previous crash.

`:Lsp autorestart [toggle|on|off|status]` moves the switch at runtime. There is
no keymap: unlike the hint and indicator toggles this is set once and left, and
a key for it would be a key you never press.

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
| Which layers built the active config? | `:Lsp status`, `:checkhealth lsp` |
| Which keys are bound? | [BINDINGS.md](BINDINGS.md) |
| Which commands exist? | [commands.md](commands.md) |
| Why is the code laid out this way? | [architecture.md](architecture.md) |
