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

## Env-variable links

marksman resolves a link target relative to the document, so
`[x]($REPOS_DIR/a/b.md)` is a folder named `$REPOS_DIR` to it: no definition, no
hover, and "Link to non-existent document" for a file that exists. The blanket
`suppress_missing_doc_links` below hid the false alarm together with every real
broken link.

`languages.env_links` (default on) changes that in two places. This module's
diagnostics filter asks `lsp.core.env_links.verdict` first: an env link whose
file exists is dropped, and anything the resolver cannot judge -- an undefined
variable -- falls through to the rules unchanged. One whose file does not exist
is **kept** (annotated with the path it was looked up at) even though the
blanket rule would hide it -- unless the in-process client is running, which
reports the broken env links itself (the file *and* the `#fragment`, which
marksman never reports for any link), and then marksman's duplicate is dropped.
Definition, hover and those diagnostics come from a separate in-process client
(`lsp.core.env_links_server`), because a handler in this server's config would
only reach requests that use client handlers, and `vim.lsp.buf.definition` does
not. See `docs/configuration.md` (`languages.env_links`).
