# lsp.servers.marksman

Marksman (Markdown) via native LSP config/enable, with a scoped diagnostics
filter. `root_dir` is written to accept both legacy lspconfig-style callers
(`fname: string`) and the new native `vim.lsp` pipeline (`bufnr: integer,
cb?: fun(root: string)`), avoiding a "file: expected string, got number"
error.
