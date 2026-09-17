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
  --
  -- These used to go to `eslint_fix.set_bins` / `prettier_format.set_bins`,
  -- neither of which exists: `setup({ binaries = { eslint = "..." } })` raised
  -- "attempt to call field 'set_bins' (a nil value)" on line 30 and took the
  -- whole `setup` with it. The setters live on the two bin-resolver modules,
  -- next to the cache they write.
  if opts.binaries then
    if opts.binaries.eslint then
      require("lsp.tools.eslint_prettier.eslint").set_eslint_bin(opts.binaries.eslint)
    end
    if opts.binaries.prettier then
      require("lsp.tools.eslint_prettier.prettier").set_prettier_bin(opts.binaries.prettier)
    end
  end
  -- create usercommands and attach autocmds immediately
  usercmds.attach(M)
  autocmds.attach(M)
end

--- Attach only (for cases where plugin loader calls attach separately)
--- `_ctx` is accepted for call-site symmetry with the other attach functions
--- and deliberately ignored.
---@param _ctx table|nil
function M.attach(_ctx)
  usercmds.attach(M)
  autocmds.attach(M)
end

-- expose core helpers for TESTS/extensions
M._find_root = find_root
M._check_config = check_config
M._eslint_fix = eslint_fix
M._prettier_format = prettier_format

return M
