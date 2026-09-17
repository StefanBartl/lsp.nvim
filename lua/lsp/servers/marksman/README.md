# lsp.servers.marksman

Marksman (Markdown) via native LSP config/enable, with a scoped diagnostics
filter. The `root_dir` registered with `vim.lsp.config` has the native
pipeline's shape and only that one: `(bufnr: integer, on_dir: fun(root:
string))`. It reads `vim.bo[bufnr].buftype` before delegating, so a
legacy lspconfig-style `root_dir(fname)` call raises -- measured,
`init.lua:53: Unknown option '<path>/README.md'`.

The polymorphism lives one level down, in `rootresolver.lua` and the
`lib.nvim.fs.polymorphic_rootresolver` it wraps: *that* resolver takes either
a buffer number or a filename, with an optional callback, and is what keeps a
"file: expected string, got number" out of the native pipeline. Reach for it,
not for `vim.lsp.config["marksman"].root_dir`, if a root is what you want.

`root_dir` also refuses to start a client for buffers with no real backing
file (`buftype ~= ""`). Marksman only accepts `file://` URIs built from an
actual path; a scratch/preview buffer with `filetype = "markdown"` but a
synthetic name -- e.g. mdview.nvim's read-only tab preview, named
`[mdview preview] foo.md (12)` -- turns into a URI with no parsable host and
crashes the server on `textDocument/didOpen` ("Invalid URI: The hostname
could not be parsed."). Not calling the `on_dir` callback for such buffers
stops the native pipeline from starting a client for them at all, so no
didOpen is ever sent.
