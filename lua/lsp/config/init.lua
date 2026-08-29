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

  if KEYMAPS.presets[km.preset] == nil then
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
  -- `usrcmds` carries a second boolean; normalizing it here keeps the switch
  -- guards downstream from having to re-check its type.
  if key == "usrcmds" and type(sub.legacy_aliases) ~= "boolean" then
    sub.legacy_aliases = DEFAULTS.usrcmds.legacy_aliases
  end
end

---@internal
--- Force `servers` into a non-empty array of strings. An empty or malformed
--- list would silently mean "no language server at all", which looks exactly
--- like a broken installation -- so it degrades to the default set and says so.
---@param cfg LspNvim.Config
---@return nil
local function normalize_servers(cfg)
  local list = cfg.servers
  if type(list) ~= "table" then
    _warnings[#_warnings + 1] = "servers: expected a list of names, using defaults"
    cfg.servers = vim.deepcopy(DEFAULTS.servers)
    return
  end

  ---@type string[]
  local clean = {}
  for _, name in ipairs(list) do
    if type(name) == "string" and name ~= "" then
      clean[#clean + 1] = name
    else
      _warnings[#_warnings + 1] = ("servers: ignoring non-string entry %s"):format(
        vim.inspect(name)
      )
    end
  end

  if #clean == 0 then
    _warnings[#_warnings + 1] = "servers: list is empty, using defaults"
    clean = vim.deepcopy(DEFAULTS.servers)
  end
  cfg.servers = clean
end

---@internal
--- Force a sub-table back to its default when the user replaced it with
--- something that is not a table at all. Deep-merge already filled in the
--- fields; this only catches `formatter = false` style mistakes, where every
--- field access downstream would error.
---@param cfg LspNvim.Config
---@param key string
---@return nil
local function normalize_table(cfg, key)
  if type(cfg[key]) ~= "table" then
    if cfg[key] ~= nil then
      _warnings[#_warnings + 1] = ("%s: expected a table, using defaults"):format(key)
    end
    cfg[key] = vim.deepcopy(DEFAULTS[key])
  end
end

--- Merge the user's options over the defaults, normalize, and store the result.
---@param user_opts? LspNvim.Config|table
---@return LspNvim.Config
function M.setup(user_opts)
  -- Cleared first, not after the type check below: appending a warning and
  -- then resetting the list discards it, which is exactly what used to happen
  -- to the "expected a table" warning -- the one case where the caller most
  -- needs to be told.
  _warnings = {}

  if type(user_opts) ~= "table" then
    if user_opts ~= nil then
      _warnings[#_warnings + 1] = "setup(): expected a table of options, ignoring"
    end
    user_opts = {}
  end

  ---@diagnostic disable-next-line: missing-fields
  local cfg = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), user_opts)
  normalize_keymaps(cfg)
  normalize_switch(cfg, "usrcmds")
  normalize_switch(cfg, "which_key")
  normalize_servers(cfg)
  if cfg.rename.provider ~= "inc_rename" and cfg.rename.provider ~= "native" then
    if cfg.rename.provider ~= "auto" and cfg.rename.provider ~= nil then
      _warnings[#_warnings + 1] = ('rename.provider: unknown value %q, using "auto"'):format(
        tostring(cfg.rename.provider)
      )
    end
    cfg.rename.provider = "auto"
  end
  for _, key in ipairs({
    "rename",
    "diagnostics",
    "formatter",
    "inlay_hints",
    "attach",
    "mason",
    "lspdoctor",
    "tools",
    "languages",
    "completion",
  }) do
    normalize_table(cfg, key)
  end

  -- `labels` is the one option that is a function rather than data. Anything
  -- else there would blow up at the call site inside the source, far from the
  -- setup() call that caused it, so it is rejected here instead.
  if type(cfg.completion.personal_names) ~= "table" then
    cfg.completion.personal_names = vim.deepcopy(DEFAULTS.completion.personal_names)
  end
  local labels = cfg.completion.personal_names.labels
  if labels ~= nil and type(labels) ~= "function" then
    _warnings[#_warnings + 1] = "completion.personal_names.labels: expected a function, ignoring"
    cfg.completion.personal_names.labels = nil
  end

  -- The override map is the one config value a typo turns into a silent
  -- no-op: a stray `filetypes = { "lua" }` (a list, not a map) would resolve
  -- every lookup to nil and simply never override anything.
  if type(cfg.inlay_hints.filetypes) ~= "table" then
    if cfg.inlay_hints.filetypes ~= nil then
      _warnings[#_warnings + 1] =
        "inlay_hints.filetypes: expected a filetype -> boolean map, ignoring"
    end
    cfg.inlay_hints.filetypes = {}
  else
    for ft, value in pairs(cfg.inlay_hints.filetypes) do
      if type(ft) ~= "string" or type(value) ~= "boolean" then
        _warnings[#_warnings + 1] = ("inlay_hints.filetypes: ignoring entry %s = %s (want string = boolean)"):format(
          vim.inspect(ft),
          vim.inspect(value)
        )
        cfg.inlay_hints.filetypes[ft] = nil
      end
    end
  end
  if type(cfg.inlay_hints.enable) ~= "boolean" then
    cfg.inlay_hints.enable = DEFAULTS.inlay_hints.enable
  end

  if
    cfg.diagnostics.ui ~= "auto"
    and cfg.diagnostics.ui ~= "native"
    and cfg.diagnostics.ui ~= "trouble"
  then
    if cfg.diagnostics.ui ~= nil then
      _warnings[#_warnings + 1] = ('diagnostics.ui: unknown value %q, using "auto"'):format(
        tostring(cfg.diagnostics.ui)
      )
    end
    cfg.diagnostics.ui = "auto"
  end

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
