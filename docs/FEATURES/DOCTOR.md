# Doctor

`:LspDoctor` in six reports — `startup`, `resolve`, `buffer`, `capabilities`,
`probe`, `all` — answering the per-buffer questions: which servers are
expected, which are running, whether their executables resolve, where the
filetype → server chain breaks, what the clients advertise, and where two
providers overlap.

Five of them observe. `probe` provokes: it hands the attached clients a buffer
they cannot parse and reports whether diagnostics come back — the only way to
tell a clean file from a dead pipeline, since both look like an empty gutter.
It is not part of `all`, because it is the only report that costs anything.

Reachable both ways: `:LspDoctor [mode]` and `:Lsp doctor [mode]` take the same
mode list, from the same table, so the two cannot come to offer different
report names. The bare `:LspDoctor` runs `all`; the bare `:Lsp doctor` runs
`startup`, because that route opens a scratch split and the question one
arrives with is almost always "why is my server not running".

- **Module:** `lspdoctor/`
- **Config:** `lspdoctor`, `lspdoctor.probe_timeout`
- **Commands:** `:LspDoctor[!] [mode]`, `:Lsp doctor [mode]`
