---@module 'lsp.usercmds.restart'
--- LspRestartHere command implementation

local M = {}

local notify = require("lib.nvim.notify").create("[LSP.Restart] ")
local lsp = vim.lsp

--- Get clients attached to buffer
---@param bufnr integer|nil
---@return vim.lsp.Client[]
local function get_buffer_clients(bufnr)
  return lsp.get_clients({ bufnr = bufnr or 0 })
end

--- Start LSP server by name (with retry logic) and ATTACH to buffer
---@param name string
---@param bufnr integer
---@return boolean success
local function start_lsp(name, bufnr)
  if not name or name == "" then
    return false
  end

  -- Get LSP config from vim.lsp.config
  if type(lsp.config) ~= "table" then
    return false
  end

  local config_list = lsp.config.get and lsp.config.get() or {}
  local server_config = nil

  for _, cfg in pairs(config_list) do
    if cfg.name == name then
      server_config = cfg
      break
    end
  end

  if not server_config then
    return false
  end

  -- Start AND attach to buffer
  local ok, client_id = pcall(lsp.start, server_config, { bufnr = bufnr })
  return ok and client_id ~= nil
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
