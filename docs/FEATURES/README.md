# Features

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
