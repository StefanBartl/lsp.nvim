---@module 'lsp.servers.bashls'
--- Bash/sh/zsh language server via native LSP config/enable.
--- Requires bash-language-server in PATH (Mason: bash-language-server).
--- Diagnostics are powered by shellcheck when available.

local notify = require("lib.nvim.notify").create("[lsp.servers.bashls]")

local M = {}

---@type string|nil
local _shellcheck_path = nil

---@internal
--- Absolute path to shellcheck, or `""` when it is not on PATH -- which is what
--- `bashIde.shellcheckPath` wants either way.
---
--- Memoised, and deliberately not called while the config is being registered:
--- a *failing* `exepath()` walks every PATH entry against every PATHEXT suffix
--- (measured here: 68 x 11 stats, 25-200ms depending on cache warmth) and
--- Neovim caches nothing. Paid at startup that is pure loss on every session
--- that never opens a shell script; paid from `before_init` it is paid once,
--- by the session that actually starts the server.
---@return string
local function shellcheck_path()
  if _shellcheck_path == nil then
    _shellcheck_path = vim.fn.exepath("shellcheck")
  end
  return _shellcheck_path
end

---Build LSP settings for bash-language-server
---@return table
local function settings()
  return {
    bashIde = {
      -- shellcheckPath is filled in by before_init, see shellcheck_path().
      -- When 'explainshell' is running locally, you can set:
      -- explainshellEndpoint = "http://localhost:5000",
      trace = { server = "off" }, -- "off" | "messages" | "verbose"
      includeAllWorkspaceSymbols = true,
      globPattern = "*@(.sh|.inc|.bash|.zsh|.ksh|.mksh)",
    },
  }
end

---@internal
--- Resolve the shellcheck path into the settings the client is about to send.
---
--- Mutates `config.settings` **in place** on purpose. `vim.lsp.Client.create()`
--- captures `settings = config.settings` before `before_init` runs, and the
--- `workspace/didChangeConfiguration` notification is sent from that captured
--- reference -- so reassigning `config.settings` here (what `:h
--- vim.lsp.ClientConfig` shows for other fields) would be dropped, while
--- writing into the existing table is seen.
---@param _params lsp.InitializeParams
---@param config vim.lsp.ClientConfig
---@return nil
local function before_init(_params, config)
  local s = config.settings
  if type(s) ~= "table" then
    return
  end
  s.bashIde = s.bashIde or {}
  -- If shellcheck is present, bashls will use it automatically; this is an
  -- explicit override to be robust, and an empty string when it is absent.
  s.bashIde.shellcheckPath = shellcheck_path()
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
    before_init = before_init,
    settings = settings(),
  })

  if opts.enable ~= false then
    pcall(vim.lsp.enable, "bashls")
  end
end

--- The `before_init` hook, exposed for the spec suite.
---@private
M._before_init = before_init

return M
