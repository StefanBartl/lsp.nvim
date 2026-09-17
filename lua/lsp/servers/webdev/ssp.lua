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

  -- SSP here means server-side processing (HTML/PHP/ERB), so the html language
  -- server covers the templating well enough.
  --
  -- Registered under "ssp", not "html". Both this module and
  -- `lsp.servers.webdev.html` used to call `vim.lsp.config("html", …)`, and
  -- `vim.lsp.config()` merges into whatever is already under that key, so
  -- whichever ran second rewrote the other's entry in place. Measured with both
  -- set up in `servers` order (html, then ssp):
  --
  --   filetypes    { html, htmldjango, djangohtml, eruby } -> { html, ssp, ejs, erb }
  --   root_markers { index.html, .git, package.json, vite.config.js }
  --                                                       -> { .git, package.json }
  --   on_attach    html's wrapper (which turns
  --                documentFormattingProvider off so prettier/conform own
  --                formatting)                            -> plain shared.on_attach
  --
  -- Nothing said so; the html server just quietly stopped covering htmldjango
  -- and started fighting the external formatter. Its own name keeps the two
  -- configs apart, and `html` is dropped from the filetypes below so the two
  -- do not both start a client for the same buffer.
  vim.lsp.config("ssp", {
    -- Direct `node <entry>` instead of Mason's .cmd shim: the shim makes
    -- cmd.exe the child and node.exe a grandchild, and on quit Neovim waits
    -- forever for a pipe the grandchild still holds. Measured and confirmed --
    -- see lsp.core.mason_node. Falls back
    -- to the shim when the entry point cannot be resolved.
    cmd = require("lsp.core.mason_node").cmd_or(
      "vscode-langservers-extracted",
      { "vscode-html-language-server", "--stdio" },
      { "--stdio" },
      "vscode-html-language-server"
    ),
    -- `erb` is gone with `html`, for the same reason and one more. Neovim never
    -- sets a filetype called `erb` -- measured: `vim.filetype.match{ filename =
    -- "a.erb" }` is `eruby` -- so the entry matched nothing, and the name it
    -- meant is one `lsp.servers.webdev.html` already claims, which would put
    -- two html servers on one .erb buffer.
    --
    -- `ssp` and `ejs` are not filetypes Neovim sets either (both are `<none>`
    -- from `vim.filetype.match`), but unlike `erb` they have no already-served
    -- spelling to collide with: they are the names a host's own `ftdetect` or
    -- `vim.filetype.add` gives these templates, and this config is there for
    -- when it does. It is opt-in (`servers` does not list it by default).
    filetypes = { "ssp", "ejs" },
    root_markers = { ".git", "package.json" },
    capabilities = shared.capabilities,
    on_attach = shared.on_attach,
    on_init = shared.on_init,
  })

  if opts.enable ~= false then
    pcall(vim.lsp.enable, "ssp")
  end
end

return M
