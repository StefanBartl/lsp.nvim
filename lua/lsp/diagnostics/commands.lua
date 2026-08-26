---@module 'lsp.diagnostics.commands'
--- User command definitions for diagnostics navigation.

local util = require("lsp.diagnostics.util")
local loclist = require("lsp.diagnostics.loclist")
local quickfix = require("lsp.diagnostics.quickfix")
local usercmd = require("lib.nvim.bindings.usercmd")
local notify = require("lib.nvim.notify").create("[lsp.nvim]")

local M = {}

--- Register all diagnostics-related user commands.
---@return nil
function M.enable()
  if vim.g._diagnostics_cmds_enabled == 1 then
    return
  end
  vim.g._diagnostics_cmds_enabled = 1

  -- Every `[severity]` argument below shares one shape: completion from the
  -- canonical word list, and a rejected typo rather than a silent widening to
  -- all severities.
  local severity_arg = {
    nargs = "?",
    complete = util.complete_severity,
  }

  ---@param args string
  ---@param run fun(severity: integer|nil)
  ---@return nil
  local function with_severity(args, run)
    local sev, err = util.parse_severity(args)
    if err then
      notify.warn(err)
      return
    end
    run(sev)
  end

  -- Location list (buffer)
  usercmd.create(
    "DiagLoc",
    function(ctx)
      with_severity(ctx.args, function(sev)
        loclist.to_loc({ open = true, severity = sev })
      end)
    end,
    vim.tbl_extend("force", severity_arg, {
      desc = "Diagnostics of the current buffer into the location list [severity]",
    })
  )

  usercmd.create(
    "DiagNextLoc",
    function(ctx)
      with_severity(ctx.args, loclist.next_loc)
    end,
    vim.tbl_extend("force", severity_arg, {
      desc = "Jump to the next diagnostic in the current buffer [severity]",
    })
  )

  usercmd.create(
    "DiagPrevLoc",
    function(ctx)
      with_severity(ctx.args, loclist.prev_loc)
    end,
    vim.tbl_extend("force", severity_arg, {
      desc = "Jump to the previous diagnostic in the current buffer [severity]",
    })
  )

  -- Quickfix (workspace)
  usercmd.create(
    "DiagQF",
    function(ctx)
      with_severity(ctx.args, function(sev)
        quickfix.to_qf({ open = true, severity = sev })
      end)
    end,
    vim.tbl_extend("force", severity_arg, {
      desc = "Workspace diagnostics into the quickfix list [severity]",
    })
  )

  -- No `[severity]` here: these two step through the quickfix list itself
  -- (`:cnext`/`:cprevious`), not through diagnostics, and the list has already
  -- been filtered by whatever `:DiagQF` put in it.
  usercmd.create("DiagNextQF", function()
    quickfix.next_qf()
  end, { bang = true, desc = "Jump to the next quickfix entry" })

  usercmd.create("DiagPrevQF", function()
    quickfix.prev_qf()
  end, { bang = true, desc = "Jump to the previous quickfix entry" })
end

return M
