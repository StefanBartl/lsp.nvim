---@module 'lsp.bindings.autocmds'
---@brief Autocommand groups owned by lsp.nvim.
---@description
--- One group, `lsp_nvim`, so `clear()` really removes everything this plugin
--- registered and the group stays reloadable.
---
--- Currently one handler, and what it is for is not what this file used to say.
--- It was written on the premise that Neovim sets the `gr*` family (`grn`,
--- `grr`, `gri`, `grt`, `gO`) buffer-locally when a language server attaches, so
--- a catalogue entry using one of those left-hand sides would be silently
--- shadowed in exactly the buffers it is meant for.
---
--- That premise does not survive measurement. `$VIMRUNTIME/lua/vim/_core/
--- defaults.lua` maps all of them *globally* at startup, and says why: they are
--- mapped unconditionally so behaviour does not depend on whether a client is
--- attached. Measured on 0.12.2 with a real client attaching to a real buffer,
--- `maparg("grn", "n", false, true).buffer` reads 0 before and after -- there is
--- no buffer-local mapping at any point. The catalogue's global entries already
--- own the keys before a client exists, which `config/KEYMAPS.lua` records too.
---
--- The handler is kept rather than deleted, because the plugin supports 0.11 and
--- that version cannot be measured from here. What changed is that it now looks
--- for the buffer-local mapping it exists to beat instead of assuming one. On a
--- Neovim that maps globally it does nothing; on one that does not, it does what
--- the first paragraph describes. Re-binding unconditionally also meant
--- overwriting a buffer-local `grn` a user had set in their own ftplugin.
---
--- Format-on-save lives in `lsp/formatter/init.lua`'s own augroup and the
--- diagnostics refresh in `core/`, both from before this file existed. Moving
--- them here is worth doing but is not a keymap concern.
---
---@see lsp.bindings.keymaps
---@see lsp.config.KEYMAPS

local autocmd = require("lib.nvim.bindings.autocmd")
local keymaps = require("lsp.bindings.keymaps")

local M = {}

--- Augroup every autocommand of this plugin is registered under.
---@type string
M.GROUP = "lsp_nvim"

--- Catalogue entries whose left-hand side collides with a Neovim `gr*` default.
--- Kept as a list rather than derived from the entries, because the collision is
--- a property of Neovim's defaults, not of the catalogue -- deriving it would
--- mean hardcoding the same list of Neovim keys somewhere else.
---
--- Whether a collision needs answering at attach time is decided per buffer by
--- `keymaps.rebind_buffer_local`, not assumed here: see the note at the top.
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
