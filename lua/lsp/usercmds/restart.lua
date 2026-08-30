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
local lsp = vim.lsp

--- Get clients attached to buffer
---@param bufnr integer|nil
---@return vim.lsp.Client[]
local function get_buffer_clients(bufnr)
  return lsp.get_clients({ bufnr = bufnr or 0 })
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
  local clients = get_buffer_clients(bufnr)

  if #clients == 0 then
    notify.info("No LSP clients to restart")
    return
  end

  if args.args and args.args ~= "" then
    -- Restart specific server
    local found = false
    for _, c in ipairs(clients) do
      if c.name == args.args then
        found = true
        -- Before the stop: a force-stop is a SIGTERM, which the supervisor
        -- would otherwise read as a crash and race this restart.
        supervisor.expect_stop(c.id)
        lsp.stop_client(c.id, true)

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
        break
      end
    end

    if not found then
      notify.warn(string.format("LSP '%s' not running", args.args))
    end
  else
    -- Restart all servers
    local server_names = {}
    for _, c in ipairs(clients) do
      server_names[#server_names + 1] = c.name
    end

    local ids = {}
    for _, c in ipairs(clients) do
      ids[#ids + 1] = c.id
    end

    supervisor.expect_stop(ids)
    lsp.stop_client(ids, true)

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
