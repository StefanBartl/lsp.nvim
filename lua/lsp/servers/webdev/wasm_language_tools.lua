---@module 'lsp.servers.webdev.wasm_language_tools'
--- WebAssembly Language Tools (WAT Format)

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

  vim.lsp.config("wasm_language_tools", {
    cmd = { "wat_server" },
    filetypes = { "wasm", "wat" },
    root_markers = { ".git", "Cargo.toml", "package.json" },
    capabilities = shared.capabilities,
    on_attach = function(client, bufnr)
      if type(shared.on_attach) == "function" then
        shared.on_attach(client, bufnr)
      end

      -- Semantic Highlighting aktivieren
      if client.server_capabilities then
        client.server_capabilities.semanticTokensProvider = {
          full = true,
          legend = {
            tokenTypes = { "keyword", "operator", "type", "function", "variable" },
            tokenModifiers = { "declaration", "definition" },
          },
        }
      end
    end,
    on_init = shared.on_init,
    settings = {
      ["wasm-language-tools"] = {
        formatter = {
          enabled = true,
        },
      },
    },
  })

  if opts.enable ~= false then
    pcall(vim.lsp.enable, "wasm_language_tools")
  end
end

return M
