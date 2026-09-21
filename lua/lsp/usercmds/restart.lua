---@module 'lsp.usercmds.restart'
--- LspRestartHere command implementation.
---
--- The start half lives in `lsp.core.supervisor`, which needs the same
--- primitive for a crashed server and is where the bug in this one was found:
--- the config lookup here went through `vim.lsp.config.get()`, which does not
--- exist on Neovim 0.12 (checked against 0.12.2). It resolved to nil, the
--- lookup fell through to an empty table, and the command stopped its client
--- and then reported a failure it could not distinguish from a real one.

local M = {}

local notify = require("lib.nvim.notify").create("[LSP.Restart] ")
local supervisor = require("lsp.core.supervisor")
local util = require("lsp.core.util")

--- Language servers attached to buffer. lsp.nvim's own in-process clients are
--- not among them: they have no process to restart and no registered
--- configuration to start again from, so "restart everything" stopped them,
--- failed to bring them back, and counted the failure.
---@param bufnr integer|nil
---@return vim.lsp.Client[]
local function get_buffer_clients(bufnr)
  return util.server_clients(bufnr or 0)
end

--- Start LSP server by name and ATTACH to buffer.
---@param name string
---@param bufnr integer
---@return boolean success
local function start_lsp(name, bufnr)
  return supervisor.start(name, bufnr)
end

--- Execute LspRestartHere command
---@param args table vim.api.nvim_create_user_command args
---@return nil
function M.execute(args)
  local bufnr = vim.api.nvim_get_current_buf()

  -- Asked for by name, before "nothing to restart" is decided: the answer to
  -- this name is not "no clients", it is "not one of those".
  if util.is_internal_name(args.args) then
    notify.info(
      string.format(
        "'%s' is lsp.nvim's own in-process client, not a language server; it re-attaches by itself on the next gitsigns update",
        args.args
      )
    )
    return
  end

  local clients = get_buffer_clients(bufnr)

  if #clients == 0 then
    notify.info("No LSP clients to restart")
    return
  end

  if args.args and args.args ~= "" then
    -- Restart specific server: every client carrying that name goes down, not
    -- just the first one found. The loop used to `break`, and a name is not
    -- unique -- with two `dup` clients on one buffer the command stopped one,
    -- started a replacement, and left the other running (measured: `dup#1
    -- dup#2` before, `dup#2` plus the new client after). One restart has to
    -- leave one client behind, not two.
    local stopped = 0
    for _, c in ipairs(clients) do
      if c.name == args.args then
        stopped = stopped + 1
        -- Before the stop: a force-stop is a SIGTERM, which the supervisor
        -- would otherwise read as a crash and race this restart.
        supervisor.expect_stop(c.id)
        c:stop(true)
      end
    end

    if stopped == 0 then
      notify.warn(string.format("LSP '%s' not running", args.args))
      return
    end

    -- Delayed restart to allow cleanup
    vim.defer_fn(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      if start_lsp(args.args, bufnr) then
        notify.info(string.format("Restarted LSP: %s", args.args))
      else
        notify.error(string.format("Failed to restart LSP: %s", args.args))
      end
    end, 100)
  else
    -- Restart all servers. The names are deduplicated: `supervisor.start`
    -- reuses a client for a name it has already started, so two clients called
    -- `spec_dup` come back as one and starting the name twice is one start
    -- plus one no-op. Counting clients instead of names made the command
    -- report "Restarted 3/3 LSP server(s)" for three clients that became one
    -- (measured), which is a count of what went down, not of what came back.
    local server_names = {}
    local seen = {}
    for _, c in ipairs(clients) do
      if not seen[c.name] then
        server_names[#server_names + 1] = c.name
        seen[c.name] = true
      end
    end

    local ids = {}
    for _, c in ipairs(clients) do
      ids[#ids + 1] = c.id
    end

    supervisor.expect_stop(ids)
    -- One at a time: the list form belonged to `vim.lsp.stop_client`, which is
    -- deprecated on 0.12, and `Client:stop()` has no equivalent. The ids are
    -- still collected as a list because `expect_stop` takes one, and every
    -- mark has to be in place before the first client goes down.
    for _, c in ipairs(clients) do
      c:stop(true)
    end

    -- Delayed restart for all servers
    vim.defer_fn(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      local started = 0
      for _, name in ipairs(server_names) do
        if start_lsp(name, bufnr) then
          started = started + 1
        end
      end
      notify.info(string.format("Restarted %d/%d LSP server(s)", started, #server_names))
    end, 100)
  end
end

return M
