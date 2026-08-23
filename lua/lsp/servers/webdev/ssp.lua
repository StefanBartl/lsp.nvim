---@module 'lsp.servers.webdev.ssp'
--- Server-Side Processing / Template Language Support

local M = {}

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  shared = shared or {}
  opts = opts or {}

  if type(vim.lsp.config) ~= "table" then
    return
  end

  -- Falls SSP = Server-Side Processing mit HTML/PHP/ERB
  -- Verwende html + emmet für grundlegendes Templating
  vim.lsp.config("html", {
    -- Direct `node <entry>` instead of Mason's .cmd shim: the shim makes
    -- cmd.exe the child and node.exe a grandchild, and on quit Neovim waits
    -- forever for a pipe the grandchild still holds. Measured and confirmed --
    -- see lsp.core.mason_node and docs/ROADMAP/QuitCrash_NVIM.md. Falls back
    -- to the shim when the entry point cannot be resolved.
    cmd = require("lsp.core.mason_node").cmd_or(
      "vscode-langservers-extracted",
      { "vscode-html-language-server", "--stdio" },
      { "--stdio" },
      "vscode-html-language-server"
    ),
    filetypes = { "html", "ssp", "ejs", "erb" },
    root_markers = { ".git", "package.json" },
    capabilities = shared.capabilities,
    on_attach = shared.on_attach,
    on_init = shared.on_init,
  })

  if opts.enable ~= false then
    pcall(vim.lsp.enable, "html")
  end
end

return M
