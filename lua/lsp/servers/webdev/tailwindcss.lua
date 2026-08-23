---@module 'lsp.servers.webdev.tailwindcss'
--- TailwindCSS Language Server

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

  vim.lsp.config("tailwindcss", {
    -- Direct `node <entry>` instead of Mason's .cmd shim: the shim makes
    -- cmd.exe the child and node.exe a grandchild, and on quit Neovim waits
    -- forever for a pipe the grandchild still holds. Measured and confirmed --
    -- see lsp.core.mason_node and docs/ROADMAP/QuitCrash_NVIM.md. Falls back
    -- to the shim when the entry point cannot be resolved.
    cmd = require("lsp.core.mason_node").cmd_or(
      "tailwindcss-language-server",
      { "tailwindcss-language-server", "--stdio" },
      { "--stdio" }
    ),
    filetypes = {
      "astro",
      "html",
      "css",
      "scss",
      "javascript",
      "javascriptreact",
      "typescript",
      "typescriptreact",
      "vue",
      "svelte",
    },
    root_markers = { "tailwind.config.js", "tailwind.config.ts", "tailwind.config.cjs", ".git" },
    capabilities = shared.capabilities,
    on_attach = shared.on_attach,
    on_init = shared.on_init,
    settings = {
      tailwindCSS = {
        experimental = {
          classRegex = {
            { "cva\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]" },
            { "cx\\(([^)]*)\\)", "(?:'|\"|`)([^']*)(?:'|\"|`)" },
          },
        },
        validate = true,
        lint = {
          cssConflict = "warning",
          invalidApply = "error",
          invalidScreen = "error",
          invalidVariant = "error",
          invalidConfigPath = "error",
          invalidTailwindDirective = "error",
          recommendedVariantOrder = "warning",
        },
      },
    },
  })

  if opts.enable ~= false then
    pcall(vim.lsp.enable, "tailwindcss")
  end
end

return M
