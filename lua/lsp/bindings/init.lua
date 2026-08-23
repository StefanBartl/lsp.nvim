---@module 'lsp.bindings'
---@brief Registers everything the plugin binds: keymaps, commands, autocmds.
---@description
--- One entry point, one order. `init.lua` calls this and nothing else, so
--- "what does this plugin claim when it loads" has exactly one answer to read.
---
--- Order matters in one place only: which-key labels the prefixes of the
--- keymaps that were actually registered, so it runs after them.
---
---@see lsp.bindings.keymaps
---@see lsp.bindings.usrcmds
---@see lsp.bindings.autocmds
---@see lsp.bindings.which_key

local keymaps = require("lsp.bindings.keymaps")
local usrcmds = require("lsp.bindings.usrcmds")
local autocmds = require("lsp.bindings.autocmds")
local which_key = require("lsp.bindings.which_key")

local M = {}

--- Bind the configured key set, register `:Lsp`, install the autocommands.
---@param cfg LspNvim.Config
---@return LspNvim.KeymapSpec[] registered_keymaps
---@return boolean usrcmd_registered
function M.setup(cfg)
  local registered = keymaps.setup(cfg)
  which_key.setup(cfg, registered)
  autocmds.setup(cfg)

  local usrcmd = false
  if cfg.usrcmds.enable then
    usrcmd = usrcmds.setup()
  end

  return registered, usrcmd
end

return M
