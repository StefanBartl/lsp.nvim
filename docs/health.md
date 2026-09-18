# Health Check

```vim
:checkhealth lsp
```

Seven sections, in the order you need them when something is wrong.

| Section | Answers |
| ------- | ------- |
| Environment | Neovim 0.11+, and lib.nvim — the one dependency the plugin cannot run without |
| lsp.nvim | Whether `setup()` ran, which config layers built it, what it registered, and every warning it worked around |
| Keymap collisions | Whether the keymap catalogue still owns its keys right now — or you, or another plugin, also claimed one |
| Servers | Installed vs. configured vs. set up vs. attached — here and in total |
| Ecosystem | Which third-party plugins the adapters can see |
| Diagnostics | Whether `vim.diagnostic.config()` was applied, and who contributed which keys |
| Per-buffer diagnosis | Points at `:LspDoctor`, which answers the buffer-level questions |

All seven run even when one of them cannot. A section whose module raises turns
into a single error line — *"this section failed: …"*, with "the sections after
it still ran" beside it — and the report continues. A health check that dies on
the first broken module is useless in precisely the case it exists for.

## The two lines above the warnings

The `lsp.nvim` section names the `preset` that was applied and the
`.nvim-lsp.json` that was merged, if any — before the warnings, because the
warnings refer to them: reading `(from .nvim-lsp.json)` is only useful once you
know a project file was found at all, and which one.

This is the answer to "why is `ts_ls` not attaching in this repository". A
project override that nobody can see is a debugging trap, so it is reported
whether or not anything went wrong.

## Keymap collisions

`keymaps_spec.lua` already proves that no two catalogue entries claim the same
key at build time — a mistake that costs nothing there, since the suite never
touches a live keymap. What it cannot see is the runtime question: does the
catalogue collide with a key *you* set in your config, or one another plugin
set?

This section answers that by reading
`lib.nvim.bindings.keymap.conflicts()` — a registry of every plugin bound
through `lib.nvim`'s own keymap wrapper, filtered here to conflicts naming
`"LSP"`, the name the catalogue registers under. One `lhs`/mode claimed twice
means one binding wins silently and the other never fires — rebind the
catalogue entry via `keymaps.map`, or change the other side.

It only sees what went through `lib.nvim`: a plugin that calls
`vim.keymap.set`/`vim.api.nvim_set_keymap` directly, without ever touching
`lib.nvim`, leaves nothing here to find. That gap is inherent to reading a
registry rather than re-scanning the live keymap table on every key the
catalogue owns, and is worth knowing before reading a clean report as proof
that nothing collides.

## Reading the Servers section

Four numbers, and the gap between any two of them is usually the answer.

- **Installed but not configured** — Mason has the package on disk and
  `servers` never names it. Not a problem: an installed server that nothing
  sets up is idle. The line exists so the install count is not mistaken for
  something running. Mason's package names are not lspconfig's
  (`lua-language-server` against `lua_ls`), and the mapping between them lives
  in mason-lspconfig, which this plugin does not depend on — so the two lists
  are counts side by side, not a name-for-name comparison.
- **Configured but not set up** — the name did not resolve to an
  `lsp.servers.<name>` module, or that module's setup threw. The reason is in
  the warnings above it.
- **Set up but not attached** — expected until you open a matching file. If it
  stays that way, `:Lsp doctor startup` adds the missing piece: whether the
  server's executable actually resolves.
- **Attached, but not here** — the per-buffer line names which of the running
  clients serve the file you were in when you opened the report. A server can
  be running for a different project root and be irrelevant to the buffer in
  front of you.

### Which buffer is "here"

The one you came from, not the report. Neovim creates the `health://` buffer
and makes it current *before* it runs any check, so the report would otherwise
be describing itself. The buffer you came from is the alternate one.

That only survives the *first* `:checkhealth` of a session: each run wipes the
previous `health://` buffer and leaves the window without an alternate, so a
second opinion has nothing to come from. Rather than claim there is no buffer
while the file is still open and the client still attached to it, it falls back
to the last used listed file buffer — and says so, appending
`(last used file buffer)` to the name. A tie there is broken by buffer number,
which is a guess however deterministic, and the suffix is what tells you to
read the line that way.

Only when that fallback finds nothing either — the report was opened from an
empty session — does it say `unknown -- no file buffer to report on`, rather
than printing a zero that looks like a fault.

## The one warning about cost

An installed server costs nothing. A running server costs little. What costs is
a **heavy server held open across many buffers** — `ts_ls`, `pyright`, `jdtls`
and `omnisharp` keep a whole-project model in memory and re-check it per
buffer, so twenty attached buffers is a different machine than two.

That is the only thing in the section that warns, and it warns on the
combination, never on a count alone: five buffers on `ts_ls` is a working set,
and warning about it would train you to skip the section. The warning names the
buffer count and the total line count, so the number is the actual magnitude
rather than an adjective.

## Severity means something

An error is something the plugin cannot work without. Information is something
it uses when present. That is why a missing conform.nvim is an error and a
missing trouble.nvim is not — one is the formatter engine, the other is a UI the
keymap catalogue reaches through command strings.

The same rule applies to keymaps: an entry bound while the plugin it needs is
absent is a **warning**, because it will fail only when pressed, which is the
worst moment to find out.

Absent and broken are told apart, and the advice is the difference. A plugin
that is nowhere on the runtimepath gets "which is not installed" and "install
it"; one that is on the runtimepath and raised on the way up gets "which is
installed but failed to load" and "do not reinstall it — it is there", with the
`:lua require("…")` that shows the error itself. `pcall(require, …)` cannot
separate those two, and this report used to call both "not installed", which is
an hour spent reinstalling something that was already there.

One warning per plugin, listing the keys it owns, and the plugins come out in
sorted order — LuaJIT seeds its string hashes per process, so an unsorted report
moves its lines from run to run, and a report whose lines move is one you cannot
diff against the one you pasted into an issue yesterday.

## It cannot disagree with `:Lsp status`

Both read `require("lsp").status()`. There is no second place where the plugin
describes itself.

## Two things it deliberately does not do

It does not repeat `:LspDoctor`'s per-buffer report — capabilities, workspace
folders, provider conflicts belong there and are shown by
`:Lsp doctor capabilities`.

It does not list the third-party plugins from a table of its own. The list comes
from the adapter registry, because a list written down twice eventually
disagrees with itself.
