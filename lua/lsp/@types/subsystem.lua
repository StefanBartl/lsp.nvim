---@meta
---@module 'lsp.@types.subsystem'

require("lsp.@types.vim_lsp")

---@class LspMod.Init
---@field ensure_installing boolean|nil

---@class LspMod.Client.Capabilities
---@field codeLensProvider table|nil
---@field inlayHintProvider table|nil
---@field semanticTokensProvider table|nil
---@field documentFormattingProvider boolean|nil
---@field documentRangeFormattingProvider boolean|nil
---@field completionProvider table|nil
---@field definitionProvider boolean|nil
---@field codeActionProvider boolean|nil
---@field textDocumentSync any
---@field positionEncoding string|nil
---@field diagnosticProvider boolean|nil
---@field publishDiagnosticsProvider boolean|nil

---@class LspMod.Client
---@field id integer
---@field name string
---@field offset_encoding string|nil
---@field root_dir string|nil
---@field workspace_folders { name?: string, uri?: string }[]|nil
---@field config table|nil
---@field supports_method fun(self: LspMod.Client, method: string): boolean
---@field server_capabilities LspMod.Client.Capabilities|nil
---@field request fun(self: LspMod.Client, method: string, params: table, callback: fun(err:any, res:any), bufnr: integer)

---@alias LspMod.PositionEncoding "utf-8"|"utf-16"|"utf-32"

---@class LspMod.Position
---@field line integer        # 0-based line index
---@field character integer  # character offset in the given positionEncoding

---@class LspMod.Range
---@field start LspMod.Position
---@field ["end"] LspMod.Position

---@class LspMod.TextDocumentIdentifier
---@field uri string          # document URI (e.g. file:///...)

---@class LspMod.CodeAction.Context
---@field diagnostics table[]|nil
---@field only string[]|nil
---@field triggerKind integer|nil

---@class LspMod.CodeAction.Params
---@field textDocument LspMod.TextDocumentIdentifier
---@field range LspMod.Range
---@field context LspMod.CodeAction.Context
---@field workDoneToken any|nil
---@field partialResultToken any|nil

---@class LspMod.AttachOptions
---@field use_workspace_diagnostics boolean
---@field use_lazydev boolean

---@class LspMod.AttachApi
---@field on_attach fun(client: any, bufnr:integer)
---@field on_init   fun(client: any, _):boolean

return {}
