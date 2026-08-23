---@module 'lsp.tools.eslint_prettier'
--- Main entry for eslint_prettier tooling.
--- Exposes `setup()` and `attach()`; attach registers autocmds/usercommands.
--- Works cross-platform and resolves mason-installed binaries automatically.
local M = {}

local find_root = require("lsp.tools.eslint_prettier.core.find_root")
local check_config = require("lsp.tools.eslint_prettier.core.check_config")
local eslint_fix = require("lsp.tools.eslint_prettier.eslint.fix")
local prettier_format = require("lsp.tools.eslint_prettier.prettier.format")
local autocmds = require("lsp.tools.eslint_prettier.autocmds")
local usercmds = require("lsp.tools.eslint_prettier.usercmds")

--- Default filetypes to operate on.
M.filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "vue", "svelte" }

--- toggle for autorun
M._enabled = true

--- Setup optional user overrides
---@param opts table|nil
function M.setup(opts)
  opts = opts or {}
  M.filetypes = opts.filetypes or M.filetypes
  if type(opts.enable_on_setup) == "boolean" then
    M._enabled = opts.enable_on_setup
  end
  -- optional: provide custom binary paths
  if opts.binaries then
    eslint_fix.set_bins(opts.binaries.eslint or nil)
    prettier_format.set_bins(opts.binaries.prettier or nil)
  end
  -- create usercommands and attach autocmds immediately
  usercmds.attach(M)
  autocmds.attach(M)
end

--- Attach only (for cases where plugin loader calls attach separately)
---@param ctx table|nil
function M.attach(ctx)
  ctx = ctx or {}
  usercmds.attach(M)
  autocmds.attach(M)
end

-- expose core helpers for tests/extensions
M._find_root = find_root
M._check_config = check_config
M._eslint_fix = eslint_fix
M._prettier_format = prettier_format

return M
