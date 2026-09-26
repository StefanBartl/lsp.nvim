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

---Send the groups to a loaded which-key.
---
---which-key v3 takes a flat list of specs; v2 wants a keyed table passed to
---`register`. Try v3 first, since `add` does not exist on v2.
---@param wk table
---@param groups table[]
---@return integer count # `#groups` when which-key took them, else 0.
local function deliver(wk, groups)
  local accepted
  if type(wk.add) == "function" then
    accepted = pcall(wk.add, groups)
  ---@diagnostic disable-next-line: deprecated
  elseif type(wk.register) == "function" then
    ---@type table<string, table>
    local v2 = {}
    for _, g in ipairs(groups) do
      v2[g[1]] = { name = g.group }
    end
    ---@diagnostic disable-next-line: deprecated
    accepted = pcall(wk.register, v2)
  else
    return 0
  end

  -- The `pcall` result is what the count reports, rather than `#groups`
  -- unconditionally. Measured against a which-key whose `add` raises: this
  -- returned 2 while nothing had been registered, and a count that cannot be
  -- wrong is the only reason to return one.
  return accepted and #groups or 0
end

--- Register a group label per owned prefix that actually has a binding under it.
---@param cfg LspNvim.Config
---@param registered LspNvim.KeymapSpec[]
---@return integer count # Groups registered now; 0 while which-key is not loaded yet
---   (they are delivered when it loads).
function M.setup(cfg, registered)
  if not cfg.which_key.enable then
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

  -- Sorted for the reason `keymaps.setup` sorts its catalogue names: the loop
  -- above walks `KEYMAPS.groups` with `pairs`, and the list it produced here
  -- handed which-key `<leader>xl` before `<leader>x` -- neither catalogue
  -- order nor any order a second run has to repeat.
  table.sort(groups, function(a, b)
    return a[1] < b[1]
  end)

  -- Hand the labels over when which-key is there: now if it is loaded, else when
  -- it loads. Never `require` it here -- under a lazy manager that is the load
  -- trigger, and this runs in the synchronous startup phase for a popup nobody
  -- has opened (which-key is meant to load on the first `<leader>`).
  local counted = 0
  local ran_now = require("lib.nvim.bindings.keymap.which_key").when_loaded(function(wk)
    counted = deliver(wk, groups)
  end)

  -- Groups registered so far: what the call reported when which-key was
  -- loaded, nothing yet when the labels are waiting for it.
  return ran_now and counted or 0
end

return M
