---@module 'lsp.servers.webdev.ts_ls'
--- TypeScript/JavaScript server via native LSP config/enable.

---@class TsLsServer
local M = {}

local lsp = vim.lsp

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  shared = shared or {}
  opts = opts or {}

  if type(lsp.config) == "table" then
    lsp.config("ts_ls", {
      -- Direct `node <entry>` instead of Mason's .cmd shim: the shim makes
      -- cmd.exe the child and node.exe a grandchild, and on quit Neovim waits
      -- forever for a pipe the grandchild still holds. Measured and confirmed --
      -- see lsp.core.mason_node and docs/ROADMAP/QuitCrash_NVIM.md. Falls back
      -- to the shim when the entry point cannot be resolved.
      cmd = require("lsp.core.mason_node").cmd_or(
        "typescript-language-server",
        { "typescript-language-server", "--stdio" },
        { "--stdio" }
      ),
      filetypes = { "typescript", "typescriptreact", "tsx", "javascript", "javascriptreact" },
      root_markers = { "tsconfig.json", "jsconfig.json", "package.json", ".git" },
      capabilities = shared.capabilities,
      on_attach = function(client, bufnr)
        if type(shared.on_attach) == "function" then
          shared.on_attach(client, bufnr)
        end
        -- Per-buffer diagnostic tuning can be set globally elsewhere via vim.diagnostic.config
      end,
      on_init = shared.on_init,
      settings = {
        javascript = { preferences = { includeCompletionsForModuleExports = true } },
        typescript = {
          preferences = {
            includeInlayParameterNameHints = "literals",
            includeInlayFunctionLikeReturnTypeHints = true,
          },
        },
      },
    })
    if opts.enable ~= false then
      pcall(lsp.enable, "ts_ls")
    end
  end
end

return M
