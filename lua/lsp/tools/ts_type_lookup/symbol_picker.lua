---@module 'lsp.tools.ts_type_lookup.symbol_picker'
---@brief `:TypeDefPick` -- workspace symbols, through the picker the rest of
---@brief the plugin already uses.
---@description
--- This was 171 lines of hand-rolled Telescope: its own finder, its own entry
--- maker, a buffer previewer that read the file with `readfile()` and showed
--- three lines either side of the hit, and a `<CR>` action that opened a
--- vsplit. All of it to put the answer to one `workspace/symbol` request on
--- screen.
---
--- fzf-lua answers the same request with `lsp_workspace_symbols`, and fzf-lua
--- is already this plugin's picker -- `<leader>dos`, `<leader>wos`,
--- `<leader>do` and `<leader>wo` are `<cmd>FzfLua …<cr>` entries in the keymap
--- catalogue. Two backends for the same kind of list meant two sets of keys
--- *inside* the picker, two preview behaviours, and two plugins to have
--- installed for one feature. Now it is one.
---
--- **What changes at the keyboard**: `:TypeDefPick` opens the same window as
--- `<leader>wos`, with fzf-lua's preview and its open actions, instead of a
--- Telescope window whose only action was a vsplit.
---
--- **What does not change**: Telescope is still a dependency of the plugin as
--- a whole. `lsp.languages.webdev.astro` uses `telescope.builtin` for its
--- component/layout/page navigation, behind a `FileType astro` autocommand.
--- What is gone is a *second picker for the same list*, not Telescope.
---
--- Roadmap M4a. M4b -- a real adapter over fzf-lua, telescope, snacks and
--- pickers.nvim -- is deliberately not this: an abstraction is worth building
--- when there is a second backend to abstract, and removing the second backend
--- is the cheaper half of that trade.
---
---@see lsp.config.KEYMAPS
---@see lsp.integrations.picker

local notify = require("lib.nvim.notify").create("[lsp.tools.ts_type_lookup.symbol_picker]")
local usercmd = require("lib.nvim.bindings.usercmd")

local fn = vim.fn

local M = {}

--- Open the workspace-symbol picker for a query.
---@param query string|nil # Defaults to the word under the cursor.
---@return boolean opened
function M.pick(query)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    notify.warn("fzf-lua is not installed -- it is the picker `<leader>wos` uses too")
    return false
  end

  query = (query ~= nil and query ~= "") and query or fn.expand("<cword>")
  if query == "" then
    notify.warn("no symbol under the cursor, and no argument given")
    return false
  end

  -- `lsp_query` is what goes to the server in `workspace/symbol`. fzf-lua's
  -- own `query` option is the filter applied to what came back, which is a
  -- different thing and would ask the server for everything.
  fzf.lsp_workspace_symbols({ lsp_query = query })
  return true
end

--- Register `:TypeDefPick`.
---@return nil
function M.attach()
  usercmd.create("TypeDefPick", function(opts)
    M.pick(opts.args ~= "" and opts.args or nil)
  end, { nargs = "?", desc = "Workspace symbols for a query (default: the word under the cursor)" })
end

return M
