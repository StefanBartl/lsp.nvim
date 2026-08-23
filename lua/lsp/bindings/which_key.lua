---@module 'lsp.bindings.which_key'
---@brief Labels the plugin's key prefixes as which-key groups.
---@description
--- which-key is a soft dependency: absent, this is a no-op, and no mapping
--- depends on it (NEW-22 asks that every mapping *supports* which-key, not that
--- which-key be required). The individual descriptions need nothing from here
--- either -- which-key reads the `desc` every catalogue entry already carries.
--- What this adds is the group label for a prefix.
---
--- The labels come from `config/KEYMAPS.lua`'s curated `groups` table rather
--- than being derived from the bound left-hand sides. Deriving would label
--- every prefix this plugin touches, and most are shared with the rest of a
--- config (`<leader>f` is find/file, `<leader>d`, `<leader>w`, `<leader>l`,
--- `<leader>t` likewise) -- calling those "LSP" would be actively misleading.
--- A prefix gets a label only when this plugin owns it outright.
---
---@see lsp.bindings.keymaps
---@see lsp.config.KEYMAPS

local KEYMAPS = require("lsp.config.KEYMAPS")

local M = {}

--- Register a group label per owned prefix that actually has a binding under it.
---@param cfg LspNvim.Config
---@param registered LspNvim.KeymapSpec[]
---@return integer count # Groups registered.
function M.setup(cfg, registered)
  if not cfg.which_key.enable then
    return 0
  end

  local ok, wk = pcall(require, "which-key")
  if not ok then
    return 0
  end

  -- Only label a prefix something was actually bound under: a group header
  -- over an empty submenu is worse than no header.
  ---@type table[]
  local groups = {}
  for prefix, label in pairs(KEYMAPS.groups) do
    local used = false
    for _, spec in ipairs(registered) do
      if spec.lhs:sub(1, #prefix) == prefix and #spec.lhs > #prefix then
        used = true
        break
      end
    end
    if used then
      groups[#groups + 1] = { prefix, group = label }
    end
  end

  if #groups == 0 then
    return 0
  end

  -- which-key v3 takes a flat list of specs; v2 wants a keyed table passed to
  -- `register`. Try v3 first, since `add` does not exist on v2.
  if type(wk.add) == "function" then
    pcall(wk.add, groups)
  elseif type(wk.register) == "function" then
    ---@type table<string, table>
    local v2 = {}
    for _, g in ipairs(groups) do
      v2[g[1]] = { name = g.group }
    end
    pcall(wk.register, v2)
  else
    return 0
  end

  return #groups
end

return M
