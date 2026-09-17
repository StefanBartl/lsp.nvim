# lsp.tools.eslint_prettier.autocmds

Attaches `BufWritePost` autocmds for lint+format, with toggle support.
Post rather than Pre: both tools rewrite the file on disk, so running them
before Neovim's own write has the child and the editor holding the same path
open at once -- a sharing violation on Windows, measured on a 25.8 MB buffer.
