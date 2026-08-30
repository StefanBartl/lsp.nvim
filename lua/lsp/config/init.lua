---@module 'lsp.config'
---@brief Runtime configuration store for lsp.nvim.
---@description
--- Resolves four layers into one table and hands out the result via `get()`.
--- Nothing else in the plugin reads `DEFAULTS` directly, and nothing reads a
--- field off this module -- `get()` is the only access path, so the fallback
--- and normalization below cannot be bypassed.
---
--- The layers, lowest to highest:
---
--- 1. `DEFAULTS`               -- the documented values.
--- 2. `PRESETS[preset]`        -- one word for "how much of this should run
---                                on this machine" (`lean` / `full`).
--- 3. the `setup()` options    -- what you wrote.
--- 4. `.nvim-lsp.json`         -- what *this checkout* needs, from an
---                                allowlist (`lsp.config.project`).
---
--- The order is the argument for the feature. A preset sits *below* your
--- options because it moves the floor rather than overruling you; the project
--- file sits *above* them because "in this repository, not globally" is the
--- whole thing it is for. Resolution happens in two stages, because the
--- `project` options themselves are read from layers 1-3 -- a project file
--- cannot decide whether project files are read.
---
--- Normalization follows Postel's law (LUA-80..83): an out-of-range value is
--- pulled back to the documented default and recorded as a warning rather than
--- passed through or raised. A typo in a config file should degrade the
--- feature, not break startup -- but it must still be visible, which is what
--- `warnings()` and `:checkhealth lsp` are for. With more than one layer, "it
--- was wrong" stops being enough: every warning names the layer the value came
--- from, because with a preset and a project file in play, *where* is the
--- question a warning has to answer.
---
---@see lsp.config.DEFAULTS
---@see lsp.config.PRESETS
---@see lsp.config.project
---@see lsp.config.KEYMAPS
---@see lsp.health

local DEFAULTS = require("lsp.config.DEFAULTS")
local KEYMAPS = require("lsp.config.KEYMAPS")
local PRESETS = require("lsp.config.PRESETS")
local project = require("lsp.config.project")

local M = {}

---@type LspNvim.Config|nil
local _active = nil

---@type string[]
local _warnings = {}

--- The layers above `DEFAULTS` that actually supplied something, highest
--- precedence first. Used for attribution only -- the merge itself is done by
--- `vim.tbl_deep_extend` -- so this is the answer to "who set that", nothing
--- more.
---@type { label: string, data: table }[]
local _layers = {}

---@type LspNvim.ConfigLayers
local _sources = { preset = "default", project = nil }

---@internal
--- Which layer supplied a value, highest precedence first.
---@param key string|nil # Top-level key; nil to skip attribution entirely.
---@param field string|nil # Sub-field, for a value nested one level down.
---@return string|nil label
local function source_of(key, field)
  if key == nil then
    return nil
  end
  for _, layer in ipairs(_layers) do
    local value = layer.data[key]
    if value ~= nil and field ~= nil then
      value = type(value) == "table" and value[field] or nil
    end
    if value ~= nil then
      return layer.label
    end
  end
  return nil
end

---@internal
--- Record a normalization problem, naming the layer the bad value came from.
---
--- The suffix is the part that earns its keep once presets and project files
--- exist: "servers: list is empty" is a different problem depending on whether
--- you wrote it, a preset did, or a repository you just cloned did.
---@param msg string # The problem, in the "option: what happened" shape.
---@param key string|nil # Top-level option key, for attribution.
---@param field string|nil # Sub-field, when the value sits one level down.
---@return nil
local function warn(msg, key, field)
  local src = source_of(key, field)
  _warnings[#_warnings + 1] = src ~= nil and ("%s (from %s)"):format(msg, src) or msg
end

---@internal
--- Force `keymaps` into a shape `bindings/keymaps.lua` can iterate without
--- re-checking: a known preset name and a table of overrides.
---@param cfg LspNvim.Config
---@return nil
local function normalize_keymaps(cfg)
  local km = cfg.keymaps
  if type(km) ~= "table" then
    warn("keymaps: expected a table, using defaults", "keymaps")
    cfg.keymaps = vim.deepcopy(DEFAULTS.keymaps)
    return
  end

  if km.enable == nil then
    km.enable = true
  end

  if KEYMAPS.presets[km.preset] == nil then
    if km.preset ~= nil then
      warn(
        ("keymaps.preset: unknown value %q, falling back to %q"):format(
          tostring(km.preset),
          DEFAULTS.keymaps.preset
        ),
        "keymaps",
        "preset"
      )
    end
    km.preset = DEFAULTS.keymaps.preset
  end

  if type(km.map) ~= "table" then
    if km.map ~= nil then
      warn("keymaps.map: expected a table of overrides, ignoring", "keymaps", "map")
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
      warn(("%s: expected a table, using defaults"):format(key), key)
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
--- Force `project` into shape. Runs in stage one, before the file is looked
--- for -- these are the options that decide whether there is a fourth layer at
--- all, so they can only come from the three below it.
---@param cfg LspNvim.Config
---@return nil
local function normalize_project(cfg)
  normalize_switch(cfg, "project")
  local file = cfg.project.file
  if type(file) ~= "string" or file == "" then
    if file ~= nil then
      warn(
        ("project.file: expected a file name, using %q"):format(DEFAULTS.project.file),
        "project",
        "file"
      )
    end
    cfg.project.file = DEFAULTS.project.file
  end
end

---@internal
--- Take a list option from the layer that supplied it rather than from the
--- merged table.
---
--- `vim.tbl_deep_extend` merges two arrays index by index, which is wrong for
--- every list option here: `{ "lua_ls" }` over a six-entry default yields
--- `{ "lua_ls", <defaults 2..6> }`, so a config asking for one server silently
--- gets six. A list is a replacement, not an overlay -- there is no sensible
--- reading of "half the default markers".
---
--- The highest layer that says anything wins outright, including when what it
--- says is malformed: a stray `"servers": "lua_ls"` in a project file must not
--- be answered by the `setup()` list underneath it, or the typo would be
--- invisible. So a non-list stops the search and returns nil, which sends the
--- caller down its degrade-and-warn path.
---@param key string # Top-level key.
---@param field string|nil # Sub-field, for a list nested one level down.
---@return string[]|nil # nil when no layer supplied a usable list.
local function layer_list(key, field)
  for _, layer in ipairs(_layers) do
    local value = layer.data[key]
    if value ~= nil and field ~= nil then
      value = type(value) == "table" and value[field] or nil
    end
    if value ~= nil then
      if type(value) == "table" and vim.islist(value) then
        return value
      end
      return nil
    end
  end
  return nil
end

---@internal
--- Clean a list of names down to the non-empty strings in it.
---@param list any[]
---@param label string # Option path, for the warning.
---@param key string # Top-level key, for attribution.
---@param field string|nil # Sub-field, for attribution.
---@return string[]
local function clean_names(list, label, key, field)
  ---@type string[]
  local clean = {}
  for _, name in ipairs(list) do
    if type(name) == "string" and name ~= "" then
      clean[#clean + 1] = name
    else
      warn(("%s: ignoring non-string entry %s"):format(label, vim.inspect(name)), key, field)
    end
  end
  return clean
end

---@internal
--- Force `servers` into a non-empty array of strings. An empty or malformed
--- list would silently mean "no language server at all", which looks exactly
--- like a broken installation -- so it degrades to the default set and says so.
---
--- Read from the layers, not from the merged table, for the reason
--- `layer_list` gives: `servers = { "lua_ls" }` used to come out of the
--- deep-merge as `{ "lua_ls", "gopls", "marksman", ... }` -- every default from
--- index two on survived, so narrowing the server list did almost nothing and
--- said nothing about it.
---@param cfg LspNvim.Config
---@return nil
local function normalize_servers(cfg)
  local list = layer_list("servers") or cfg.servers
  if type(list) ~= "table" then
    warn("servers: expected a list of names, using defaults", "servers")
    cfg.servers = vim.deepcopy(DEFAULTS.servers)
    return
  end

  local clean = clean_names(list, "servers", "servers")

  if #clean == 0 then
    warn("servers: list is empty, using defaults", "servers")
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
---@return nil
local function normalize_workspace(cfg)
  for _, field in ipairs({ "markers", "containers" }) do
    local supplied = layer_list("workspace", field)
    local list = supplied or cfg.workspace[field]

    if type(list) ~= "table" then
      if list ~= nil then
        warn(
          ("workspace.%s: expected a list of names, using defaults"):format(field),
          "workspace",
          field
        )
      end
      cfg.workspace[field] = vim.deepcopy(DEFAULTS.workspace[field])
    else
      cfg.workspace[field] = clean_names(list, "workspace." .. field, "workspace", field)
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
      warn(("%s: expected a table, using defaults"):format(key), key)
    end
    cfg[key] = vim.deepcopy(DEFAULTS[key])
  end
end

---@internal
--- Resolve the profile name and record it. Unknown names degrade to
--- `"default"` rather than to no options at all -- a typo in a profile name
--- must not silently strip the plugin down.
---@param user_opts table
---@return LspNvim.Preset
local function resolve_preset(user_opts)
  local name = user_opts.preset
  if PRESETS[name] == nil then
    if name ~= nil then
      _warnings[#_warnings + 1] = ("preset: unknown value %q, using %q (known: %s)"):format(
        tostring(name),
        DEFAULTS.preset,
        "default, full, lean"
      )
    end
    name = DEFAULTS.preset
  end
  ---@cast name LspNvim.Preset
  return name
end

--- Merge the layers, normalize the result, and store it.
---@param user_opts? LspNvim.Config|table
---@return LspNvim.Config
function M.setup(user_opts)
  -- Cleared first, not after the type check below: appending a warning and
  -- then resetting the list discards it, which is exactly what used to happen
  -- to the "expected a table" warning -- the one case where the caller most
  -- needs to be told.
  _warnings = {}
  _layers = {}
  _sources = { preset = DEFAULTS.preset, project = nil }

  if type(user_opts) ~= "table" then
    if user_opts ~= nil then
      _warnings[#_warnings + 1] = "setup(): expected a table of options, ignoring"
    end
    user_opts = {}
  end

  local preset = resolve_preset(user_opts)
  _sources.preset = preset

  -- Highest precedence first, and only the layers that exist: with no preset
  -- and no project file this is one entry, and every warning reads exactly as
  -- it did before the feature landed.
  _layers = { { label = "setup()", data = user_opts } }
  if preset ~= "default" then
    _layers[#_layers + 1] = {
      label = ("preset %q"):format(preset),
      data = PRESETS[preset],
    }
  end

  -- Stage one: everything that decides whether there is a project layer.
  ---@diagnostic disable-next-line: missing-fields
  local cfg =
    vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), vim.deepcopy(PRESETS[preset]), user_opts)
  cfg.preset = preset
  normalize_project(cfg)

  -- Stage two: the project file, merged over everything above.
  local layer, project_warnings = project.read(cfg.project)
  vim.list_extend(_warnings, project_warnings)
  if layer ~= nil then
    table.insert(_layers, 1, { label = layer.label, data = layer.data })
    _sources.project = layer.path
    cfg = vim.tbl_deep_extend("force", cfg, vim.deepcopy(layer.data))
  end

  normalize_keymaps(cfg)
  normalize_switch(cfg, "usrcmds")
  normalize_switch(cfg, "which_key")
  normalize_servers(cfg)
  if cfg.rename.provider ~= "inc_rename" and cfg.rename.provider ~= "native" then
    if cfg.rename.provider ~= "auto" and cfg.rename.provider ~= nil then
      warn(
        ('rename.provider: unknown value %q, using "auto"'):format(tostring(cfg.rename.provider)),
        "rename",
        "provider"
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
  normalize_workspace(cfg)

  -- `labels` is the one option that is a function rather than data. Anything
  -- else there would blow up at the call site inside the source, far from the
  -- setup() call that caused it, so it is rejected here instead.
  if type(cfg.completion.personal_names) ~= "table" then
    cfg.completion.personal_names = vim.deepcopy(DEFAULTS.completion.personal_names)
  end
  local labels = cfg.completion.personal_names.labels
  if labels ~= nil and type(labels) ~= "function" then
    warn("completion.personal_names.labels: expected a function, ignoring", "completion")
    cfg.completion.personal_names.labels = nil
  end

  -- The override map is the one config value a typo turns into a silent
  -- no-op: a stray `filetypes = { "lua" }` (a list, not a map) would resolve
  -- every lookup to nil and simply never override anything.
  if type(cfg.inlay_hints.filetypes) ~= "table" then
    if cfg.inlay_hints.filetypes ~= nil then
      warn(
        "inlay_hints.filetypes: expected a filetype -> boolean map, ignoring",
        "inlay_hints",
        "filetypes"
      )
    end
    cfg.inlay_hints.filetypes = {}
  else
    for ft, value in pairs(cfg.inlay_hints.filetypes) do
      if type(ft) ~= "string" or type(value) ~= "boolean" then
        warn(
          ("inlay_hints.filetypes: ignoring entry %s = %s (want string = boolean)"):format(
            vim.inspect(ft),
            vim.inspect(value)
          ),
          "inlay_hints",
          "filetypes"
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
      warn(
        ("diagnostics.debounce_ms: expected a non-negative number, using %d"):format(
          DEFAULTS.diagnostics.debounce_ms
        ),
        "diagnostics",
        "debounce_ms"
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
      warn(
        ('diagnostics.ui: unknown value %q, using "auto"'):format(tostring(cfg.diagnostics.ui)),
        "diagnostics",
        "ui"
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

--- Which layers the active configuration was built from: the profile that was
--- applied, and the project file that was found, if any.
---
--- Reported by `:Lsp status` and `:checkhealth lsp` because an override you
--- cannot see is a debugging trap -- "why is `ts_ls` not attaching here" has a
--- one-line answer only when the file that switched it off is named.
---@return LspNvim.ConfigLayers
function M.layers()
  return vim.deepcopy(_sources)
end

--- Problems found while normalizing the last `setup()` call. Empty when the
--- configuration was clean, or when `setup()` has not run.
---@return string[]
function M.warnings()
  return _warnings
end

return M
