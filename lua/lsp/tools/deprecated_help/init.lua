---@module 'lsp.tools.deprecated_help'
--- Initialization entry for the modularized deprecated-warning helper.
--- Example usage:
---   require('myplugin.init').setup({
---     keymap = "<leader>lh",
---   })
---
--- This file composes modules and installs the common wrapper.

local lsp_common = require("lsp.tools.deprecated_help.lsp_common")
local lua_ls = require("lsp.tools.deprecated_help.lsp.lua_ls.lua_ls")
local publish_diagnostics = require("lsp.tools.deprecated_help.lsp.lua_ls.publish_diagnostics")
local defaults = require("lsp.tools.deprecated_help.defaults")

local M = {}

--- Setup the plugin.
--- opts can contain per-server sub-tables, e.g. opts.lua_ls = { keymap = "<leader>lh" }
---@param opts table|nil
function M.setup(opts)
  opts = opts or {}

  -- setup lua_ls module first (registers server callback)
  if opts.lua_ls then
    lua_ls.setup(opts.lua_ls)
  else
    lua_ls.setup() -- default
  end

  -- install the common publishDiagnostics wrapper
  lsp_common.setup()

  -- set dynamic hint message for wrap.publish_diagnostics
  opts.diagnostic_hint = " — press " .. defaults.keymap .. " to open :help for this symbol"
  publish_diagnostics.wrap(opts)
end

return M
