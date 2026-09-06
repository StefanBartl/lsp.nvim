---@module 'lsp.languages.webdev.typescript'
--- TypeScript/JS QoL: organizes imports synchronously on every BufWritePre
--- for `*.ts`/`*.tsx`/`*.js`/`*.jsx`, via `lsp.core.util.organize_imports_sync`
--- (a direct, blocking LSP code-action request) rather than the async
--- `vim.lsp.buf.code_action` path -- see that function's docstring for why the
--- async path is wrong on BufWritePre.

local M = {}

local api = vim.api
local Autocmd = require("lib.nvim.bindings.autocmd")
local util = require("lsp.core.util")

---@return nil
function M.enable()
  local grp = api.nvim_create_augroup("LangTs", { clear = true })
  Autocmd.create("BufWritePre", function(ev)
    pcall(util.organize_imports_sync, ev.buf, "source.organizeImports")
  end, {
    group = grp,
    pattern = { "*.ts", "*.tsx", "*.js", "*.jsx" },
  })
end

---@type Lsp.Languages.ConfiguredLangs.Webdev.Typescript.Module
return M
