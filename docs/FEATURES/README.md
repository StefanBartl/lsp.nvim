# Features

Everything LSP-related lives under one root and answers to one verb, in three
layers — core, integrations, pack — with the arrows pointing one way only.
[architecture.md](../architecture.md) has the argument.

| Area | Does |
| --- | --- |
| **Servers** | A registry resolving configured names to modules, merging capabilities, owning attach, and bringing a crashed server back with a bounded backoff |
| **Configuration** | Four layers — defaults, a `preset` profile, your `setup()` options, a per-project `.nvim-lsp.json` — and every warning names the layer the bad value came from |
| **Diagnostics** | Into the quickfix or location list, with a leading-edge throttle on `publishDiagnostics`, and a workspace-wide toggle that refuses above its size gate rather than freezing the editor |
| **Formatter** | conform-first with an LSP fallback, and a format-on-save toggle this plugin owns rather than conform |
| **In-buffer indicators** | Inlay hints and a code-action indicator, each global plus per-filetype, both filtered so they carry information |
| **Roots and workspaces** | A scope switch for the servers that resolve a root themselves, and LSP's own multi-root mechanism for the rest |
| **`:LspDoctor`** | Six per-buffer reports. Five observe; `probe` provokes, which is the only way to tell a clean file from a dead pipeline |
| **Tools and integrations** | ESLint/Prettier, signature help, type lookup, deprecation help, one picker backend, and a context menu built from the resolved keymap catalogue |

What lsp.nvim actually does, by area — and, where it matters, why it is shaped
that way. Each page below is one theme; the reference detail lives elsewhere:
[configuration.md](../configuration.md) for the options,
[commands.md](../commands.md) for the `:Lsp` routes, and
[BINDINGS.md](../BINDINGS.md) for every key, command and autocommand at a
glance.

| Page | What it covers |
|---|---|
| [CONFIGURATION.md](CONFIGURATION.md) | The four option layers — defaults, preset, `setup()`, project file — and which one a warning came from. |
| [SERVERS.md](SERVERS.md) | Getting servers up and keeping them there: the registry, capabilities, attach handling, crash recovery, per-language setup. |
| [DIAGNOSTICS.md](DIAGNOSTICS.md) | Diagnostics into a list, navigation, the publish throttle, and the workspace-wide toggle with its size gate. |
| [FORMATTER.md](FORMATTER.md) | Conform-first with an LSP fallback, and a format-on-save toggle this plugin owns rather than conform. |
| [INDICATORS.md](INDICATORS.md) | The two per-buffer displays: inlay hints and the code-action indicator, both global plus per-filetype. |
| [WORKSPACE.md](WORKSPACE.md) | Two mechanisms under one word: the root-scope switch, and LSP's own workspace folders. |
| [DOCTOR.md](DOCTOR.md) | `:LspDoctor` in six reports — five that observe, one that provokes. |
| [TOOLS.md](TOOLS.md) | The extras behind their own switches, the single picker backend, and the completion source. |
| [INTEGRATIONS.md](INTEGRATIONS.md) | What the adapters add on top of a third-party plugin: the context menu, and the winbar breadcrumb depth. |

## Where to start

[CONFIGURATION.md](CONFIGURATION.md) first: the layer order it describes is why
a setting behaves the way it does on every other page, and why every warning
this plugin emits names a layer.
