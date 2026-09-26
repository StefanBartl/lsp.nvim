---@module 'lsp.servers.webdev.html'
--- Robust HTML language server definition with Mason/Windows fallbacks.
--- This module tries multiple candidate executables and falls back to Mason's bin folder.
--- It disables server formatting by default to avoid conflicts with external formatters.

local lsp = vim.lsp
local executable = require("lib.nvim.cross.executable")

---@class HtmlServer
local M = {}

---@param shared table|nil  -- { capabilities?:table, on_attach?:fun(client,bufnr), on_init?:fun(client,init_result):boolean }
---@param opts table|nil    -- { enable?: boolean, cmd?: string[] }
---@return nil
function M.setup(shared, opts)
  shared = shared or {}
  opts = opts or {}

  ---@type string[]
  local candidates = opts.cmd
    or {
      "vscode-html-language-server",
      "html-languageserver",
      "html-lsp",
    }

  -- Try to resolve an executable either via exepath or Mason bin dir
  local function resolve_exec(name)
    if not name or name == "" then
      return nil
    end
    return executable.path(name) or executable.mason_bin(name)
  end

  ---The argv to start: the first candidate that resolves, else the candidate
  ---list itself, to surface a meaningful error if nothing is installed.
  ---@return string[]
  local function resolve_cmd()
    for i = 1, #candidates do
      local p = resolve_exec(candidates[i])
      if p then
        return { p, "--stdio" }
      end
    end
    return candidates
  end

  -- Resolved when the server is started (first html buffer), not here: with
  -- three candidate names of which none is installed, resolving in setup() cost
  -- ~130 ms of $PATH walks in the synchronous startup phase. `cmd` may be a
  -- function that starts the RPC client itself (Neovim >= 0.11); an older
  -- Neovim without it keeps the eager resolution.
  ---@type string[]|fun(dispatchers: table, config: table): table
  local cmd
  if type(lsp.rpc) == "table" and type(lsp.rpc.start) == "function" then
    cmd = function(dispatchers, config)
      return lsp.rpc.start(resolve_cmd(), dispatchers, {
        cwd = config.cmd_cwd,
        env = config.cmd_env,
        detached = config.detached,
      })
    end
  else
    cmd = resolve_cmd()
  end

  if type(lsp.config) ~= "table" then
    return
  end

  ---@type string[]
  local filetypes = { "html", "htmldjango", "djangohtml", "eruby" }

  lsp.config("html", {
    cmd = cmd,
    filetypes = filetypes,
    root_markers = { "index.html", ".git", "package.json", "vite.config.js" },
    capabilities = shared.capabilities,
    on_attach = function(client, bufnr)
      if type(shared.on_attach) == "function" then
        pcall(shared.on_attach, client, bufnr)
      end
      -- Prefer external formatters (prettier/conform). Avoid LSP formatting conflicts.
      if
        client
        and client.server_capabilities
        and client.server_capabilities.documentFormattingProvider
      then
        client.server_capabilities.documentFormattingProvider = false
      end
    end,
    -- `workspace/diagnostic/refresh` is answered for *this client only*.
    --
    -- This used to be an assignment to `vim.lsp.handlers[...]` from `on_init`,
    -- which is the global table every client falls back to
    -- (`Client:_resolve_handler` = `self.handlers[m] or vim.lsp.handlers[m]`).
    -- Neovim ships a real default for that method -- measured on 0.12.2:
    -- `type(vim.lsp.handlers["workspace/diagnostic/refresh"]) == "function"`
    -- before html's `on_init`, a *different* function after it -- so the first
    -- html buffer of a session silently replaced pull-diagnostics refresh with
    -- a no-op for ts_ls, gopls and everything else attached at the time.
    --
    -- A per-config `handlers` entry is checked before the global one, so the
    -- same suppression now costs exactly the client that asked for it.
    handlers = {
      ["workspace/diagnostic/refresh"] = function()
        return vim.NIL
      end,
    },
    on_init = shared.on_init,
    settings = {
      html = {
        suggest = { html5 = true },
        format = { enable = false },
      },
    },
  })

  if opts.enable ~= false then
    pcall(lsp.enable, "html")
  end
end

return M
