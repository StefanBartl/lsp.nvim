# Workflow — using lsp.nvim day to day

Every feature is described on its own in [FEATURES/](FEATURES/README.md), the
commands in [commands.md](commands.md) and [BINDINGS.md](BINDINGS.md). This is
the different question: how the pieces combine once you are working in a real
project, and which of the near-identical-looking routes answers which question.

## The verb name `Lsp` is load-bearing — it takes nvim-lspconfig's plugin file out

`nvim-lspconfig` ships a `plugin/lspconfig.lua` whose sixth line is
`if vim.fn.exists(':lsp') == 2 then return end`, and that lookup is
case-insensitive. Registering `:Lsp` therefore makes lspconfig's whole plugin
file bail out before it registers anything — verified headless: lspconfig loads,
and `:LspStart`, `:LspStop`, `:LspRestart` do not exist afterwards, while
`:LspInfo` and `:LspLog` are this plugin's.

This is why the two coexist quietly instead of overwriting each other. It also
means **renaming the verb is not cosmetic**: rename it and five lspconfig
commands appear, two of which then shadow this plugin's own. If you want
lspconfig's commands back, that is the switch — deliberately, not by accident.

## Start with `status`, escalate to `doctor` — they answer different questions

`:Lsp status` is about the *plugin*: what `setup()` registered, which keymaps
were bound, and every warning the config normalizer worked around. Reach for it
when a setting seems not to have taken effect — a malformed value degrades to a
default and records a warning rather than raising, so "my option does nothing"
is a `status` question, never a server question.

`:Lsp doctor` is about the *buffer*: expected servers vs. running ones,
executables on PATH, advertised capabilities, provider overlap. `startup` is the
default and is usually enough; `capabilities` is the one for "it runs but
behaves oddly", because that is where capabilities and two providers fighting
over the same request show up.

`:checkhealth lsp` is the third and widest: environment, servers, ecosystem —
including keymaps that are bound while the plugin they need is not installed.
The `needs` column in the catalogue is recorded, not enforced, precisely so that
binding a key never force-loads a lazily configured plugin; checkhealth is where
that debt gets reported.

## Restart, force-restart, recover — an escalation ladder, not three synonyms

`:Lsp restart [server]` is the ordinary one. `:Lsp force-restart {server}`
stops every instance of that server with a forced cleanup, waits, then starts
fresh with a retry — reach for it when a plain restart leaves a client that is
attached but unresponsive, which is the case ordinary restart cannot fix.
`:Lsp recover` is the other axis entirely: it asks the doctor's health check
which servers are *configured for this buffer and not running* and starts those.

So: something is misbehaving → `restart`; something is wedged → `force-restart`;
something never came up at all → `recover`. Using `restart` for the third case
does nothing, because there is no client to restart.

## `:Lsp format which` before blaming the formatter

Formatting is conform-first with an LSP fallback, and the two produce visibly
different results. When a buffer formats "wrong", the first question is which
tool ran, and `:Lsp format which` answers it directly instead of leaving you to
infer it from the diff.

**Format-on-save is off by default** (`formatter.on_save = false`). `<leader>ft`
formats once, `<leader>tft` toggles on-save for the session, and
`:Lsp format on|off|status` is the same switch from the command line. The
toggle is the plugin's own autocommand, never conform's option — so turning it
on here does not leave conform quietly formatting in some other code path when
you turn it off again.

`formatter.timeout_ms` defaults to 1500. A large file formatted by a slow
external tool hits that, and the symptom is "nothing happened" rather than an
error.

## `]d` and `]w` are deliberately different questions

`]d`/`[d` move through the buffer's diagnostics, and where they send you depends
on `diagnostics.ui`: `"native"` uses `vim.diagnostic.jump`, `"trouble"` opens
and focuses Trouble's list and moves inside it, `"auto"` (the default) picks
Trouble when it is installed.

`]w`/`[w` move inside an **already open** Trouble list and do nothing when there
is none. That is not a degraded `]d` — it is the "I am working through this
list" motion, and it stays put when no list is open on purpose.

It answers that without loading Trouble at all: if the plugin was never loaded
there is no list of its open, so the answer is already known. Which is what
makes Trouble's `cmd = "Trouble"` lazy trigger correct — these two keys are not
a reason to load it eagerly.

All eight motion keys honour a count: `3]q`, `2]d`. The leader-prefixed actions
populate a list or flip a setting and have no ordered target, so a count there
means nothing.

## Workspace diagnostics: the size gate is the feature

`attach.use_workspace_diagnostics` is on by default, and the walk is
asynchronous with a `max_files` gate of 800. Above that it **refuses and says
so** rather than freezing the editor — so on a large repository the honest
reading of "no workspace diagnostics appeared" is usually "the gate held", not
"the feature is broken". Check with `:Lsp workspace status`.

`:Lsp workspace now` is the one-shot: populate for this buffer's clients right
now, without changing the on-attach setting. That is the right reach for a big
repo where you want the numbers once for a specific question rather than on
every attach.

## Roots: switch the scope, or add a folder

Per-server roots come from each server's resolver; the *global* scope switch —
working directory, git root, or the file's own path — is `<leader>lsp` or
`:Lsp root pick`. `:Lsp root show` (or a bare `:Lsp root`) reports the scope
together with the root every attached client actually resolved and the
workspace folders it holds — which is the question one usually arrives with,
since the scope alone never says where it put your servers.

The case that makes this a workflow item rather than a setting is the monorepo:
with the scope on the git root, a server may index far more than the
sub-project you are in; with it on the file path, cross-package references stop
resolving. Neither is wrong, and which one you want changes with the task.

**When neither is right, add the folder instead.** `<leader>lsw` (`:Lsp root
add`) offers the projects around this buffer and hands the chosen one to every
attached client that accepts a runtime change. gopls sitting in `packages/api`,
one pick of `packages/web`, and definitions across the package boundary resolve
— no restart, no re-index of the whole repo. `:Lsp root remove` takes one back
off, `:Lsp root list` shows what `add` would offer without opening a picker.

Two limits worth knowing before you reach for it. The scope switch only reaches
servers whose `root_dir` is a function — `lua_ls` and `marksman`; `gopls`,
`ts_ls`, `clangd` and `csharp` declare `root_markers` and Neovim resolves those
itself, so for them the folder is the only lever. And a server that never
advertised `changeNotifications` is skipped rather than sent a notification it
did not ask for; `:Lsp root show` names it, with the reason.

lua_ls additionally treats the Neovim config directory as a root of its own,
which is what its workspace library needs; that is not affected by the scope
switch.

## `opts` and `vim.g.lsp_nvim.pack` are two channels, and they cannot be merged

`opts` configures behaviour. `vim.g.lsp_nvim.pack` decides which third-party
plugins get installed, and it has to be set **before** `require("lazy").setup()`
— lazy evaluates `import = "lsp.pack"` while it is still collecting specs, long
before any `setup(opts)` exists to read.

The failure mode is quiet: put `pack` inside `opts` and nothing errors, the
extras simply never get installed, and the plugin reports them as missing in
`:checkhealth lsp` as if you had chosen to run without them.

## A config with its own `lua/lsp/**` shadows this plugin completely

The module root is `lsp` on purpose, so existing `require("lsp.…")` lines keep
resolving after the code moves here. The cost is that a Neovim config with its
own `lua/lsp/` directory wins on the runtimepath, `require("lsp")` never reaches
the plugin, and nothing looks broken — it is simply not the code that is
running.

When migrating: rename the old directory, switch over, verify, and only then
delete it. You cannot test the switch while both exist.

## Two left-hand sides worth knowing about before you rebind anything

The prefixless `ls*` family costs every Normal-mode `l` a `timeoutlen` wait,
because Neovim has to see whether an `s` follows. That is the deliberate price
of a prefixless three-character mapping — if it bothers you mid-session, the
answer is `keymaps.map` per action, not `keymaps.enable = false`.

`grn` and `grt` collide with Neovim 0.11's own `gr*` maps, which are set
**buffer-locally** on `LspAttach` and therefore beat a global mapping. The
plugin re-binds those two on `LspAttach` so the catalogue's version runs, which
is what makes `rename.provider` actually decide the rename — both bound keys run
one rename action, and they can no longer disagree about which backend that is.

`docs/BINDINGS.md` is generated from `lua/lsp/config/KEYMAPS.lua` and CI checks
it with `--check`. Editing the table by hand is pointless; change the catalogue.
