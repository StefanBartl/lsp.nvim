---@module 'lsp.bindings.usrcmds'
---@brief The `:Lsp <subcommand>` verb, built with lib.nvim's composer.
---@description
--- One compound command instead of a family of flat ones (NEW-23), with
--- `<Tab>` completion over subcommands and over every closed argument set
--- (NEW-26). Roadmap §8.2 designs the full route tree; the routes below are the
--- ones that need nothing from the migration -- they read Neovim's own LSP
--- state rather than the plugin's, so they work on a bare install.
---
--- Report output goes to a scratch split rather than `print()` or a
--- notification: it is multi-line, it is meant to be read and copied from, and
--- a notification would truncate it.
---
---@see lsp.bindings
---@see lsp.init

local composer = require("lib.nvim.usercmd.composer")
local scratch = require("lib.nvim.window.open_scratch_split")
local notify = require("lib.nvim.notify").create("[Lsp]")

local M = {}

--- Log levels `vim.lsp.log.set_level` accepts, in ascending severity. Used
--- both as the completion source and as the validated argument set.
---@type string[]
local LOG_LEVELS = { "trace", "debug", "info", "warn", "error", "off" }

---@internal
--- Show a report in its own scratch split.
---@param lines string[]
---@return nil
local function report(lines)
  scratch(lines, { filetype = "lspreport" })
end

---@internal
--- Human-readable lines describing the plugin's current state.
---@return string[]
local function status_lines()
  local status = require("lsp").status()
  local cfg = status.config

  local lines = {
    "lsp.nvim - status",
    "",
    ("setup() has run:   %s"):format(tostring(status.initialized)),
    ("`:Lsp` registered: %s"):format(tostring(status.usrcmd)),
    ("keymaps bound:     %d"):format(#status.keymaps),
    ("servers set up:    %d"):format(#status.servers),
    ("clients attached:  %d"):format(#status.clients),
  }

  if cfg ~= nil then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "config"
    lines[#lines + 1] = ("  keymaps.enable   = %s"):format(tostring(cfg.keymaps.enable))
    lines[#lines + 1] = ("  keymaps.preset   = %q"):format(cfg.keymaps.preset)
    lines[#lines + 1] = ("  usrcmds.enable   = %s"):format(tostring(cfg.usrcmds.enable))
    lines[#lines + 1] = ("  which_key.enable = %s"):format(tostring(cfg.which_key.enable))
    lines[#lines + 1] = ("  formatter.on_save = %s"):format(tostring(cfg.formatter.on_save))
    lines[#lines + 1] = ("  servers          = %s"):format(table.concat(cfg.servers, ", "))
  end

  if #status.warnings > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "warnings"
    for _, w in ipairs(status.warnings) do
      lines[#lines + 1] = "  " .. w
    end
  end

  if #status.servers > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "servers set up"
    for _, name in ipairs(status.servers) do
      lines[#lines + 1] = "  " .. name
    end
  end

  return lines
end

---@internal
--- Human-readable lines describing the attached LSP clients.
---@return string[]
local function server_lines()
  local status = require("lsp").status()
  local clients = vim.lsp.get_clients()

  local lines = { "lsp.nvim - servers", "" }
  lines[#lines + 1] = ("set up: %s"):format(
    #status.servers > 0 and table.concat(status.servers, ", ") or "(none)"
  )
  lines[#lines + 1] = ""

  if #clients == 0 then
    lines[#lines + 1] = "No LSP client is attached to any buffer."
    return lines
  end

  for _, client in ipairs(clients) do
    local buffers = vim.tbl_keys(client.attached_buffers or {})
    lines[#lines + 1] = ("%s (id %d)"):format(client.name, client.id)
    lines[#lines + 1] = ("  root:    %s"):format(client.root_dir or "-")
    lines[#lines + 1] = ("  buffers: %d"):format(#buffers)
  end
  return lines
end

--- Register the `:Lsp` verb.
---@return boolean registered # false when the composer refused the spec.
function M.setup()
  local ok = pcall(composer.verb, "Lsp", {
    desc = "lsp.nvim: inspect LSP state and the plugin's own",
    routes = {
      {
        path = { "status" },
        desc = "Show what lsp.nvim has set up",
        run = function()
          report(status_lines())
        end,
      },

      {
        path = { "servers" },
        desc = "List the LSP clients currently attached",
        run = function()
          report(server_lines())
        end,
      },

      {
        path = { "health" },
        desc = "Run :checkhealth lsp",
        run = function()
          vim.cmd("checkhealth lsp")
        end,
      },

      {
        path = { "log", "open" },
        desc = "Open Neovim's LSP log file in a split",
        run = function()
          local path = vim.lsp.get_log_path()
          if path == nil or vim.fn.filereadable(path) ~= 1 then
            notify.warn("No LSP log file yet: " .. tostring(path))
            return
          end
          vim.cmd("split " .. vim.fn.fnameescape(path))
        end,
      },

      {
        path = { "log", "level" },
        args = { { name = "level", type = "STRING", enum = LOG_LEVELS } },
        desc = "Set the LSP log level (trace|debug|info|warn|error|off)",
        run = function(ctx)
          vim.lsp.log.set_level(ctx.args.level)
          notify.info("LSP log level: " .. ctx.args.level)
        end,
      },
    },
  })

  return ok
end

return M
