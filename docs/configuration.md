# Configuration

The full field reference is `:h lsp.nvim-config`; the defaults themselves are
`lua/lsp/config/DEFAULTS.lua`, which is the single source and is commented. This
page covers what those two cannot: why the options are shaped the way they are.

## Everything here is read by code

Options are added when the code that honours them arrives, not before. A
default nothing reads is a promise the plugin does not keep, and it is worse
than no option at all, because it looks like a knob. `integrations` is the
standing example: the shape of it has been sketched more than once, and the key
stays absent until something reads it.

The rule cuts both ways. `completion.personal_names` sat on the far side of it
for a while and is here now — the source reads it at setup time regardless of
which completion engine is active, which is the whole reason it is an option
rather than something nvim-cmp's own `opts` hands over.

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
on-demand work: definition, hover, rename and code actions are neither
throttled nor switched off, and answer exactly as they do under `default`. That
split is what makes it usable rather than merely smaller.

The one thing `lean` does move that is not a performance dial is
`keymaps.preset`, which it sets to `"minimal"` -- so the catalogue's own keys
for that on-demand work (`lsd`, `lsa`, `lsr`, `lsi`, `lss`, `grn`, `]d`/`[d`
and the per-symbol Trouble views) are not bound under it. The actions remain,
and most of them keep a key: Neovim's own global `gra`, `grr`, `gri`, `grt` and
`gO` cover code action, references, implementations, type definition and
document symbols, and `<leader>rn` still renames. Go-to-definition is the one
with no native equivalent — it is `vim.lsp.buf.definition()` or nothing under
`minimal`. Set `keymaps = { preset = "default" }` alongside the profile to keep
the catalogue's keys as well.

`full` is the inverse trade: `update_in_insert`, inlay hints on, a 50ms
throttle instead of 150, the code-action indicator unfiltered rather than
narrowed to `quickfix`/`source`, the implementation markers on, and gitsigns'
hunk actions in the code-action list. `lean` also switches the winbar
breadcrumb off — a `documentSymbol` request per edit pause, for a bar that only
decorates the window.

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
the codebase may answer them. The other sixteen top-level keys do not, and the
omissions are named rather than left to be inferred. `keymaps`, `usrcmds`,
`which_key` and `menu` describe you — opening a repository must not move a key
or drop a command. `mason` installs software. `preset` is a property of the
machine. `auto_restart` is a supervision policy: how often this editor
relaunches a crashed process belongs to the machine running the servers, and it
is the one omission a repository could otherwise turn into a restart loop.
`lspdoctor` is report formatting and `rename` a personal habit, neither of them
a property of the code being edited. So are `winbar`, `peek`, `implement`,
`code_actions` and `finder`: how *your* editor looks and which picker it opens —
and two of them start extra requests or an extra in-process server, which a
checkout must not switch on. `completion` is host data —
`personal_names.labels` is a function and could not be expressed anyway. And
`project` itself: a file naming its own successor is a loop with nothing to
gain.

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
`gr*` collision with Neovim's own defaults — which are *global*, not
buffer-local, so `grn` and `grt` replace them outright the moment the binder
runs).

## lspdoctor.formatter_priority does not choose a formatter

It ranks a line in a report. That is all it has ever done, and the namespace
says so — it sits under `lspdoctor`, not under `formatter`.

What actually formats a buffer is `lsp.formatter`: conform's chain for the
filetype, with LSP as the fallback conform falls back *to*. On every filetype
conform covers (`lua`, `javascript`, `typescript`, `javascriptreact`,
`typescriptreact`, `json`, `css`, `html`, `cs`, `markdown`, `sh`, `bash`,
`zsh`) no LSP client formats at all, whatever this list says.

The report used to hide that. On a Lua buffer it printed `Winner: **lua_ls**`
while `stylua` was doing the work — a diagnostic tool naming the wrong culprit,
which is the one thing a diagnostic tool must not do. It now prints what conform
answers for the buffer first, and the ranked LSP clients second, marked as the
report-only line it is.

Enforcing the list instead would mean moving the key out of `lspdoctor.*`,
because an option that changes behaviour has no business in a reporting
namespace — and it would change nothing observable until a filetype has two
formatting LSP clients and no conform formatter.

## diagnostics — who owns `vim.diagnostic.config()`

`vim.diagnostic.config()` is one global surface with no notion of an owner.
Every caller merges into the same table, the last one wins **per key**, and
nobody is told. Two plugins with opinions about signs end up with the icons
from one and the virtual text from the other, decided by startup order.

lsp.nvim owns the call. It happens exactly once, from
`lsp.core.diagnostics.apply`, after the servers are enabled, out of three
layers where later wins:

| Layer | Source |
| --- | --- |
| 1 | `lsp.core.diagnostics.baseline()` — lsp.nvim's own presentation |
| 2 | contributions, in registration order |
| 3 | your `opts.diagnostics` — last, so a config always wins |

lsp.nvim's own look is layer **1**, not layer 3. That is deliberate and it was
briefly wrong: the presentation used to live in `config/DEFAULTS.lua`, which is
merged last — so a plugin contributing a virtual-text style was overruled by
lsp.nvim's *default* rather than by anything you asked for. `diagnostics` in
DEFAULTS now holds only `ui` and `debounce_ms`, neither of which is
presentation.

### Contributing from another plugin

A plugin that would otherwise call `vim.diagnostic.config()` itself registers
instead, before `lsp.setup()` runs:

```lua
require("lsp.core.diagnostics").contribute("my.nvim", {
  signs = {
    text = { [vim.diagnostic.severity.ERROR] = " " },
  },
})
```

Registering the same name twice replaces the earlier spec and keeps its
position, so a plugin re-running its own `setup()` does not stack.
`forget(name)` drops one.

lsp.nvim does not know who its contributors are and never requires them — the
registry is a plain list of names and tables.

**Sign tables merge key by key.** Severity values are `1..4`, so a full sign
table looks like a list to `vim.tbl_deep_extend`, which would replace it
wholesale: contributing one icon would silently delete the other three.
`signs.text`, `signs.numhl`, `signs.linehl` and `signs.texthl` are merged per
severity instead.

### Seeing where a setting came from

```vim
:checkhealth lsp
```

The **Diagnostics** section lists every layer by name with the keys it
contributed. A plugin that still calls `vim.diagnostic.config()` directly will
not appear there and will override these per key — that is the situation the
registry exists to end, and the section says so.

---

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

## winbar

The LSP breadcrumb — `folder > file > Class > method` — in the window bar. It
replaces lspsaga's `symbol_in_winbar`, and takes the same two-level shape as
`inlay_hints`:

```lua
winbar = {
  enable = true,
  filetypes = { help = false },
  show_file = true,          -- the path in front of the symbols
  folder_level = 1,          -- directories shown before the file name
  separator = " › ",
  chips = true,              -- rounded, coloured chips; false = one flat string
  max_symbols = { markdown = 1 },
  debounce_ms = 60,          -- cursor movement -> repaint
  refresh_ms = 300,          -- last edit -> next documentSymbol request
},
```

**`max_symbols` is the depth cap, and it is a map for a reason.** Only markdown
is capped by default: marksman reports headings as a *nested* outline, so a
cursor in an H3 is inside three symbols and would draw `file > H1 > H2 > H3`,
which is a table of contents and not a breadcrumb. Your entries merge over that
default, so `{ lua = 2 }` adds a cap and leaves markdown's; `markdown = false`
removes it. `0` is a legal cap and shows the path alone.

**`debounce_ms` and `refresh_ms` are different costs.** The first only decides
how often the bar is redrawn — the cursor reads a cache. The second decides
how often the server is asked, and is the one to raise on a slow machine.

`<leader>tW` and `:Lsp winbar` move the same state at runtime, per filetype
with the second. See [FEATURES/INDICATORS.md](FEATURES/INDICATORS.md#lsp-breadcrumb-winbar)
for what it costs and who owns `'winbar'`.

## peek

The floating, editable peek of a definition (`lsp`, `lsT`, `:Lsp peek`):

```lua
peek = {
  width = 0.7,               -- a fraction of the editor up to 1, cells above
  height = 0.5,
  border = "rounded",
  beacon = true,             -- flash the line when a peek is taken into a window
  keys = {
    close = "q",
    edit = "<C-o>",
    vsplit = "<C-v>",
    split = "<C-x>",
    tabedit = "<C-t>",
  },
},
```

`keys` merges per action: `{ close = "<Esc>" }` changes one and leaves the rest,
`false` unbinds one, and an action that does not exist is dropped with a
warning. They are buffer-local to the peeked buffer and removed when the last
peek window over it closes.

## implement

Implementation markers on interfaces. **Off by default**, and the reason is a
number, not a preference: one `textDocument/implementation` request per marked
symbol per edit pause is the same shape of load that was measured at ~214ms in a
startup sample for the code-action indicator.

```lua
implement = {
  enable = false,
  filetypes = { typescript = true },   -- on here, off everywhere else
  kinds = { Interface = true },        -- SymbolKind names; add Class = true
  text = " %d impl",                   -- %d is the count
  debounce_ms = 600,
  max_requests = 20,                   -- per round
},
```

`kinds` is a **map**, not `{ "Interface" }`: `vim.tbl_deep_extend` merges two
lists index by index, so a list would leave you the default's entries you meant
to replace. The same reason makes `finder` below a map of switches. A `text`
that cannot print a count is refused, with a warning, in favour of the default:
one with no `%d`, or with a lone `%` (`" %d% impl"` — write `%%` for a percent
sign, `" %d%% impl"`). It goes through `string.format` on every answer, so what
`string.format` rejects would otherwise fail there each time and draw nothing.

## code_actions and finder

What `lsa` and `lsf` open:

```lua
code_actions = {
  picker = "auto",           -- "auto" | "fzf-lua" | "native"
  gitsigns = false,          -- hunk actions in the same list
},
finder = {
  references = true,
  implementations = true,
  definitions = true,
  declarations = false,
  typedefs = false,
},
```

`picker = "auto"` is fzf-lua's `lsp_code_actions` — the edit previewed as a
diff — when fzf-lua is installed, and `vim.lsp.buf.code_action` when it is not;
the other two pin one. `gitsigns = true` starts a small in-process language
server on buffers gitsigns is attached to, which is why it is opt-in: it shows
up in `:Lsp servers`. See [FEATURES/NAVIGATION.md](FEATURES/NAVIGATION.md).

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
