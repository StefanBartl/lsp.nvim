---@module 'lsp.tools.ts_type_lookup'
--- Entry point: attaches ts_type_lookup's usercmds and telescope picker, and
--- loads its noice.nvim integration.

local M = {}

function M.setup()
  require("lsp.tools.ts_type_lookup.cmds").attach()
  require("lsp.tools.ts_type_lookup.ts_telescope_picker").attach()
  require("lsp.tools.ts_type_lookup.noice_integration")
end

return M
