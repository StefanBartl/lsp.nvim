---@module 'lsp.diagnostics.commands'
--- User command definitions for diagnostics navigation.

local util = require("lsp.diagnostics.util")
local loclist = require("lsp.diagnostics.loclist")
local quickfix = require("lsp.diagnostics.quickfix")
local usercmd = require("lib.nvim.usercmd")

local M = {}

--- Register all diagnostics-related user commands.
---@return nil
function M.enable()
  if vim.g._diagnostics_cmds_enabled == 1 then
    return
  end
  vim.g._diagnostics_cmds_enabled = 1

  -- Location list (buffer)
  usercmd.create("DiagLoc", function(ctx)
    loclist.to_loc({ open = true, severity = ctx.args })
  end, { nargs = "?" })

  usercmd.create("DiagNextLoc", function(ctx)
    local sev = util.to_severity(ctx.args)
    loclist.next_loc(sev)
  end, { nargs = "?" })

  usercmd.create("DiagPrevLoc", function(ctx)
    local sev = util.to_severity(ctx.args)
    loclist.prev_loc(sev)
  end, { nargs = "?" })

  -- Quickfix (workspace)
  usercmd.create("DiagQF", function(ctx)
    quickfix.to_qf({ open = true, severity = ctx.args })
  end, { nargs = "?" })

  usercmd.create("DiagNextQF", function()
    quickfix.next_qf()
  end, { bang = true })

  usercmd.create("DiagPrevQF", function()
    quickfix.prev_qf()
  end, { bang = true })
end

return M
