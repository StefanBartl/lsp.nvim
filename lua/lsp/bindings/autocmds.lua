---@module 'lsp.bindings.autocmds'
---@brief Autocommand groups owned by lsp.nvim.
---@description
--- One group, `lsp_nvim`, so `clear()` really removes everything this plugin
--- registered and the group stays reloadable.
---
--- Currently one handler, and it exists for a specific reason: Neovim sets the
--- `gr*` family (`grn`, `grr`, `gri`, `grt`, `gO`) buffer-locally when a
--- language server attaches, and a buffer-local mapping beats a global one. Any
--- catalogue entry using one of those left-hand sides would therefore be
--- silently shadowed in exactly the buffers it is meant for. Re-binding on
--- |LspAttach| is the only place that can win, because it runs after Neovim's
--- own defaults are in place.
---
--- Format-on-save lives in `lsp/formatter/init.lua`'s own augroup and the
--- diagnostics refresh in `core/`, both from before this file existed. Moving
--- them here is worth doing but is not a keymap concern.
---
---@see lsp.bindings.keymaps
---@see lsp.config.KEYMAPS

local autocmd = require("lib.nvim.autocmd")
local keymaps = require("lsp.bindings.keymaps")

local M = {}

--- Augroup every autocommand of this plugin is registered under.
---@type string
M.GROUP = "lsp_nvim"

--- Catalogue entries whose left-hand side collides with a Neovim 0.11 default
--- that is set buffer-locally on LspAttach. Kept as a list rather than derived
--- from the entries, because the collision is a property of Neovim's defaults,
--- not of the catalogue -- deriving it would mean hardcoding the same list of
--- Neovim keys somewhere else.
---@type string[]
local LSP_ATTACH_REBIND = { "rename", "goto_type_definition_gr" }

--- Create (or reset) the augroup and register the handlers.
---@param cfg LspNvim.Config
---@return integer count # Autocommands registered.
function M.setup(cfg)
  M.clear()

  if not cfg.keymaps.enable then
    return 0
  end

  autocmd.create("LspAttach", function(args)
    for _, name in ipairs(LSP_ATTACH_REBIND) do
      keymaps.rebind_buffer_local(cfg, name, args.buf)
    end
  end, {
    group = autocmd.group(M.GROUP, true),
    desc = "lsp.nvim: re-bind catalogue entries Neovim shadows with its own gr* defaults",
  })

  return 1
end

--- Remove every autocommand this plugin registered.
---
--- `autocmd.group(name, true)` in `setup()` already clears the group on
--- re-registration; this exists for the case where the plugin is told to stop
--- owning autocommands at all.
---@return nil
function M.clear()
  pcall(vim.api.nvim_del_augroup_by_name, M.GROUP)
end

return M
