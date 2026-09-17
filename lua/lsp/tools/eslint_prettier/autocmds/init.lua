---@module 'lsp.tools.eslint_prettier.autocmds'
--- Attach autocmds (BufWritePre) for lint+format with toggle support.
local api = vim.api
local core = require("lsp.tools.eslint_prettier.core.find_root")
local check = require("lsp.tools.eslint_prettier.core.check_config")
local eslint_fix = require("lsp.tools.eslint_prettier.eslint.fix")
local prettier_fmt = require("lsp.tools.eslint_prettier.prettier.format")
local Autocmd = require("lib.nvim.bindings.autocmd")

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
    -- run only if the respective config exists, and prettier only once eslint
    -- has exited: both rewrite the same path, so started together the slower
    -- one's write is what survives and the other's is lost. Measured on a
    -- stubbed pair -- prettier done at ~0.1 s, eslint at ~2 s -- the file held
    -- eslint's output alone.
    local function format()
      if check.has_prettier(root) then
        prettier_fmt.prettier_format(ev.buf)
      end
    end
    if check.has_eslint(root) then
      eslint_fix.eslint_fix(ev.buf, format)
    else
      format()
    end
  end, {
    group = group,
    pattern = { "*.js", "*.cjs", "*.mjs", "*.jsx", "*.ts", "*.tsx", "*.vue", "*.svelte" },
  })
end

return M
