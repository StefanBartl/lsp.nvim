---@module 'lsp.core.handlers'
--- Wraps `textDocument/publishDiagnostics` to run every diagnostic list
--- through `lsp.core.filter`'s dedup before Neovim renders it.

local M = {}

---Wraps publishDiagnostics to deduplicate entries before showing.
---@return nil
function M.setup()
  local filter_ok, filter = pcall(require, "lsp.core.filter")
  if not filter_ok then
    return
  end

  local orig = vim.lsp.handlers["textDocument/publishDiagnostics"]

  -- Capture the handler table once (avoids duplicate-field warning)
  local handlers = vim.lsp.handlers

  ---@cast handlers any
  handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, conf)
    if result and type(result.diagnostics) == "table" then
      -- shallow copy to avoid mutating LSP payload
      local copy = { uri = result.uri, diagnostics = {} }
      -- optional: normalize to avoid flapping columns if server omits 'col'
      for i, d in ipairs(result.diagnostics) do
        copy.diagnostics[i] = d
      end
      copy.diagnostics = filter.dedup(copy.diagnostics)
      return orig(err, copy, ctx, conf)
    end
    return orig(err, result, ctx, conf)
  end
end

return M
