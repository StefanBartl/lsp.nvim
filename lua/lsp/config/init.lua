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
--- Take a list option from the *user's* table rather than the merged one.
---
--- `vim.tbl_deep_extend` merges two arrays index by index, which is wrong for
--- every list option here: `{ "lua_ls" }` over a six-entry default yields
--- `{ "lua_ls", <defaults 2..6> }`, so a config asking for one server silently
--- gets six. A list is a replacement, not an overlay -- there is no sensible
--- reading of "half the default markers".
---@param user_opts table
---@param key string # Top-level key on the user's options.
---@param field string|nil # Sub-field, for a list nested one level down.
---@return string[]|nil # nil when the user did not supply a list at all.
local function user_list(user_opts, key, field)
  local value = user_opts[key]
  if field ~= nil then
    value = type(value) == "table" and value[field] or nil
  end
  if type(value) ~= "table" or not vim.islist(value) then
    return nil
  end
  return value
end

---@internal
--- Clean a list of names down to the non-empty strings in it.
---@param list any[]
---@param label string # Option path, for the warning.
---@return string[]
local function clean_names(list, label)
  ---@type string[]
  local clean = {}
  for _, name in ipairs(list) do
    if type(name) == "string" and name ~= "" then
      clean[#clean + 1] = name
    else
      _warnings[#_warnings + 1] = ("%s: ignoring non-string entry %s"):format(
        label,
        vim.inspect(name)
      )
    end
  end
  return clean
end

---@internal
--- Force `servers` into a non-empty array of strings. An empty or malformed
--- list would silently mean "no language server at all", which looks exactly
--- like a broken installation -- so it degrades to the default set and says so.
---
--- Read from `user_opts`, not from the merged table, for the reason `user_list`
--- gives: `servers = { "lua_ls" }` used to come out of the deep-merge as
--- `{ "lua_ls", "gopls", "marksman", ... }` -- every default from index two on
--- survived, so narrowing the server list did almost nothing and said nothing
--- about it. That is the one behaviour change in this function: a config that
--- names servers now gets those servers and no others.
---@param cfg LspNvim.Config
---@param user_opts table
---@return nil
local function normalize_servers(cfg, user_opts)
  local list = user_list(user_opts, "servers") or cfg.servers
  if type(list) ~= "table" then
    _warnings[#_warnings + 1] = "servers: expected a list of names, using defaults"
    cfg.servers = vim.deepcopy(DEFAULTS.servers)
    return
  end

  local clean = clean_names(list, "servers")

  if #clean == 0 then
    _warnings[#_warnings + 1] = "servers: list is empty, using defaults"
    clean = vim.deepcopy(DEFAULTS.servers)
  end
  cfg.servers = clean
end

---@internal
--- Force `workspace.markers` / `workspace.containers` into lists of names.
---
--- Both are read only when the workspace-folder picker opens, so a bad value
--- would otherwise surface as an empty candidate list days after the typo --
--- with no hint that the option caused it.
---@param cfg LspNvim.Config
---@param user_opts table
---@return nil
local function normalize_workspace(cfg, user_opts)
  for _, field in ipairs({ "markers", "containers" }) do
    local supplied = user_list(user_opts, "workspace", field)
    local list = supplied or cfg.workspace[field]

    if type(list) ~= "table" then
      if list ~= nil then
        _warnings[#_warnings + 1] = ("workspace.%s: expected a list of names, using defaults"):format(
          field
        )
      end
      cfg.workspace[field] = vim.deepcopy(DEFAULTS.workspace[field])
    else
      cfg.workspace[field] = clean_names(list, "workspace." .. field)
    end
  end

  -- An empty marker list is not degraded to the default: "offer me nothing but
  -- the client roots and the cwd" is a coherent wish, and silently restoring
  -- eighteen markers over it would be the config lying. `containers` likewise.
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
  normalize_servers(cfg, user_opts)
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
    "workspace",
  }) do
    normalize_table(cfg, key)
  end
  normalize_workspace(cfg, user_opts)

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

  -- A negative or non-numeric window would reach `uv.timer:start()` and raise
  -- there, inside a handler, on every push -- far from the setup() call that
  -- caused it.
  local debounce = cfg.diagnostics.debounce_ms
  if type(debounce) ~= "number" or debounce < 0 then
    if debounce ~= nil then
      _warnings[#_warnings + 1] = ("diagnostics.debounce_ms: expected a non-negative number, using %d"):format(
        DEFAULTS.diagnostics.debounce_ms
      )
    end
    cfg.diagnostics.debounce_ms = DEFAULTS.diagnostics.debounce_ms
  else
    cfg.diagnostics.debounce_ms = math.floor(debounce)
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
