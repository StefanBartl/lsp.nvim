# lsp.completion.personal_names

nvim-cmp source completing this config's ~30 dotted personal-plugin names
(e.g. "documentation.nvim", "markdown.nvim" — see `plugins.personal.list`)
as one atomic candidate each. The default cmp keyword pattern splits words
at ".", so typing "do" would otherwise only ever surface "documentation" (a
plain buffer word), never the full plugin name.
