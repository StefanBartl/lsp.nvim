---@module 'lsp.tools.eslint_prettier.autocmds'
--- Attach autocmds (BufWritePre) for lint+format with toggle support.
local api = vim.api
local core = require("lsp.tools.eslint_prettier.core.find_root")
local check = require("lsp.tools.eslint_prettier.core.check_config")
local eslint_fix = require("lsp.tools.eslint_prettier.eslint.fix")
local prettier_fmt = require("lsp.tools.eslint_prettier.prettier.format")
local Autocmd = require("lib.nvim.autocmd")

local M = {}

---@param ctx table plugin context with fields: filetypes (string[]), _enabled (bool)
function M.attach(ctx)
  ctx = ctx or {}
  local filetypes = ctx.filetypes
    or { "javascript", "javascriptreact", "typescript", "typescriptreact", "vue", "svelte" }
  local group = api.nvim_create_augroup("MasonEslintPrettier", { clear = true })

  Autocmd.create("BufWritePre", function(ev)
    if not ctx._enabled then
      return
    end
    local ft = api.nvim_get_option_value("filetype", { buf = ev.buf })
    local allowed = false
    for _, v in ipairs(filetypes) do
      if v == ft then
        allowed = true
        break
      end
    end
    if not allowed then
      return
    end

    local root = core(ev.buf)
    -- run only if either config exists
    if check.has_eslint(root) then
      eslint_fix.eslint_fix(ev.buf)
    end
    if check.has_prettier(root) then
      prettier_fmt.prettier_format(ev.buf)
    end
  end, {
    group = group,
    pattern = { "*.js", "*.cjs", "*.mjs", "*.jsx", "*.ts", "*.tsx", "*.vue", "*.svelte" },
  })
end

return M
