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

  local exe = nil
  for i = 1, #candidates do
    local p = resolve_exec(candidates[i])
    if p then
      exe = p
      break
    end
  end

  local cmd
  if exe then
    cmd = { exe, "--stdio" }
  else
    -- keep candidate list to surface meaningful error if nothing found
    cmd = candidates
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
    on_init = function(client, init_result)
      -- Register handler for workspace/diagnostic/refresh (html LSP sends this)
      if client.server_capabilities then
        vim.lsp.handlers["workspace/diagnostic/refresh"] = function()
          -- No-op: ignore this request
          return vim.NIL
        end
      end

      if type(shared.on_init) == "function" then
        return shared.on_init(client, init_result)
      end
      return true
    end,
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
