---@module 'lsp.usercmds'
--- LSP UserCommands - Main Registry
--- Delegates to specialized submodules for each command

local notify = require("lib.nvim.notify").create("[lsp.usrcmds] ")
local composer = require("lib.nvim.bindings.usercmd.composer")
local usercmd = require("lib.nvim.bindings.usercmd")

local M = {}

local desc_tag = "[lsp.usercmds] "

-- Lazy-loaded submodules
local commands = {
  start = function()
    return require("lsp.usercmds.start")
  end,
  stop = function()
    return require("lsp.usercmds.stop")
  end,
  restart = function()
    return require("lsp.usercmds.restart")
  end,
  info = function()
    return require("lsp.usercmds.info")
  end,
}

local completion = function()
  return require("lsp.usercmds.completion")
end

--- Register the flat command family.
---
--- Everything up to `:LspMdHints` is an alias onto a `:Lsp` route and is
--- skipped when `usrcmds.legacy_aliases` is off. `:LspMdHints` is not: it is
--- marksman-specific, and a server command does not belong in the global verb
--- (roadmap section 8.2), so it is registered either way.
---@param legacy boolean|nil # false skips the aliases.
---@return nil
function M.attach(legacy)
  if legacy == false then
    M.attach_md_hints()
    return
  end

  usercmd.create("LspLog", function()
    local logfile = vim.lsp.log.get_filename()
    vim.cmd("split " .. vim.fn.fnameescape(logfile))
  end, { desc = desc_tag .. "Open LSP log file" })

  usercmd.create("LspStatus", function()
    local bufnr = 0
    local clients = vim.lsp.get_clients({ bufnr = bufnr })

    if #clients == 0 then
      notify.info("No LSP clients attached to current buffer")
      return
    end

    local lines = { "LSP Status for buffer " .. bufnr }
    for _, c in ipairs(clients) do
      table.insert(lines, string.format("\n[%s]", c.name))
      table.insert(lines, "  ID: " .. tostring(c.id))
      table.insert(lines, "  Root: " .. tostring(c.config and c.config.root_dir or "unknown"))
      table.insert(lines, "  Status: " .. (c:is_stopped() and "stopped" or "running"))
    end

    notify.info(table.concat(lines, "\n"))
  end, { desc = desc_tag .. "Show LSP status for current buffer" })

  -- LspRecover: Auto-recover missing servers
  usercmd.create("LspRecover", function()
    local recovery = require("lsp.usercmds.recovery")
    recovery.auto_recover(vim.api.nvim_get_current_buf())
  end, { desc = desc_tag .. "Auto-recover missing LSP servers" })

  -- LspForceRestart: Force-restart with cleanup
  usercmd.create("LspForceRestart", function(args)
    local recovery = require("lsp.usercmds.recovery")
    if args.args and args.args ~= "" then
      recovery.force_restart(args.args, vim.api.nvim_get_current_buf())
    else
      notify.warn("Usage: :LspForceRestart <server_name>")
    end
  end, {
    nargs = 1,
    complete = function(arglead, cmdline, cursorpos)
      return completion().complete_restart(arglead, cmdline, cursorpos)
    end,
    desc = desc_tag .. "Force-restart LSP with full cleanup",
  })

  -- LspStartHere: Start servers (auto-detect or specify)
  usercmd.create("LspStartHere", function(args)
    commands.start().execute(args)
  end, {
    nargs = "?",
    complete = function(arglead, cmdline, cursorpos)
      return completion().complete_start(arglead, cmdline, cursorpos)
    end,
    desc = desc_tag .. "Start LSP servers (auto-detect or specify name)",
  })

  -- LspStopHere: Stop servers
  usercmd.create("LspStopHere", function(args)
    commands.stop().execute(args)
  end, {
    nargs = "?",
    complete = function(arglead, cmdline, cursorpos)
      return completion().complete_stop(arglead, cmdline, cursorpos)
    end,
    desc = desc_tag .. "Stop LSP clients (all or specify name)",
  })

  -- LspRestartHere: Restart servers
  usercmd.create("LspRestartHere", function(args)
    commands.restart().execute(args)
  end, {
    nargs = "?",
    complete = function(arglead, cmdline, cursorpos)
      return completion().complete_restart(arglead, cmdline, cursorpos)
    end,
    desc = desc_tag .. "Restart LSP clients (all or specify name)",
  })

  -- LspInfo: Show detailed info
  usercmd.create("LspInfo", function()
    commands.info().execute()
  end, {
    desc = desc_tag .. "Show LSP information for current buffer",
  })

  M.attach_md_hints()
end

--- Register `:LspMdHints`. Kept out of `:Lsp` on purpose: it is a marksman
--- command, and server commands do not belong in a global verb.
---@return nil
function M.attach_md_hints()
  -- LspMdHints: toggle marksman's Hint-severity diagnostics ("lightbulb").
  -- `path = {}` is the verb's root route (no literal subcommand word,
  -- matching the flat `:LspMdHints [on|off|toggle|status]` grammar) — the
  -- composer's own enum validation replaces the hand-written usage warning.
  composer.verb("LspMdHints", {
    desc = desc_tag .. "Toggle marksman Hint-severity diagnostics (markdown 'lightbulb')",
    routes = {
      {
        path = {},
        args = {
          {
            name = "mode",
            type = "STRING",
            enum = { "on", "off", "toggle", "status" },
            optional = true,
          },
        },
        run = function(ctx)
          local hints = require("lsp.servers.marksman.hints")
          local mode = ctx.args.mode or "toggle"
          if mode == "toggle" then
            hints.toggle()
          elseif mode == "on" then
            hints.set(true)
          elseif mode == "off" then
            hints.set(false)
          elseif mode == "status" then
            notify.info("Markdown hints: " .. (hints.enabled() and "on" or "off"))
          end
        end,
      },
    },
  })
end

return M
