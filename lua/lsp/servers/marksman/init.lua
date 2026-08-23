---@module 'lsp.servers.marksman'
--- Marksman (Markdown) via native LSP config/enable with scoped diagnostics filter.
--- This version makes `root_dir` compatible with both legacy lspconfig-style
--- callers (fname: string) and the new native `vim.lsp` pipeline
--- (bufnr: integer, cb?: fun(root:string)), preventing "file: expected string, got number".
---
--- It also keeps a narrow diagnostics filter to suppress "missing doc link" noise.

local lsp = vim.lsp
local cfg = require("lsp.servers.marksman.config")
local diagnostics_handler = require("lsp.servers.marksman.diagnostics_handler")
local root_resolver = require("lsp.servers.marksman.rootresolver")

---@class MarksmanServer
local M = {}

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

--- Setup Marksman via native `vim.lsp.config()/enable()`.
--- @param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
--- @param opts { enable?: boolean }|nil
--- @return nil
function M.setup(shared, opts)
  shared = shared or {}
  opts = opts or {}

  -- Only proceed if the native config API is available (Neovim 0.11+)
  if type(lsp.config) == "table" then
    lsp.config("marksman", {
      cmd = { "marksman", "server" },
      filetypes = cfg.filetypes,
      -- Important: the resolver must accept (bufnr, cb) in the new pipeline.
      root_dir = root_resolver(),
      capabilities = shared.capabilities,
      on_attach = shared.on_attach,
      on_init = shared.on_init,
      handlers = {
        ["textDocument/publishDiagnostics"] = diagnostics_handler.make_handler(),
        ["textDocument/codeAction"] = require("lsp.servers.marksman.code_action_handler")(),
      },
      -- Marksman benefits from multi-file workspaces for link resolution
      single_file_support = false,
    })

    if opts.enable ~= false then
      -- Enable now; attaches on FileType/BufReadPost per native pipeline
      pcall(vim.lsp.enable, "marksman")
    end
  end
end

return M
