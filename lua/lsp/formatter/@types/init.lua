---@meta
---@module 'lsp.formatter.@types'
--- Types for `lsp.formatter.build()`.
---
--- Same story as `lsp.languages.@types`: referenced by `formatter/init.lua`,
--- defined nowhere in this repo, and resolving until 2026-09-01 against an
--- older copy of lsp.nvim that lay in a git worktree on the library path.

--- What `build()` accepts. Both fields are defaulted on entry, which is why
--- the parameter itself is optional too.
---@class FormatterOptions
---@field format_on_save? boolean Install the BufWritePre autocmd right away (default `false`).
---@field timeout_ms? integer Passed to Conform and to the LSP fallback (default `1500`).

--- The instance's own bookkeeping, closed over by the returned functions and
--- never handed out.
---@class FormatterState
---@field enabled boolean Whether the on-save autocmd is currently installed.
---@field augroup integer The `LspFormatOnSave` augroup id.

--- What `build()` returns. Every entry answers `true` on success, including
--- the two that are no-ops when already in the requested state.
---@class FormatterApi
---@field format fun(bufnr?: integer): boolean One-shot format: Conform first, LSP fallback, window views preserved.
---@field enable fun(): boolean Install the on-save autocmd.
---@field disable fun(): boolean Remove it.
---@field toggle fun(): boolean Flip it; returns the state it leaves behind.
---@field is_enabled fun(): boolean

return {}
