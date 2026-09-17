---@module 'lsp.tools.eslint_prettier.usercmds'
--- Create user commands like :EslintFix, :PrettierFormat, :LintAndFormat, :ToggleLintFormatOnSave
local notify = require("lib.nvim.notify").create("[lsp.tools.eslint_prettier.usercmds]")
local usercmd = require("lib.nvim.bindings.usercmd")

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

  -- "then", not "and both at once". Both tools rewrite the same path on disk,
  -- so firing them in one tick is a race whose loser is silently discarded.
  -- Measured with a slow eslint stub and a fast prettier one: prettier's write
  -- landed at ~0.1 s, eslint's at ~2 s, and the file ended up holding only
  -- eslint's output -- the formatting the command was asked for was gone.
  usercmd.create("LintAndFormat", function()
    local bufnr = api.nvim_get_current_buf()
    local root = core(bufnr)
    local function format()
      if check.has_prettier(root) then
        prettier_fmt.prettier_format(bufnr)
      end
    end
    if check.has_eslint(root) then
      eslint_fix.eslint_fix(bufnr, format)
    else
      format()
    end
  end, { desc = "Run eslint_d --fix then prettier --write on current file" })

  -- `not not not not x` is `x`, so this command used to report a toggle and
  -- change nothing: `_enabled` measured `true` before the call and `true`
  -- after two of them. The doc promises it flips
  -- `require('lsp.tools.eslint_prettier')._enabled` and then says which way it
  -- went, which is what it does now.
  usercmd.create("ToggleLintFormatOnSave", function()
    ctx._enabled = not ctx._enabled
    notify.info("Lint+format on save: " .. (ctx._enabled and "on" or "off"))
  end, { desc = "Toggle automatic lint+format on save" })
end

return M
