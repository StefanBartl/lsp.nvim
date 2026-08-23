---@module 'lsp.tools.deprecated_help.lsp_common'
--- Common LSP wiring utilities.
--- - Wraps the original publishDiagnostics handler without breaking it.
--- - Provides a hook system so per-server modules can register callbacks.
---
--- Design goals:
--- - Do not break current functionality: always call original handler.
--- - Be minimal: only intercept diagnostics, then call registered callbacks.
--- - Allow multiple server-specific modules to register handlers.

local notify = require("lib.nvim.notify").create("[lsp.tools.deprecated_help.lsp_common]")

local M = {}

-- keep original handler reference to preserve behavior
M._orig_publish = vim.lsp.handlers["textDocument/publishDiagnostics"]

-- registry for callbacks keyed by client name. Each callback: function(err, result, ctx, config)
---@type table<string, fun(err: any, result: table, ctx: table, config: table)>
M.server_callbacks = {}

-- Register a server-specific diagnostic callback. Overwrites existing for same server name.
---@param server_name string
---@param cb function
function M.register_server_callback(server_name, cb)
  M.server_callbacks[server_name] = cb
end

-- Internal wrapper that calls original handler first, then server-specific callback (if any).
-- Signature matches vim.lsp.handlers["textDocument/publishDiagnostics"]
---@param err lsp.ResponseError|nil
---@param result table|nil
---@param ctx lsp.HandlerContext
---@param config table|nil
local function wrapper(err, result, ctx, config)
  -- call original handler to preserve existing functionality
  if M._orig_publish then
    M._orig_publish(err, result, ctx, config)
  end

  if not result or not result.diagnostics or type(result.diagnostics) ~= "table" then
    return
  end

  -- find client by ctx.client_id (defensive)
  local client = nil
  if ctx and ctx.client_id then
    client = vim.lsp.get_client_by_id(ctx.client_id)
  end

  local server_name = client and client.name or nil
  if server_name and M.server_callbacks[server_name] then
    -- call the server-specific callback asynchronously (non-blocking)
    -- Use pcall to avoid throwing errors into the LSP path
    local ok, err_msg = pcall(function()
      M.server_callbacks[server_name](err, result, ctx, config)
    end)
    if not ok then
      notify.error("myplugin.lsp_common: server callback error: " .. tostring(err_msg))
    end
  end
end

-- Install the wrapper into vim.lsp.handlers.
function M.setup()
  vim.lsp.handlers["textDocument/publishDiagnostics"] = wrapper
end

return M
