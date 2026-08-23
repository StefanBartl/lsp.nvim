---@module 'lsp.servers.bashls'
--- Bash/sh/zsh language server via native LSP config/enable.
--- Requires bash-language-server in PATH (Mason: bash-language-server).
--- Diagnostics are powered by shellcheck when available.

local notify = require("lib.nvim.notify").create("[lsp.servers.bashls]")

local M = {}

---Build LSP settings for bash-language-server
---@return table
local function settings()
  return {
    bashIde = {
      -- If shellcheck is present, bashls will use it automatically;
      -- below paths are optional overrides to be explicit and robust.
      shellcheckPath = vim.fn.exepath("shellcheck"), -- empty string if not found
      -- When 'explainshell' is running locally, you can set:
      -- explainshellEndpoint = "http://localhost:5000",
      trace = { server = "off" }, -- "off" | "messages" | "verbose"
      includeAllWorkspaceSymbols = true,
      globPattern = "*@(.sh|.inc|.bash|.zsh|.ksh|.mksh)",
    },
  }
end

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  shared = shared or {}
  opts = opts or {}

  if type(vim.lsp.config) ~= "table" then
    notify.warn("vim.lsp.config is unavailable; cannot configure bashls")
    return
  end

  -- bashls understands POSIX sh and bash; for zsh, completion/diagnostics are useful
  -- but not 100% semantisch exakt. Das ist ein pragmatischer Kompromiss.
  vim.lsp.config("bashls", {
    cmd = { "bash-language-server", "start" },
    filetypes = { "sh", "bash", "zsh", "ksh" },
    root_markers = { ".git", "shell.nix" },
    capabilities = shared.capabilities,
    on_attach = shared.on_attach,
    on_init = shared.on_init,
    settings = settings(),
  })

  if opts.enable ~= false then
    pcall(vim.lsp.enable, "bashls")
  end
end

return M
