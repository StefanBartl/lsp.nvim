---@meta
---@module 'lsp.@types.subsystem'

---@class LspMod.Init
---@field ensure_installing boolean|nil

-- The client and protocol shapes below used to be declared here under
-- `LspMod.*` names. Neovim carries every one of them, and more precisely:
-- `vim.lsp.Client` has each field this file listed, `lsp.ServerCapabilities`
-- is the full capability set rather than the eleven keys we happened to use,
-- and `lsp.Position`/`lsp.Range`/`lsp.TextDocumentIdentifier`/
-- `lsp.CodeActionParams` come straight from the protocol meta.
--
-- Keeping a second name for the same shape is not free: LuaLS decides class
-- assignability by NAME, not by shape, so a parallel `LspMod.Client` can never
-- be assigned from a `vim.lsp.Client` however identical the fields are. That
-- collision is what `languages/webdev/typescript.lua` ran into three times.

---@class LspMod.AttachOptions
---@field use_workspace_diagnostics boolean
---@field use_lazydev boolean

---@class LspMod.AttachApi
---@field on_attach fun(client: any, bufnr:integer)
---@field on_init   fun(client: any, _):boolean

return {}
