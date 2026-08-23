---@module 'lsp.servers.gopls'
--- Go language server via native LSP config/enable.

local lsp = vim.lsp

---@class GoplsServer
local M = {}

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  shared = shared or {}
  opts = opts or {}

  if type(vim.lsp.config) == "table" then
    lsp.config("gopls", {
      cmd = { "gopls" },
      filetypes = { "go", "gomod", "gosum" },
      root_markers = { "go.work", "go.mod", ".git" },
      capabilities = shared.capabilities,
      on_attach = shared.on_attach,
      on_init = shared.on_init,
      settings = {
        gopls = {
          usePlaceholders = true,
          staticcheck = true,
          gofumpt = true,
          analyses = { unusedparams = true, shadow = true },
          memoryMode = "DegradeClosed",
          directoryFilters = { "-**/node_modules", "-**/dist", "-**/.git" },
        },
      },
    })
    if opts.enable ~= false then
      pcall(lsp.enable, "gopls")
    end
  end
end

return M
