---@module 'lsp.servers.lua_ls.error_handler'
--- Error handler for lua_ls to catch malformed requests

local notify = require("lib.nvim.notify").create("[lsp.servers.lua_ls.error_handler]")

local M = {}

--- Wrap lua_ls client request to catch textDocument errors
---@param client table LSP client object
function M.wrap_client(client)
  if not client or type(client.request) ~= "function" then
    return
  end

  local original_request = client.request

  client.request = function(self, method, params, handler, bufnr)
    -- Guard: ensure params.textDocument exists for methods that need it
    local needs_text_doc = {
      ["textDocument/hover"] = true,
      ["textDocument/definition"] = true,
      ["textDocument/signatureHelp"] = true,
      ["textDocument/completion"] = true,
    }

    if needs_text_doc[method] then
      if not params or not params.textDocument then
        notify.warn(
          string.format("[lua_ls] Prevented malformed request: %s missing textDocument", method)
        )
        return nil, "malformed_request"
      end
    end

    return original_request(self, method, params, handler, bufnr)
  end
end

return M
