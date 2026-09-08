# lsp.servers.marksman

Marksman (Markdown) via native LSP config/enable, with a scoped diagnostics
filter. `root_dir` is written to accept both legacy lspconfig-style callers
(`fname: string`) and the new native `vim.lsp` pipeline (`bufnr: integer,
cb?: fun(root: string)`), avoiding a "file: expected string, got number"
error.

`root_dir` also refuses to start a client for buffers with no real backing
file (`buftype ~= ""`). Marksman only accepts `file://` URIs built from an
actual path; a scratch/preview buffer with `filetype = "markdown"` but a
synthetic name -- e.g. mdview.nvim's read-only tab preview, named
`[mdview preview] foo.md (12)` -- turns into a URI with no parsable host and
crashes the server on `textDocument/didOpen` ("Invalid URI: The hostname
could not be parsed."). Not calling the `on_dir` callback for such buffers
stops the native pipeline from starting a client for them at all, so no
didOpen is ever sent.
