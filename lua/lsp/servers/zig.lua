---@module 'lsp.servers.zig'
--- zls via native LSP config/enable (Neovim ≥ 0.11).

local lsp = vim.lsp

---@class ZigServer
local M = {}

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  shared = shared or {}
  opts = opts or {}

  if type(vim.lsp.config) == "table" then
    lsp.config("zls", {
      cmd = { "zls" },
      filetypes = { "zig", "zir" },
      root_markers = { "build.zig", "zls.json", ".git" },
      capabilities = shared.capabilities,
      on_attach = shared.on_attach,
      on_init = shared.on_init,
    })
    if opts.enable ~= false then
      pcall(lsp.enable, "zls")
    end
  end
end

return M
