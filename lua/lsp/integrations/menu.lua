---@module 'lsp.integrations.menu'
---@brief Context-menu entries for nvzone/menu (soft, opt-in integration).
---@description
--- lsp.nvim does not depend on a menu plugin. It *provides* a list of
--- entries in the shape nvzone/menu expects, built with
--- `lib.nvim.contextmenu`'s helpers, and a host — typically the user's own
--- RightMouse dispatcher — composes them into its own menu, e.g.:
--- >
---   local items = require("lsp.integrations.menu").items()
---   -- prepend/append `items` to your own menu table, then menu.open(composed)
--- <
--- Built from `require("lsp").status().keymaps` — the SAME resolved
--- catalogue `bindings/keymaps.lua` actually registered (the active
--- `keymaps.preset`, with `keymaps.map` overrides/disables already
--- applied) — rather than a second hand-maintained list, the same
--- anti-drift reasoning `config/KEYMAPS.lua`'s own header states for why
--- keymaps are declarative data in the first place. Two entries are
--- skipped as pure alternate-key duplicates of one already included
--- (`rename_leader`, `goto_type_definition_gr` — see `config/KEYMAPS.lua`'s
--- own "one action, two keys" comments), and any entry whose `requires`
--- names a plugin that isn't installed is skipped too: unlike a keymap
--- (invisible until pressed, so a missing `requires` is harmless — see
--- `lsp.bindings.keymaps`'s header), a menu entry is something the user is
--- actively looking at, so one that would just error on click is worse
--- than one that doesn't appear. Opt-out via `config.menu.enable`.

local contextmenu = require("lib.nvim.contextmenu")

local M = {}

---@internal
--- Alternate-key duplicates of an already-included action.
local SKIP = { rename_leader = true, goto_type_definition_gr = true }

---@internal
--- Fly-out group for a catalogue entry, derived from its name so a new
--- entry following the existing naming convention groups correctly without
--- a second, hand-maintained lookup table to keep in sync.
---@param name string
---@return string
local function group_of(name)
  if name:match("^trouble_") then
    return "  Trouble"
  end
  if name:match("^picker_") then
    return "  Picker"
  end
  if name:match("^diag_") or name:match("^qf_") or name:match("^loc_") then
    return "  Diagnostics"
  end
  if name:match("^format_") then
    return "  Formatter"
  end
  if name == "rename" then
    return "  Rename"
  end
  return "  Navigation" -- goto_*, document_symbols, code_action, signature_help, root_scope_pick, marksman_hints
end

---@internal
--- A catalogue entry's `rhs` is a function or a `"<cmd>...<cr>"` string
--- (see `LspNvim.KeymapSpec`); normalize either to a no-argument callback.
---@param rhs string|function
---@return function
local function to_fn(rhs)
  if type(rhs) == "function" then
    return rhs
  end
  local cmd = rhs:match("^<[Cc]md>(.-)<[Cc][Rr]>$") or rhs
  return function()
    vim.cmd(cmd)
  end
end

--- Build the lsp.nvim menu entries, grouped by fly-out.
--- Returns `{}` when the integration is disabled or nothing is registered
--- yet (`require("lsp").setup()` hasn't run), so a host can safely
--- `vim.list_extend`/compose this unconditionally.
---@return Lib.ContextMenu.Item[]
function M.items()
  local cfg = require("lsp.config").get()
  local mcfg = cfg and cfg.menu
  if mcfg and mcfg.enable == false then
    return {}
  end

  local registered = require("lsp").status().keymaps or {}

  -- Bucket by group, preserving `registered`'s own (already sorted-by-name)
  -- order within each bucket.
  local buckets, order = {}, {}
  for _, spec in ipairs(registered) do
    if not SKIP[spec.name] and (not spec.requires or pcall(require, spec.requires)) then
      local g = group_of(spec.name)
      if not buckets[g] then
        buckets[g] = {}
        order[#order + 1] = g
      end
      local entries = buckets[g]
      entries[#entries + 1] = contextmenu.entry(true, "  " .. spec.desc, to_fn(spec.rhs), spec.lhs)
    end
  end

  local out = {}
  for _, g in ipairs(order) do
    local items = buckets[g]
    local sub = contextmenu.submenu(g, items)
    if sub then
      out[#out + 1] = sub
    end
  end

  return out
end

--- Convenience: the entries wrapped as a single nested submenu entry, for
--- hosts that prefer an "LSP ▸" fly-out instead of top-level group entries.
--- Returns nil when there is nothing to show.
---@param label? string submenu label (default "  LSP")
---@return Lib.ContextMenu.Item|nil
function M.submenu(label)
  return contextmenu.submenu(label or "  LSP", M.items())
end

return M
