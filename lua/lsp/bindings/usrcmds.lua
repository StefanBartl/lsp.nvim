---@module 'lsp.bindings.usrcmds'
---@brief The `:Lsp <subcommand>` verb, built with lib.nvim's composer.
---@description
--- One compound command instead of a family of flat ones (NEW-23), with
--- `<Tab>` completion over subcommands and over every closed argument set
--- (NEW-26). This is roadmap section 8.2's route tree.
---
--- The ~25 flat `:Lsp*` and `:Diag*` commands the migration brought along stay
--- as thin aliases, switchable off with `usrcmds.legacy_aliases = false`.
--- Muscle memory beats tidiness, and an alias costs a line -- but they are
--- aliases now, not the primary form: both reach the same functions in
--- `lsp.bindings.actions` and the `lsp.usercmds.*` modules, so the two can no
--- longer drift apart.
---
--- Two commands are deliberately *not* folded in. `:LspDoctor` keeps its own
--- verb -- it is a diagnostic tool with its own renderer and five modes, not
--- an LSP control command (the same exception `replacer.nvim` makes for
--- `:Surround`) -- and it is reachable as `:Lsp doctor` anyway.
--- `:LspMdHints` is marksman-specific, and server commands do not belong in a
--- global verb.
---
--- Report output goes to a scratch split rather than `print()` or a
--- notification: it is multi-line, meant to be read and copied from, and a
--- notification would truncate it.
---
---@see lsp.bindings
---@see lsp.bindings.actions
---@see lsp.init

local composer = require("lib.nvim.bindings.usercmd.composer")
local argtypes = require("lib.nvim.bindings.usercmd.composer.argtypes")
local scratch = require("lib.nvim.window.open_scratch_split")
local notify = require("lib.nvim.notify").create("[Lsp]")
local actions = require("lsp.bindings.actions")

local M = {}

--- Log levels `vim.lsp.log.set_level` accepts, in ascending severity.
---@type string[]
local LOG_LEVELS = { "trace", "debug", "info", "warn", "error", "off" }

--- Argument type for a server name, completing from the *live* set rather than
--- a list frozen at setup time (NEW-26 asks for exactly that: a value set that
--- changes at runtime must be computed at completion time).
---
--- Registered once, under a name only this plugin uses -- `argtypes.register`
--- is a shared registry, so a generic name like "SERVER" would be a collision
--- waiting to happen.
---@return nil
local function register_server_argtype()
  argtypes.register("LSP_SERVER", {
    validate = function(raw)
      return true, raw, nil
    end,
    complete = function(arg_lead)
      ---@type table<string, true>
      local seen = {}
      ---@type string[]
      local names = {}

      -- Attached clients first: they are what "restart this one" usually
      -- means, and they are certainly real.
      for _, client in ipairs(vim.lsp.get_clients()) do
        if not seen[client.name] then
          seen[client.name] = true
          names[#names + 1] = client.name
        end
      end

      -- Then everything configured, attached or not.
      local cfg = require("lsp.config").get()
      for _, name in ipairs(cfg.servers or {}) do
        if not seen[name] then
          seen[name] = true
          names[#names + 1] = name
        end
      end

      return argtypes.prefix(names, arg_lead)
    end,
  })
end

--- Argument type for a filetype, completed from what is actually open plus
--- whatever already carries an inlay-hint override. Neovim's own
--- `getcompletion(_, "filetype")` would list every filetype it knows, which is
--- several hundred entries and almost none of them relevant to a buffer that
--- is open right now.
---@return nil
local function register_filetype_argtype()
  argtypes.register("LSP_FILETYPE", {
    validate = function(raw)
      return true, raw, nil
    end,
    complete = function(arg_lead)
      ---@type table<string, true>
      local seen = {}
      ---@type string[]
      local names = {}

      local ok, hints = pcall(require, "lsp.core.inlay_hints")
      if ok then
        for _, ft in ipairs(hints.overridden()) do
          if not seen[ft] then
            seen[ft] = true
            names[#names + 1] = ft
          end
        end
      end

      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
          local ft = vim.bo[bufnr].filetype
          if ft ~= "" and not seen[ft] then
            seen[ft] = true
            names[#names + 1] = ft
          end
        end
      end

      table.sort(names)
      return argtypes.prefix(names, arg_lead)
    end,
  })
end

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
    lines[#lines + 1] = ("  keymaps.enable      = %s"):format(tostring(cfg.keymaps.enable))
    lines[#lines + 1] = ("  keymaps.preset      = %q"):format(cfg.keymaps.preset)
    lines[#lines + 1] = ("  usrcmds.enable      = %s"):format(tostring(cfg.usrcmds.enable))
    lines[#lines + 1] = ("  usrcmds.legacy_aliases = %s"):format(
      tostring(cfg.usrcmds.legacy_aliases)
    )
    lines[#lines + 1] = ("  which_key.enable    = %s"):format(tostring(cfg.which_key.enable))
    lines[#lines + 1] = ("  formatter.on_save   = %s"):format(tostring(cfg.formatter.on_save))
    lines[#lines + 1] = ("  rename.provider     = %q"):format(cfg.rename.provider)
    lines[#lines + 1] = ("  servers             = %s"):format(table.concat(cfg.servers, ", "))
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

---@internal
--- Hand a server name to one of the `lsp.usercmds.*` command modules, in the
--- argument shape they expect -- the same table nvim passes a flat command,
--- since that is what they were written against.
---@param module string
---@param server string|nil
---@return nil
local function run_command_module(module, server)
  local ok, mod = pcall(require, "lsp.usercmds." .. module)
  if not (ok and type(mod.execute) == "function") then
    notify.warn(("command module %q unavailable"):format(module))
    return
  end
  mod.execute({ args = server or "" })
end

---@internal
--- Dispatch a table of named actions from an optional enum argument.
---@param map table<string, fun(): nil>
---@param choice string|nil
---@param fallback string
---@return nil
local function dispatch(map, choice, fallback)
  local fn = map[choice or fallback]
  if fn == nil then
    notify.warn(("unknown action %q"):format(tostring(choice)))
    return
  end
  fn()
end

--- Register the `:Lsp` verb.
---@return boolean registered # false when the composer refused the spec.
function M.setup()
  register_server_argtype()
  register_filetype_argtype()
  -- `LSP_DOCTOR_MODE` is owned by `lsp.lspdoctor` -- the module that owns the
  -- reports owns their names. It has to exist before the verb below is
  -- composed, and the bootstrap does not reach lspdoctor until after the
  -- bindings layer, so it is registered from here as well.
  pcall(function()
    require("lsp.lspdoctor").register_mode_argtype()
  end)

  local ok = pcall(composer.verb, "Lsp", {
    desc = "lsp.nvim: control and inspect the LSP setup",
    routes = {
      -- ---------------------------------------------------------- inspect
      {
        path = { "status" },
        desc = "Show what lsp.nvim has set up",
        run = function()
          report(status_lines())
        end,
      },
      {
        path = { "servers" },
        desc = "Servers set up, and the clients currently attached",
        run = function()
          report(server_lines())
        end,
      },
      {
        path = { "info" },
        desc = "Detailed LSP information for the current buffer",
        run = function()
          run_command_module("info", nil)
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
        path = { "doctor" },
        args = {
          -- Shares `:LspDoctor`'s argument type rather than repeating an enum,
          -- so the two cannot offer different report names. The type also
          -- accepts the legacy spellings without offering them.
          { name = "mode", type = "LSP_DOCTOR_MODE", optional = true },
        },
        desc = "Per-buffer diagnosis (same as :LspDoctor)",
        run = function(ctx)
          local doctor = require("lsp.lspdoctor")
          -- `startup`, not `all`: this route opens a scratch split, and the
          -- combined report is long. The question one arrives with is almost
          -- always "why is my server not running".
          local mode = doctor.LEGACY_MODES[ctx.args.mode] or ctx.args.mode or "startup"
          local fn = doctor[mode]
          if type(fn) ~= "function" then
            notify.warn(("unknown doctor report %q"):format(tostring(mode)))
            return
          end
          fn(0, true)
        end,
      },

      -- ---------------------------------------------------------- lifecycle
      {
        path = { "start" },
        args = { { name = "server", type = "LSP_SERVER", optional = true } },
        desc = "Start servers for this buffer (auto-detect, or one by name)",
        run = function(ctx)
          run_command_module("start", ctx.args.server)
        end,
      },
      {
        path = { "stop" },
        args = { { name = "server", type = "LSP_SERVER", optional = true } },
        desc = "Stop clients on this buffer (all, or one by name)",
        run = function(ctx)
          run_command_module("stop", ctx.args.server)
        end,
      },
      {
        path = { "restart" },
        args = { { name = "server", type = "LSP_SERVER", optional = true } },
        desc = "Restart clients on this buffer (all, or one by name)",
        run = function(ctx)
          run_command_module("restart", ctx.args.server)
        end,
      },
      {
        -- Its own subcommand rather than a flag on `restart`: a literal word
        -- after `restart` would be ambiguous with a server called "force",
        -- and the two really are different operations -- this one tears the
        -- client down first.
        path = { "force-restart" },
        args = { { name = "server", type = "LSP_SERVER" } },
        desc = "Restart one server with a full cleanup first",
        run = function(ctx)
          require("lsp.usercmds.recovery").force_restart(
            ctx.args.server,
            vim.api.nvim_get_current_buf()
          )
        end,
      },
      {
        path = { "recover" },
        desc = "Auto-recover servers that should be running here and are not",
        run = function()
          require("lsp.usercmds.recovery").auto_recover(vim.api.nvim_get_current_buf())
        end,
      },

      -- ---------------------------------------------------------- formatter
      {
        path = { "format" },
        args = {
          {
            name = "action",
            type = "STRING",
            enum = { "once", "on", "off", "toggle", "status", "which" },
            optional = true,
          },
        },
        desc = "Format once, or control format-on-save",
        run = function(ctx)
          dispatch({
            once = actions.format_buffer,
            on = actions.format_on,
            off = actions.format_off,
            toggle = actions.format_toggle,
            status = actions.format_status,
            which = actions.format_which,
          }, ctx.args.action, "once")
        end,
      },

      -- ---------------------------------------------------------- inlay hints
      {
        path = { "hints" },
        args = {
          {
            name = "action",
            type = "STRING",
            enum = { "toggle", "on", "off", "status", "clear" },
            optional = true,
          },
          { name = "filetype", type = "LSP_FILETYPE", optional = true },
        },
        desc = "Inlay hints: control globally, or for one filetype",
        run = function(ctx)
          local hints = require("lsp.core.inlay_hints")
          local action = ctx.args.action or "toggle"
          local ft = ctx.args.filetype

          if action == "status" then
            report(hints.status())
            return
          end
          if action == "clear" then
            -- The one action that has no global meaning: dropping "the global
            -- override" would be dropping the setting itself.
            if ft == nil then
              notify.warn("`:Lsp hints clear` needs a filetype")
              return
            end
            hints.clear(ft)
            return
          end

          if action == "toggle" then
            hints.toggle(ft)
          else
            hints.set(action == "on", ft)
          end
        end,
      },

      -- ---------------------------------------------------------- diagnostics
      {
        path = { "diag" },
        args = {
          { name = "action", type = "STRING", enum = { "qf", "loc", "next", "prev" } },
          { name = "list", type = "STRING", enum = { "qf", "loc" }, optional = true },
        },
        desc = "Diagnostics into a list, or move within one",
        run = function(ctx)
          local list = ctx.args.list or "loc"
          -- `1`, not the action's default: the navigation actions fall back to
          -- `v:count1` when called with no argument, which is right for a
          -- keypress and wrong here -- `v:count` holds whatever the last
          -- keypress left behind, not something the user typed into this
          -- command.
          local once = function(fn)
            return function()
              fn(1)
            end
          end
          dispatch({
            qf = actions.diag_to_qflist,
            loc = actions.diag_to_loclist,
            next = once((list == "qf") and actions.qf_next or actions.diag_next),
            prev = once((list == "qf") and actions.qf_prev or actions.diag_prev),
          }, ctx.args.action, "loc")
        end,
      },

      -- ---------------------------------------------------------- workspace
      {
        path = { "workspace" },
        args = {
          {
            name = "action",
            type = "STRING",
            enum = { "on", "off", "toggle", "status", "now" },
            optional = true,
          },
        },
        desc = "Workspace-wide diagnostics on attach: control or force now",
        run = function(ctx)
          dispatch({
            on = actions.workspace_on,
            off = actions.workspace_off,
            toggle = actions.workspace_toggle,
            status = actions.workspace_status,
            now = actions.workspace_now,
          }, ctx.args.action, "status")
        end,
      },

      -- ------------------------------------------- root scope and workspace
      {
        -- `pick` still picks the resolution *strategy*; `add`/`remove` move
        -- the actual workspace folders of the running clients. Two different
        -- mechanisms, deliberately under one word: from where one sits, both
        -- answers to "what does this server consider my project".
        path = { "root" },
        args = {
          {
            name = "action",
            type = "STRING",
            enum = { "pick", "show", "add", "remove", "list" },
            optional = true,
          },
        },
        desc = "Root scope and workspace folders: pick, show, add, remove, list",
        run = function(ctx)
          dispatch({
            pick = actions.root_scope_pick,
            show = actions.root_show,
            add = actions.root_workspace_add,
            remove = actions.root_workspace_remove,
            list = actions.root_workspace_list,
          }, ctx.args.action, "show")
        end,
      },

      -- ---------------------------------------------------------- log
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
