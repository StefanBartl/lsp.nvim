---@module 'lsp.core.root_scope_picker'
--- <leader>lsp: pick the LSP root-scope (cwd/git/path) via lib.nvim's select
--- chooser. Selecting an entry updates lsp.core.root_scope, which fires
--- `User LspRootScopeChanged` so lua_ls recomputes root_dir for open buffers
--- (see lsp.servers.lua_ls.reload).

local select = require("lib.nvim.ui.kit.select")
local root_scope = require("lsp.core.root_scope")
local notify = require("lib.nvim.notify").create("[lsp.core.root_scope_picker]")

local M = {}

--- Open the scope picker.
---@return nil
function M.open()
  local current = root_scope.get()

  local items = {}
  for i, scope in ipairs(root_scope.SCOPES) do
    local marker = (scope == current) and "● " or "  "
    items[i] = marker .. root_scope.label(scope)
  end

  select.open({
    items = items,
    title = "LSP Root-Scope (aktuell: " .. current .. ")",
    on_select = function(_, idx)
      local scope = root_scope.SCOPES[idx]
      if not scope then
        return
      end
      if root_scope.set(scope) then
        notify.info("Root-Scope: " .. root_scope.label(scope))
      end
    end,
  })
end

return M
