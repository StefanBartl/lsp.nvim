# LSP Doctor

Six reports on the LSP state of the current buffer, each answering one
question. Five observe; one provokes. Part of `lsp.nvim`; reachable as
`:LspDoctor` and as `:Lsp doctor`.

`:checkhealth lsp` answers a different question — *is the plugin healthy* — and
points here for the per-buffer detail. Neither reimplements the other.

> Rewritten 2026-08-29 against the source. The previous version described the
> pre-migration module (`require("usrcmds.lspdoctor")`, `run()`, `export()`,
> `:LspDoctor export`), none of which exist in this plugin.

---

## Table of content

- [The reports](#the-reports)
- [`probe`: proving the pipeline works](#probe-proving-the-pipeline-works)
- [Commands](#commands)
- [The scratch buffer](#the-scratch-buffer)
- [Configuration](#configuration)
- [What the reports show](#what-the-reports-show)
- [Formatter](#formatter)
- [Offset encoding mismatch](#offset-encoding-mismatch)
- [API](#api)
- [Troubleshooting](#troubleshooting)
- [Development](#development)

---

## The reports

The name says which question it answers, not how much output to expect.

| Report | Answers |
| ------ | ------- |
| `startup` | Is the server running, and if not, why? Per server: running, configured, attempts made, executable found, last error, and what to run next. |
| `resolve` | Where does the filetype → server chain break? Five numbered steps: which servers this filetype should get, which are configured, which are registered with `vim.lsp.config`, which are running, and what `:Lsp start` would offer. |
| `buffer` | What is going on in this buffer right now? Attached clients, diagnostic counts per severity, provider conflicts, offset encodings, formatter. Lists capped at `list_limit`. |
| `capabilities` | What can the servers here actually do? The `buffer` report uncapped, plus `root_dir` and workspace folders and the full capability set per client. |
| `probe` | Do diagnostics actually arrive? Hands the attached clients a buffer they cannot possibly parse and waits. The only report that provokes rather than observes — see below. |
| `all` | The four observing reports, in that order. What `:LspDoctor` runs with no argument. **Not** `probe`. |

### Why these names

Until 2026-08-29 they were `health`, `debug`, `quick` and `deep`. Three
problems:

- `quick` and `deep` described **volume, not content**. Nothing in "deep" hinted
  that it is where the capabilities and workspace folders live — which is what
  one opens it for.
- `health` was **triple-booked**. `:checkhealth lsp` and `:Lsp health` report on
  the *plugin*; `:LspDoctor health` reported on *this buffer's servers*. Three
  commands with "health" in them, two different meanings.
- `debug` is the vaguest word available for a report that does something very
  specific.

**The old spellings still work** — as command arguments and as functions.
Renaming a command someone already has in a mapping is a worse outcome than a
name that reads badly. They are simply no longer offered in completion, so
nobody learns them anew.

That "accepted but not offered" split is why the mode argument is a custom
argument type (`LSP_DOCTOR_MODE`) rather than an `enum`: the command composer
rejects an off-enum value *before* the route body runs, so an enum cannot
express it. Same mechanism `lsp.bindings.usrcmds` uses for `LSP_SERVER`.

---

## `probe`: proving the pipeline works

`:LspDoctor probe` answers the one question the other five cannot: **is
anything coming back?**

A clean file and a dead diagnostics pipeline look identical. Both are an empty
buffer with no signs in the gutter, and every state-reporting check says the
same thing about both — the server is running, it advertises the capability,
the buffer has zero diagnostics. The only way to tell them apart is to
guarantee there is something to report and see whether it gets reported.

So `probe` does that:

1. Builds a buffer of content this filetype's server is certain to reject
   (`local x =` for Lua, `const x =` for JavaScript, an unclosed `func main()`
   for Go), named after a file that does **not** exist, in the directory of the
   current buffer so `root_dir` resolves the way it does for real work.
2. Attaches the clients that are already on the current buffer. It does not
   start servers — the question is whether *these* clients deliver, and
   starting one would answer a different question slowly.
3. Waits up to `probe_timeout` for diagnostics to come back, per client.
4. Deletes the buffer, which sends `didClose` and takes the probe's own
   diagnostics with it.

**Nothing is ever written to disk**, at any point. The document exists only as
the content the client sent over the wire.

```
Summary: 1/1 client(s) delivered diagnostics within 5000ms

### Probe

Filetype `lua`, probing through `lspdoctor_probe.lua` (never written to disk).

**lua_ls**
  Diagnostics: ✅ 1 after 21ms
  First: `<exp> expected.` (ERROR)
```

Silence is the finding worth having:

```
**gopls**
  Diagnostics: ❌ none within 5000ms
  💡 The server is attached and was sent a file it cannot parse, and said
     nothing. Check `:LspLog`.
  💡 A server that refuses files outside its project (gopls without a module,
     tsserver without a tsconfig) looks the same from here. Open a real broken
     file to tell the two apart.
```

That second hint is the honest limit of the method, and it is printed rather
than assumed away: a synthetic file can be rejected for being synthetic, and
this report cannot see the difference between that and a broken pipeline.

**It is not part of `all`.** The other five read state and are instant; this one
creates a buffer, talks to the servers and blocks for up to `probe_timeout`.
Folding it into the no-argument default would make the report people reach for
first slow and side-effectful for the sake of a question they did not ask.

**Filetypes.** A probe needs content the server is *certain* to reject, so there
is a snippet per filetype rather than a guess: `c`, `cpp`, `cs`, `css`, `go`,
`java`, `javascript`, `javascriptreact`, `json`, `jsonc`, `lua`, `python`,
`rust`, `sh`, `bash`, `toml`, `typescript`, `typescriptreact`, `yaml`, `zig`.
Every one is a *syntax* error, not a type or lint error: syntax is what a server
checks before it resolves anything, so the probe stays honest in a directory the
server has not finished indexing. On any other filetype the report says so and
names the ones it covers — guessing would risk reporting a dead pipeline for a
file that was simply acceptable.

Add one by extending `probe.SNIPPETS`:

```lua
require("lsp.lspdoctor.probe").SNIPPETS.elixir =
  { ext = "ex", lines = { "defmodule Probe do" } }
```

`ext` is not decoration: for most servers the file extension, not the Neovim
filetype, decides whether the document is theirs at all.

---

## Commands

```
:LspDoctor                the four observing reports combined
:LspDoctor startup        is the server running, and if not, why
:LspDoctor resolve        where the filetype -> server chain breaks
:LspDoctor buffer         what is going on in this buffer right now
:LspDoctor capabilities   what the servers here can do, plus workspaces
:LspDoctor probe          whether diagnostics come back at all
:LspDoctor all            the same as no argument, explicitly
:LspDoctor! [report]      any of the above, into a scratch buffer
```

`:Lsp doctor [report]` reaches the same reports through the umbrella verb, and
shares the argument type, so the two cannot offer different names. It always
opens the scratch buffer, and defaults to `startup` rather than `all` — the
question one arrives with is almost always "why is my server not running".

`!` (bang) opens the report in a scratch buffer. It does **not** select a
report; that is what the argument is for.

`:LspDoctor` keeps its own verb rather than folding entirely into `:Lsp`: it is
a diagnostic tool with its own renderer and six reports, not an LSP control
command. It stays registered even with `usrcmds.legacy_aliases = false`.

---

## The scratch buffer

Opened by `!`, by `:Lsp doctor`, or automatically when `auto_open_scratch` is
on and the report is longer than `scratch_threshold` lines. Read-only, with
buffer-local keys:

| Key | Effect |
| --- | ------ |
| `q` | Close the buffer |
| `y` | Yank the entire report to the clipboard |
| `gw` | Write it to `stdpath('cache')/lspdoctor_YYYYMMDD_HHMMSS.md` |
| `?` | Show this key list |

Filetype is `scratch_filetype`, `markdown` by default — the reports are written
as Markdown, so headings and code spans render.

---

## Configuration

Passed through `lsp.nvim`'s `lspdoctor` option, which `setup()` forwards:

```lua
require("lsp").setup({
  lspdoctor = {
    use_notify = false,
    list_limit = 8,
    formatter_priority = { "null-ls", "eslint", "lua_ls" },
  },
})
```

| Name | Type | Default | Description |
| ---- | ---- | ------- | ----------- |
| `use_notify` | boolean | `false` | Render through `vim.notify` instead of `print`. |
| `list_limit` | integer | `10` | Max items per section in the `buffer` report. `capabilities` is uncapped. |
| `show_capabilities` | boolean | `true` | Include the per-client capability table in `capabilities`. |
| `show_workspace` | boolean | `true` | Include workspace folders and `root_dir` checks. |
| `show_tools` | boolean | `true` | Show the external-tools summary. |
| `show_conflicts` | boolean | `true` | Detect overlapping providers (formatting, diagnostics). |
| `formatter_priority` | string[] | `{}` | Order in which the report **ranks** the LSP clients that can format. See [Formatter](#formatter) — it chooses nothing. |
| `semantic_tokens_timeout` | integer (ms) | `300` | Timeout for the semantic-tokens probe in `startup`. |
| `probe_timeout` | integer (ms) | `5000` | How long `probe` waits for diagnostics. Generous on purpose: the answer that matters is "nothing arrived", and a timeout too short for a busy server produces that answer for a pipeline that works. |
| `scratch_filetype` | string | `"markdown"` | Filetype for the scratch buffer. |
| `auto_open_scratch` | boolean | `false` | Open the scratch buffer by itself when the report is long. |
| `scratch_threshold` | integer | `20` | How many lines counts as long. |

`lsp.nvim`'s own defaults differ from these in two places — `list_limit = 8` and
`auto_open_scratch = true` — because they are set in
`lua/lsp/config/DEFAULTS.lua`, which is the single source for what this plugin
ships. The table above is what this module falls back to when nothing is passed.

---

## What the reports show

`buffer` and `capabilities`:

- **Clients** attached to the current buffer
- **Diagnostics** totalled per severity
- **Provider conflicts** — overlapping formatting or diagnostics providers
- **Offset encodings** — unified, or mismatched across clients
- **Formatter** — what conform would run, then the ranked LSP clients

`capabilities` adds:

- **Workspace** — `root_dir`, workspace folders, whether the buffer is under the
  root
- **Capabilities** — the common capability flags per client
- **CodeLens and inlay hints** — supported flags, and a best-effort "enabled"
- **Semantic tokens** — a per-client request probe (ok / error / timeout)
- **Tools** — presence of external binaries and optional plugins

---

## Formatter

The section prints two things, in this order, and the order is the point:

```
Runs: **stylua** (conform)

LSP clients able to format: lua_ls
Preferred among them: **lua_ls** (priority list)
*Report only.* ...
```

`Runs:` is conform's own answer, asked through `list_formatters_to_run`, which
accounts for `stop_after_first` and the LSP-fallback logic. Deciding it a second
time here would be a second opinion, and a report whose second opinion
disagrees with reality is worse than one that says nothing.

**`formatter_priority` ranks the second line and nothing else.** It does not
choose what formats the buffer. That is `lsp.formatter`: conform's chain for the
filetype, with LSP as the fallback conform falls back *to*. On every filetype
conform covers — `lua`, `ts`, `js`, `json`, `css`, `html`, `cs`, `markdown`,
`sh` — no LSP client formats at all, whatever the list says.

The report used to hide that. It printed `Winner: **lua_ls**` on a Lua buffer
that `stylua` was formatting: a diagnostic tool naming the wrong culprit, which
is the one thing a diagnostic tool must not do. The key stays under
`lspdoctor.*` because that namespace was always telling the truth — enforcing
the list would mean moving it to `formatter.*`, and would change nothing
observable until a filetype has two formatting LSP clients and no conform
formatter.

---

## Offset encoding mismatch

If clients attached to the same buffer use different `offset_encoding` values
(`utf-8` against `utf-16`), the report warns and lists which client uses which.
Mixed encodings cause subtle position and edit errors that look like the server
misbehaving.

---

## API

```lua
local doctor = require("lsp.lspdoctor")

doctor.setup(opts)          -- called by lsp.nvim's bootstrap; opts as above
doctor.enable_usercmd()     -- registers :LspDoctor

-- Each report: (bufnr, use_scratch) -> its structured result.
-- bufnr 0 means the current buffer.
doctor.startup(0, false)
doctor.resolve(0, false)
doctor.buffer(0, false)
doctor.capabilities(0, true)   -- into a scratch buffer
doctor.probe(0, false)         -- blocks up to probe_timeout
doctor.all(0, false)           -- { startup = …, resolve = …, capabilities = … }

doctor.MODES                -- { "startup", "resolve", "buffer", "capabilities", "probe", "all" }
doctor.LEGACY_MODES         -- { health = "startup", debug = "resolve", … }
```

`doctor.buffer` and `doctor.capabilities` return an `Lsp.Doctor.Report`:

```lua
---@class Lsp.Doctor.Report
---@field mode '"buffer"'|'"capabilities"'
---@field ok boolean
---@field summary string
---@field sections Lsp.Doctor.Section[]
---@field extras table<string, any>  -- machine-readable extras for tooling
```

`doctor.probe` returns its own shape, because it answers a different kind of
question:

```lua
{
  mode = "probe",
  ok = true,                  -- every attached client answered
  filetype = "lua",
  timeout = 5000,
  path = "…/lspdoctor_probe.lua",   -- named, never written
  summary = "Summary: 1/1 client(s) delivered diagnostics within 5000ms",
  clients = { { name = "lua_ls", id = 1, attached = true, count = 1, elapsed_ms = 21 } },
}
```

When it cannot probe at all it says why in `reason` (`"no snippet"`,
`"no clients"`, `"no probe buffer"`) and leaves `ok` false.

The legacy names are callable too (`doctor.deep(0)` reaches
`doctor.capabilities`), and resolve through `LEGACY_MODES`. There is no legacy
name for `probe`; it never had one.

---

## Troubleshooting

| Symptom | Where to look |
| ------- | ------------- |
| No diagnostics anywhere, and the file might just be clean | `:LspDoctor probe` — it makes a file that cannot be clean |
| No clients shown | `:LspDoctor resolve` — it walks the filetype → server chain and shows which step drops it |
| Server configured but never starts | `:LspDoctor startup` — attempts, executable resolution, last error |
| Formatting picks the wrong tool | The `Runs:` line in `buffer`, and `:Lsp format which` |
| Mixed `offset_encoding` warning | Align the clients, or reduce the set attached to that buffer |
| Semantic-tokens probe times out | Best-effort by design: some servers do not implement the full method, or need specific initialization |
| `probe` times out on a server that works | Raise `probe_timeout`, or check whether that server refuses files outside its project — the report names both possibilities because it cannot tell them apart |
| The plugin itself looks wrong | `:checkhealth lsp` — this module reports on the buffer, that one on the plugin |

---

## Development

Specs live in `TESTS/lsp/lspdoctor_spec.lua`. They **run** every report rather
than probing that a function exists, for a concrete reason: renaming the reports
on 2026-08-29 left `M.all` calling `inspect.deep`, which no longer existed.
`:LspDoctor` with no argument — the most common way to invoke it — raised, and
nothing noticed: 230 specs passed, the smoke test passed, and the command's own
`pcall` swallowed the error. A rename is exactly the change that breaks a call
site nobody exercises, so the specs exercise all of them.

`probe` has its own cases in the same file. They stub the client rather than
starting a server, because what needs proving here is not that lua_ls works —
it is that the report distinguishes "answered" from "silent", refuses a
filetype it has no broken content for, and leaves neither a buffer nor a file
behind. That last one is the case worth having: the probe names a path in your
project directory, and a bug that writes to it would write into the repository
you are working in.

> Verified against a live `lua_ls` on 2026-08-30, twice in one session:
> 1 diagnostic in ~20ms, no file on disk, no buffer left over, and nothing of
> the probe's own left in `vim.diagnostic.get()` afterwards.
