---@meta
---@module 'lsp.integrations.mason.@types'

---@alias Cfg.Mason.EnsureMap table<string, boolean>

---@class Cfg.Mason.EnsureSession
---@field open boolean
---@field pending integer
---@field results table<string, table<string,string[]>>   -- results[kind][category] = { "name (reason)", ... }
---@field installed table<string,string[]>
---@field already table<string,string[]>

return {}
