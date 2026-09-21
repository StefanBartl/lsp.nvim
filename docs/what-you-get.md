# What you get with the defaults

| Route | Does |
| --- | --- |
| `:Lsp status` / `info` / `health` | What `setup()` registered, and every warning it worked around |
| `:Lsp servers` | What is set up, and which clients are attached to this buffer |
| `:Lsp doctor <report>` | `startup`, `resolve`, `buffer`, `capabilities`, `probe`, or `all` |
| `:Lsp start` / `stop` / `restart` / `force-restart` / `recover` | The server lifecycle |
| `:Lsp format` | Format now, and toggle format-on-save |
| `:Lsp diag` | Diagnostics into the quickfix or location list |
| `:Lsp workspace` | The workspace-wide diagnostics toggle, with its size gate |
| `:Lsp root show` / `pick` / `add` / `remove` / `list` | Resolution strategy, and LSP's own workspace folders |
| `:Lsp hints [toggle\|on\|off\|status\|clear] [filetype]` | Inlay hints, globally or per filetype |
| `:Lsp lightbulb …` | The code-action indicator, same argument pair |
| `:Lsp winbar …` | The LSP breadcrumb in the winbar, same argument pair |
| `:Lsp implement …` | Implementation markers on interfaces (off by default), same argument pair |
| `:Lsp peek [kind]` | The definition (or type, implementation, declaration) in a floating, editable window |
| `:Lsp autorestart` | Whether a crashed server comes back, and why the last attempt failed |
| `:Lsp log` | The LSP log |

`:Lsp doctor probe` is the odd one out and stays out of `all` deliberately: it
builds a buffer of deliberately broken content, hands it to this buffer's
clients and waits for an answer. That is the only way to tell a clean file from
a dead pipeline — both look like an empty gutter — and the only report that
costs anything.

The full route table, the ~25 flat legacy aliases and every keymap are in
[BINDINGS.md](BINDINGS.md).
