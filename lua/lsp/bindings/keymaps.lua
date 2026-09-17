---@module 'lsp.bindings.keymaps'
---@brief Registers the keymap catalogue, honoring the user's overrides.
---@description
--- Reads `config/KEYMAPS.lua` and hands the catalogue to
--- `lib.nvim.bindings.keymap`'s registry, which applies `keymaps.map` and
--- binds what is left. No key is hardcoded here: adding a mapping means adding
--- a catalogue entry, which is what keeps `docs/BINDINGS.md` generatable and
--- `:checkhealth lsp` able to list what is actually bound.
---
--- The catalogue predates that registry and had grown the same shape
--- independently -- named entries, per-action override, `false` to disable, a
--- list handed back for docs. Moving onto the shared one keeps all of that and
--- adds what a local copy could not: a mistyped name in `keymaps.map` is now
--- *reported* rather than silently binding nothing, and the surface joins the
--- one list `keymap.registered()` answers for every plugin here.
---
--- Every action is overridable and every action is switchable off (NEW-21):
--- a string in `keymaps.map` replaces the lhs, `false` drops the mapping, and
--- `keymaps.enable = false` skips the whole step.
---
--- `requires` is recorded, not enforced. Enforcing it would mean probing with
--- `pcall(require, …)` at setup time, which force-loads a plugin the user
--- configured to load on demand -- slower, and a behaviour change. The entries
--- that name a `requires` are command strings that stay inert until pressed
--- (letting the plugin manager load the plugin then) or Lua functions that
--- require lazily inside themselves. `:checkhealth lsp` reports a bound entry
--- whose plugin is absent; that is the right place for it.
---
---@see lsp.config.KEYMAPS
---@see lsp.bindings.actions
---@see lsp.bindings.which_key

local keymap = require("lib.nvim.bindings.keymap")
local KEYMAPS = require("lsp.config.KEYMAPS")

local M = {}

--- Bind the configured preset.
---@param cfg LspNvim.Config
---@return LspNvim.KeymapSpec[] registered # sorted by catalogue name.
function M.setup(cfg)
  -- Sorted so registration order -- and thus docs/BINDINGS.md and the health
  -- report -- is stable across runs rather than following table iteration.
  local names = vim.tbl_keys(KEYMAPS.entries)
  table.sort(names)

  local in_preset = {}
  for _, name in ipairs(KEYMAPS.presets[cfg.keymaps.preset] or {}) do
    in_preset[name] = true
  end

  ---@type table<string, Lib.Keymap.Action>
  local actions = {}
  for name, spec in pairs(KEYMAPS.entries) do
    actions[name] = {
      default = spec.lhs,
      mode = spec.mode,
      rhs = spec.rhs,
      desc = spec.desc,
      opts = { silent = true },
    }
  end

  -- Entries outside the selected preset are forced off rather than left out:
  -- `:checkhealth lsp` and the generated bindings page ask what EXISTS, and
  -- "in the catalogue, not in this preset" is a different answer from "no such
  -- entry".
  local user = vim.deepcopy(cfg.keymaps.map or {})
  for _, name in ipairs(names) do
    if not in_preset[name] and user[name] == nil then
      user[name] = false
    end
  end

  local bound = keymap.register("LSP", { order = names, actions = actions }, user, {
    bind = cfg.keymaps.enable ~= false,
  })

  ---@type LspNvim.KeymapSpec[]
  local registered = {}
  for _, e in ipairs(bound) do
    if e.bound then
      registered[#registered + 1] =
        vim.tbl_extend("force", KEYMAPS.entries[e.name], { lhs = e.lhs, name = e.name })
    end
  end
  return registered
end

---@internal
--- Does `bufnr` carry a buffer-local mapping for `lhs` that is *Neovim's own*
--- LSP default, rather than one somebody set deliberately?
---
--- Both halves matter, and getting only the first one right inverts the answer.
--- A plain "is it mapped buffer-locally" test fires on exactly the mappings that
--- must not be touched: on a Neovim whose `gr*` defaults are global there is
--- never a default to find, so the only buffer-local `grn` that can exist is the
--- user's, and re-binding over it is the one outcome worse than doing nothing.
--- Measured, with that weaker test in place: a user's `grn` in a scratch buffer
--- came back out of the re-bind reading `LSP: Rename symbol`.
---
--- Neovim's own is recognisable -- it dispatches straight to `vim.lsp.buf.*` and
--- `maparg` reports that as the description (`vim.lsp.buf.rename()` for `grn`).
--- A user who mimics that description exactly gets replaced, which is the one
--- false positive left and is not worth more machinery than this.
---
--- `lhs` is compared through `nvim_replace_termcodes`, because Neovim stores a
--- mapping under the *resolved* sequence: a `<leader>`-prefixed left-hand side
--- comes back out of `nvim_buf_get_keymap` already expanded, so comparing the
--- notation this function was handed never matches. The same trap cost `tools/`
--- a "bind once" guard that fired every time.
---@param mode string|string[]
---@param lhs string
---@param bufnr integer
---@return boolean
local function shadowed_by_neovim_default(mode, lhs, bufnr)
  local want = vim.api.nvim_replace_termcodes(lhs, true, true, true)
  local modes = (type(mode) == "table") and mode or { mode }
  for _, m in ipairs(modes) do
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, m)) do
      if vim.api.nvim_replace_termcodes(map.lhs, true, true, true) == want then
        return type(map.desc) == "string" and map.desc:match("^vim%.lsp%.buf%.") ~= nil
      end
    end
  end
  return false
end

--- Re-bind one catalogue entry buffer-locally.
---
--- For the `gr*` family, and only when there is something to answer. A
--- buffer-local mapping wins over a global one, so a buffer-local `grn` would
--- shadow the catalogue's -- harmless while both call `vim.lsp.buf.rename`, but
--- wrong as soon as `rename.provider` selects inc-rename (roadmap section 8.1).
---
--- This used to re-bind unconditionally, on the assumption that Neovim installs
--- those maps buffer-locally on |LspAttach|. It does not: they are global from
--- startup, measured before and after a real attach on 0.12.2. So the function
--- now checks the buffer first and returns false when nothing shadows the
--- catalogue -- which on a current Neovim is every time. The check is what keeps
--- this honest on a version that behaves differently, and it stops the re-bind
--- from clobbering a buffer-local mapping the *user* set in an ftplugin.
---@param cfg LspNvim.Config
---@param name string # Catalogue entry name.
---@param bufnr integer
---@return boolean bound
function M.rebind_buffer_local(cfg, name, bufnr)
  if not cfg.keymaps.enable then
    return false
  end

  local spec = KEYMAPS.entries[name]
  local override = (cfg.keymaps.map or {})[name]
  if spec == nil or override == false then
    return false
  end

  -- The same question `setup()` answers, not a second one: out-of-preset
  -- entries are forced off there only when the user said *nothing* about them
  -- (`user[name] == nil`), so an explicit lhs re-enables one. Asking "is it in
  -- the preset" alone disagreed, and the disagreement is the bug: with
  -- `preset = "minimal", map = { rename = "grn" }`, `setup()` binds `grn` and
  -- this would have refused to defend it. Whether that refusal costs anything
  -- depends on the Neovim underneath -- on a current one nothing shadows the
  -- mapping anyway -- but the two answers have to agree about which entries are
  -- bound regardless, or this function is reasoning about a different keymap
  -- set than the one that exists.
  local in_preset = vim.tbl_contains(KEYMAPS.presets[cfg.keymaps.preset] or {}, name)
  if not in_preset and override == nil then
    return false
  end

  local lhs = (type(override) == "string") and override or spec.lhs

  -- No Neovim default shadowing the catalogue here, so there is nothing to
  -- re-assert. On a Neovim whose `gr*` defaults are global -- every version this
  -- can be measured against -- that is the answer every time, and the whole
  -- handler costs one keymap scan per attach.
  if not shadowed_by_neovim_default(spec.mode, lhs, bufnr) then
    return false
  end

  -- The one-off setter, not the registry: this re-binds a single entry that is
  -- already declared, to shadow a buffer-local mapping that beat it.
  -- Registering it again would replace the plugin's whole record with one
  -- action.
  keymap(spec.mode, lhs, spec.rhs, {
    buffer = bufnr,
    silent = true,
    desc = "LSP: " .. spec.desc,
  })
  return true
end

return M
