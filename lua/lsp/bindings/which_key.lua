---@module 'lsp.bindings.which_key'
---@brief Labels the plugin's key prefixes as which-key groups.
---@description
--- which-key is a soft dependency: absent, this is a no-op, and no mapping
--- depends on it (NEW-22 asks that every mapping *supports* which-key, not that
--- which-key be required).
---
--- Groups are derived from the keymaps that were actually registered, not from
--- a hand-kept list -- a prefix that nothing binds gets no label, and a new
--- catalogue entry needs no change here.
---
---@see lsp.bindings.keymaps

local M = {}

---@internal
--- Leading `<leader>x` style prefix of a left-hand side, or nil when the lhs is
--- not part of a prefix tree worth labelling.
---@param lhs string
---@return string|nil
local function prefix_of(lhs)
  local leader, first = lhs:match("^(<[Ll]eader>)(.)")
  if leader == nil then
    return nil
  end
  return leader .. first
end

--- Register a group label per bound prefix.
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

  ---@type table<string, true>
  local seen = {}
  ---@type table[]
  local groups = {}
  for _, spec in ipairs(registered) do
    local prefix = prefix_of(spec.lhs)
    if prefix ~= nil and not seen[prefix] then
      seen[prefix] = true
      groups[#groups + 1] = { prefix, group = "LSP" }
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
