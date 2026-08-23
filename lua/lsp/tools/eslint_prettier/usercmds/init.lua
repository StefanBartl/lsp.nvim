---@module 'lsp.tools.eslint_prettier.usercmds'
--- Create user commands like :EslintFix, :PrettierFormat, :LintAndFormat, :ToggleLintFormatOnSave
local notify = require("lib.nvim.notify").create("[lsp.tools.eslint_prettier.usercmds]")
local usercmd = require("lib.nvim.usercmd")

local api = vim.api
local core = require("lsp.tools.eslint_prettier.core.find_root")
local check = require("lsp.tools.eslint_prettier.core.check_config")
local eslint_fix = require("lsp.tools.eslint_prettier.eslint.fix")
local prettier_fmt = require("lsp.tools.eslint_prettier.prettier.format")

local M = {}

---@param ctx table|nil
function M.attach(ctx)
  ctx = ctx or {}
  usercmd.create("EslintFix", function()
    local bufnr = api.nvim_get_current_buf()
    local root = core(bufnr)
    if not check.has_eslint(root) then
      notify.info("No eslint config found in project root; skipping")
      return
    end
    eslint_fix.eslint_fix(bufnr)
  end, { desc = "Run eslint_d --fix on current file (requires eslint config in project root)" })

  usercmd.create("PrettierFormat", function()
    local bufnr = api.nvim_get_current_buf()
    local root = core(bufnr)
    if not check.has_prettier(root) then
      notify.info("No prettier config found in project root; skipping")
      return
    end
    prettier_fmt.prettier_format(bufnr)
  end, { desc = "Run prettier --write on current file (requires prettier config in project root)" })

  usercmd.create("LintAndFormat", function()
    local bufnr = api.nvim_get_current_buf()
    local root = core(bufnr)
    if check.has_eslint(root) then
      eslint_fix.eslint_fix(bufnr)
    end
    if check.has_prettier(root) then
      prettier_fmt.prettier_format(bufnr)
    end
  end, { desc = "Run eslint_d --fix then prettier --write on current file" })

  usercmd.create("ToggleLintFormatOnSave", function()
    ctx._enabled = not not not not ctx._enabled -- placeholder if ctx is external
    -- better: toggle global in main module; user can call require('lsp.tools.eslint_prettier')._enabled = false
    notify.info("Toggle autorun: use plugin.setup to change default programmatically")
  end, { desc = "Toggle automatic lint+format on save (toggle via API)" })
end

return M
