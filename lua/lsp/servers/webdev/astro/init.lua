---@module 'lsp.servers.webdev.astro'
--- Astro language server, for .astro components.

local notify = require("lib.nvim.notify").create("[lsp.servers.webdev.astro]")

local M = {}

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  shared = shared or {}
  opts = opts or {}

  if type(vim.lsp.config) ~= "table" then
    notify.warn("vim.lsp.config unavailable; skipping Astro LSP")
    return
  end

  -- Extend capabilities with Astro-specific features -- on a copy.
  --
  -- `shared.capabilities` is the one table `lsp.init` builds once and hands to
  -- every server module, so writing into it here is not an Astro decision, it
  -- is a decision for whichever servers happen to be set up afterwards.
  -- Measured with `shared.capabilities = { textDocument = {} }`: after
  -- `astro.setup(shared)` the caller's own table came back carrying
  -- `textDocument.completion.completionItem.snippetSupport = true`, and
  -- `rawequal(shared.capabilities, vim.lsp.config["astro"].capabilities)` was
  -- true -- so Astro also had no capability set of its own to extend.
  local caps = vim.deepcopy(shared.capabilities or vim.lsp.protocol.make_client_capabilities())

  -- Auto-close tags support
  if not caps.textDocument then
    caps.textDocument = {}
  end
  if not caps.textDocument.completion then
    caps.textDocument.completion = {}
  end
  if not caps.textDocument.completion.completionItem then
    caps.textDocument.completion.completionItem = {}
  end

  caps.textDocument.completion.completionItem.snippetSupport = true

  vim.lsp.config("astro", {
    cmd = { "astro-ls", "--stdio" },

    filetypes = { "astro" },

    root_markers = {
      "package.json",
      "tsconfig.json",
      "astro.config.mjs",
      "astro.config.ts",
      "astro.config.js",
      ".git",
    },

    capabilities = caps,

    init_options = {
      typescript = {
        tsdk = vim.fn.stdpath("data")
          .. "/mason/packages/typescript-language-server/node_modules/typescript/lib",
      },
    },

    on_attach = function(client, bufnr)
      if type(shared.on_attach) == "function" then
        shared.on_attach(client, bufnr)
      end
    end,

    on_init = shared.on_init,

    settings = {
      astro = {
        css = {
          validate = true,
          lint = {
            unknownAtRules = "ignore",
          },
        },
        html = {
          completions = {
            autoClosingTags = true,
          },
        },
      },
    },
  })

  if opts.enable ~= false then
    pcall(vim.lsp.enable, "astro")
  end
end

return M
