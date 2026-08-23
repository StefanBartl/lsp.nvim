---@module 'lsp.servers.webdev.emmet_ls'
--- Emmet LSP for fast HTML/CSS abbreviation completions.

local lsp = vim.lsp

---@class EmmetServer
local M = {}

---@param shared table|nil
---@param opts table|nil
---@return nil
function M.setup(shared, opts)
  shared = shared or {}
  opts = opts or {}

  if type(lsp.config) == "table" then
    lsp.config("emmet_ls", {
      cmd = { "emmet-ls", "--stdio" }, -- ensure 'emmet-ls' is installed
      filetypes = {
        "html",
        "htmldjango",
        "css",
        "scss",
        "javascript",
        "typescript",
        "javascriptreact",
        "typescriptreact",
      },
      root_markers = { ".git", "package.json" },
      capabilities = shared.capabilities,
      on_attach = function(client, bufnr)
        if type(shared.on_attach) == "function" then
          pcall(shared.on_attach, client, bufnr)
        end
      end,
      settings = {},
    })
    if opts.enable ~= false then
      pcall(vim.lsp.enable, "emmet_ls")
    end
  end
end

return M
