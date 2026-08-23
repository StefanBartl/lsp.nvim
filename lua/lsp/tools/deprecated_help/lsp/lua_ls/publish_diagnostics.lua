---@module 'lsp.tools.deprecated_help.lsp.lua_ls.publish_diagnostics'
--- Wraps `vim.lsp.handlers["textDocument/publishDiagnostics"]` to catch
--- lua_ls's deprecated-symbol diagnostics as they arrive, feeding the rest
--- of deprecated_help.

local M = {}

local diagnostic = require("lsp.tools.deprecated_help.lsp.lua_ls.diagnostic")

-- Wrap the default LSP diagnostics handler
---@param opts table
function M.wrap(opts)
  local orig = vim.lsp.handlers["textDocument/publishDiagnostics"]
  if not orig then
    return
  end

  -- Capture the handler table once (avoids duplicate-field warning)
  local handlers = vim.lsp.handlers

  ---@cast handlers any
  handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
    if not result or not result.diagnostics then
      return orig(err, result, ctx, config)
    end

    if opts.annotate_diagnostics then
      for _, d in ipairs(result.diagnostics) do
        if diagnostic.is_deprecated_warning(d) then
          if
            type(d.message) == "string"
            and not string.find(d.message, opts.diagnostic_hint, 1, true)
          then
            d.message = d.message .. opts.diagnostic_hint
          end
        end
      end
    end

    return orig(err, result, ctx, config)
  end
end

return M
