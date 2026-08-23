---@module 'lsp.config'
---@brief Runtime configuration store for lsp.nvim.
---@description
--- Merges the user's options over `DEFAULTS` and hands out the result via
--- `get()`. Nothing else in the plugin reads `DEFAULTS` directly, and nothing
--- reads a field off this module -- `get()` is the only access path, so the
--- fallback and normalization below cannot be bypassed.
---
--- Normalization follows Postel's law (LUA-80..83): an out-of-range value is
--- pulled back to the documented default and recorded as a warning rather than
--- passed through or raised. A typo in a config file should degrade the
--- feature, not break startup -- but it must still be visible, which is what
--- `warnings()` and `:checkhealth lsp` are for.
---
---@see lsp.config.DEFAULTS
---@see lsp.config.KEYMAPS
---@see lsp.health

local DEFAULTS = require("lsp.config.DEFAULTS")
local KEYMAPS = require("lsp.config.KEYMAPS")

local M = {}

---@type LspNvim.Config|nil
local _active = nil

---@type string[]
local _warnings = {}

---@internal
--- Force `keymaps` into a shape `bindings/keymaps.lua` can iterate without
--- re-checking: a known preset name and a table of overrides.
---@param cfg LspNvim.Config
---@return nil
local function normalize_keymaps(cfg)
  local km = cfg.keymaps
  if type(km) ~= "table" then
    _warnings[#_warnings + 1] = "keymaps: expected a table, using defaults"
    cfg.keymaps = vim.deepcopy(DEFAULTS.keymaps)
    return
  end

  if km.enable == nil then
    km.enable = true
  end

  if KEYMAPS[km.preset] == nil then
    if km.preset ~= nil then
      _warnings[#_warnings + 1] = ("keymaps.preset: unknown value %q, falling back to %q"):format(
        tostring(km.preset),
        DEFAULTS.keymaps.preset
      )
    end
    km.preset = DEFAULTS.keymaps.preset
  end

  if type(km.map) ~= "table" then
    if km.map ~= nil then
      _warnings[#_warnings + 1] = "keymaps.map: expected a table of overrides, ignoring"
    end
    km.map = {}
  end
end

---@internal
--- Force a `{ enable = boolean }` sub-table into shape.
---@param cfg LspNvim.Config
---@param key string # Field name on `cfg`.
---@return nil
local function normalize_switch(cfg, key)
  local sub = cfg[key]
  if type(sub) ~= "table" then
    if sub ~= nil then
      _warnings[#_warnings + 1] = ("%s: expected a table, using defaults"):format(key)
    end
    cfg[key] = vim.deepcopy(DEFAULTS[key])
    return
  end
  if type(sub.enable) ~= "boolean" then
    sub.enable = DEFAULTS[key].enable
  end
end

--- Merge the user's options over the defaults, normalize, and store the result.
---@param user_opts? LspNvim.Config|table
---@return LspNvim.Config
function M.setup(user_opts)
  if type(user_opts) ~= "table" then
    if user_opts ~= nil then
      _warnings[#_warnings + 1] = "setup(): expected a table of options, ignoring"
    end
    user_opts = {}
  end

  _warnings = {}

  ---@diagnostic disable-next-line: missing-fields
  local cfg = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), user_opts)
  normalize_keymaps(cfg)
  normalize_switch(cfg, "usrcmds")
  normalize_switch(cfg, "which_key")

  _active = cfg
  return cfg
end

--- The active configuration. Falls back to a copy of the defaults when
--- `setup()` has not run, so `:checkhealth lsp` works on a bare install.
---@return LspNvim.Config
function M.get()
  if _active == nil then
    _active = vim.deepcopy(DEFAULTS)
  end
  return _active
end

--- Problems found while normalizing the last `setup()` call. Empty when the
--- configuration was clean, or when `setup()` has not run.
---@return string[]
function M.warnings()
  return _warnings
end

return M
