# lsp.formatter

Formatter API with an on-save toggle, Conform-first strategy, and view
preservation.

Cross-platform. The line that used to stand here — "Linux/macOS only — no
Windows-specific branches" — was never true of `conform.lua`, which branches on
`is_windows` for the PATH separator and the `.cmd` suffix on Mason binaries, in
a config whose main machine runs Windows. `init.lua` carries no OS-specific code
because it needs none, not because the module is Unix-only.
