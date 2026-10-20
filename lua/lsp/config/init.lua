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
local unknown = require("lsp.config.unknown")

local M = {}

--- The config object (`lib.lua.config.new`): the three layers under `DEFAULTS`, in rank order.
--- A preset is ours and the project file is read in a second step, but the merge itself, the
--- aliasing-free copy of `DEFAULTS` and the "every `setup()` starts fresh" rule are the shared
--- ones. Declared here and created below `normalize_all`, which it runs as its `resolve` hook.
---@type Lib.Config.Instance
local store

--- Problems that are not the normalization's: an unknown profile, a `setup()` that was not a
--- table, what the project file reader refused, the unknown-key scan of each layer a person wrote.
--- The normalization's own are `store.issues()`.
---@type string[]
local _extra = {}

--- The profile `setup()` resolved, read by the normalization (`cfg.preset` records it).
---@type string
local _preset = DEFAULTS.preset

--- How a warning names the layer a value came from: `setup()`, `preset "lean"`, the project file.
---@type table<string, string>
local _labels = {}

---@type LspNvim.ConfigLayers
local _sources = { preset = "default", project = nil }

--- The issue list of the normalization in progress (the one `resolve` was handed).
---@type string[]
local _found = {}

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
  local src = nil
  if key ~= nil then
    src = _labels[store.source(field ~= nil and (key .. "." .. field) or key) or ""]
  end
  _found[#_found + 1] = src ~= nil and ("%s (from %s)"):format(msg, src) or msg
end

---@internal
--- Force `keymaps` into a shape `bindings/keymaps.lua` can iterate without
--- re-checking: a known preset name and a table of overrides.
---@param cfg LspNvim.Config
---@return nil
local function normalize_keymaps(cfg)
  local km = cfg.keymaps
  -- `keymaps = false` is the conventional "no keymaps at all" spelling across
  -- the plugins here; it means `keymaps = { enable = false }`. `true` is the
  -- defaults. Neither is a mistake worth a warning.
  if type(km) == "boolean" then
    -- the shared lib.nvim helper owns the shape: false -> { enable = false },
    -- true -> {} (REL-20); the defaults fill the rest.
    local group = require("lib.nvim.normalize").normalize_switch_group(km) or {}
    cfg.keymaps = vim.tbl_extend("force", vim.deepcopy(DEFAULTS.keymaps), group)
    return
  end
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
    -- Indexing DEFAULTS with a variable yields the union of every field's
    -- type. `---@type table` on the local moves the mismatch onto the
    -- assignment instead of removing it; the claim belongs on the value.
    local fallback = DEFAULTS[key]
    ---@cast fallback table
    cfg[key] = vim.deepcopy(fallback)
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
--- Force `integrations` into `{ ui_menu = boolean }`.
---@param cfg LspNvim.Config
---@return nil
local function normalize_integrations(cfg)
  local sub = cfg.integrations
  if type(sub) ~= "table" then
    if sub ~= nil then
      warn("integrations: expected a table, using defaults", "integrations")
    end
    cfg.integrations = vim.deepcopy(DEFAULTS.integrations)
    return
  end
  if type(sub.ui_menu) ~= "boolean" then
    if sub.ui_menu ~= nil then
      warn("integrations.ui_menu: expected a boolean, using the default", "integrations", "ui_menu")
    end
    sub.ui_menu = DEFAULTS.integrations.ui_menu
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
    -- A control character in a name never resolves to a module, and a name is
    -- printed verbatim by `:Lsp status` and the registry warnings.
    if type(name) == "string" and name ~= "" and not name:find("%c") then
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
--- A list is a replacement, not an overlay -- there is no sensible reading of
--- "half the default markers": the config object's merge hands the highest
--- layer's list over whole, where `vim.tbl_deep_extend` turned
--- `servers = { "lua_ls" }` into `{ "lua_ls", "gopls", "marksman", ... }`
--- (every default from index two on survived).
---@param cfg LspNvim.Config
---@return nil
local function normalize_servers(cfg)
  local list = cfg.servers
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
    local list = cfg.workspace[field]

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
    -- Indexing DEFAULTS with a variable yields the union of every field's
    -- type. `---@type table` on the local moves the mismatch onto the
    -- assignment instead of removing it; the claim belongs on the value.
    local fallback = DEFAULTS[key]
    ---@cast fallback table
    cfg[key] = vim.deepcopy(fallback)
  end
end

---@internal
--- Force a numeric sub-option back to its default when it is not a usable
--- number, and warn with the layer that supplied it.
---
--- Three options reached their consumers unchecked -- `lightbulb.priority`,
--- `formatter.timeout_ms` and `lspdoctor.list_limit`. Measured, each survived
--- `setup()` intact with **zero** warnings, while every option that does go
--- through a check here degrades *and* names its layer. Nothing crashed,
--- because the consumers defend themselves: `core/lightbulb.lua` tests
--- `type(...) == "number" and ... > 0` and falls back to 20, and
--- `lspdoctor/health.lua` reads `Opts.list_limit or 10`. But a value the config
--- reports and the code ignores is worse than either alone -- `:Lsp status` and
--- `:checkhealth lsp` showed `priority "nope"` while the lightbulb ran at 20,
--- so the one place a user looks to find out what is in effect was the one
--- place that disagreed with it. Raw, the values do raise:
--- `nvim_buf_set_extmark` answers `Invalid 'priority': Expected Lua number` and
--- `vim.list_slice(t, 1, "big")` answers `'for' limit must be a number`.
---
--- The three numeric options that already had a check keep their hand-written
--- blocks below: their wording is asserted by specs, and converting them is a
--- tidy-up, not a fix. This produces the same two message shapes so the family
--- still reads as one.
---@param cfg LspNvim.Config
---@param key string # Top-level key, e.g. `"lightbulb"`.
---@param field string # Sub-field, e.g. `"priority"`.
---@param allow_zero boolean # Whether 0 is a legitimate value.
---@return nil
local function normalize_number(cfg, key, field, allow_zero)
  local opts = cfg[key]
  if type(opts) ~= "table" then
    return -- `normalize_table` already put a default here and warned.
  end

  local value = opts[field]
  local ok = type(value) == "number" and (allow_zero and value >= 0 or value > 0)
  if ok then
    opts[field] = math.floor(value)
    return
  end

  -- Same trap `normalize_table` documents: indexing DEFAULTS with a variable
  -- yields the union of every field's type, so the claim goes on the value.
  local defaults = DEFAULTS[key]
  ---@cast defaults table
  local fallback = defaults[field]
  -- nil is the option being absent, which is what a default is for -- only a
  -- value the user actually supplied is worth a warning.
  if value ~= nil then
    warn(
      ("%s.%s: expected a %s number, using %d"):format(
        key,
        field,
        allow_zero and "non-negative" or "positive",
        fallback
      ),
      key,
      field
    )
  end
  opts[field] = fallback
end

---@internal
--- Force a `filetype -> boolean` override map into shape.
---
--- This map is the one config value a typo turns into a silent no-op: a stray
--- `filetypes = { "lua" }` (a list, not a map) would resolve every lookup to
--- nil and simply never override anything. Shared by `inlay_hints` and
--- `lightbulb`, which is not an accident -- the two features resolve their
--- overrides by the same rule, so they have to reject the same mistakes.
---@param cfg LspNvim.Config
---@param key string # The option table holding the map.
---@return nil
local function normalize_filetype_map(cfg, key)
  local opts = cfg[key]
  if type(opts.filetypes) ~= "table" then
    if opts.filetypes ~= nil then
      warn(
        ("%s.filetypes: expected a filetype -> boolean map, ignoring"):format(key),
        key,
        "filetypes"
      )
    end
    opts.filetypes = {}
    return
  end
  for ft, value in pairs(opts.filetypes) do
    if type(ft) ~= "string" or type(value) ~= "boolean" then
      warn(
        ("%s.filetypes: ignoring entry %s = %s (want string = boolean)"):format(
          key,
          vim.inspect(ft),
          vim.inspect(value)
        ),
        key,
        "filetypes"
      )
      opts.filetypes[ft] = nil
    end
  end
end

---@internal
--- Force a boolean sub-option back to its default when it is not one, and warn
--- when the value was supplied rather than absent.
---@param cfg LspNvim.Config
---@param key string # Top-level key, e.g. `"winbar"`.
---@param field string # Sub-field, e.g. `"chips"`.
---@return nil
local function normalize_boolean(cfg, key, field)
  local opts = cfg[key]
  if type(opts) ~= "table" or type(opts[field]) == "boolean" then
    return -- `normalize_table` already put a default here and warned.
  end
  local defaults = DEFAULTS[key]
  ---@cast defaults table
  if opts[field] ~= nil then
    warn(
      ("%s.%s: expected a boolean, using %s"):format(key, field, tostring(defaults[field])),
      key,
      field
    )
  end
  opts[field] = defaults[field]
end

---@internal
--- Force a string sub-option back to its default when it is not a string.
---@param cfg LspNvim.Config
---@param key string
---@param field string
---@return nil
local function normalize_string(cfg, key, field)
  local opts = cfg[key]
  if type(opts) ~= "table" or type(opts[field]) == "string" then
    return
  end
  local defaults = DEFAULTS[key]
  ---@cast defaults table
  if opts[field] ~= nil then
    warn(
      ("%s.%s: expected a string, using %q"):format(key, field, tostring(defaults[field])),
      key,
      field
    )
  end
  opts[field] = defaults[field]
end

---@internal
--- Force a positive-number sub-option back to its default. Unlike
--- `normalize_number` it does not floor: `peek.width = 0.7` is a fraction.
---@param cfg LspNvim.Config
---@param key string
---@param field string
---@return nil
local function normalize_positive(cfg, key, field)
  local opts = cfg[key]
  if type(opts) ~= "table" then
    return
  end
  local value = opts[field]
  if type(value) == "number" and value > 0 then
    return
  end
  local defaults = DEFAULTS[key]
  ---@cast defaults table
  if value ~= nil then
    warn(
      ("%s.%s: expected a positive number, using %s"):format(key, field, tostring(defaults[field])),
      key,
      field
    )
  end
  opts[field] = defaults[field]
end

---@internal
--- Drop the entries of a `name -> value` map that `valid` refuses, warning
--- for each. A map is used instead of a list for every such option because
--- `vim.tbl_deep_extend` merges lists index by index.
---@param cfg LspNvim.Config
---@param key string
---@param field string
---@param want string # What a valid value is, for the message.
---@param valid fun(name: any, value: any): boolean
---@return nil
local function normalize_map(cfg, key, field, want, valid)
  local opts = cfg[key]
  if type(opts) ~= "table" then
    return
  end
  local map = opts[field]
  if type(map) ~= "table" then
    if map ~= nil then
      warn(("%s.%s: expected a %s map, ignoring"):format(key, field, want), key, field)
    end
    opts[field] = {}
    return
  end
  for name, value in pairs(map) do
    if not valid(name, value) then
      warn(
        ("%s.%s: ignoring entry %s = %s (want %s)"):format(
          key,
          field,
          vim.inspect(name),
          vim.inspect(value),
          want
        ),
        key,
        field
      )
      map[name] = nil
    end
  end
end

---@internal
--- The `winbar`, `peek`, `implement`, `code_actions` and `finder` options.
--- Split out of `M.setup` only because it is a long, flat list of independent
--- checks that share nothing with the rest of it.
---@param cfg LspNvim.Config
---@return nil
local function normalize_ui_features(cfg)
  -- winbar
  normalize_filetype_map(cfg, "winbar")
  for _, field in ipairs({ "enable", "show_file", "chips" }) do
    normalize_boolean(cfg, "winbar", field)
  end
  normalize_string(cfg, "winbar", "separator")
  normalize_number(cfg, "winbar", "folder_level", true)
  normalize_number(cfg, "winbar", "debounce_ms", true)
  normalize_number(cfg, "winbar", "refresh_ms", true)
  normalize_map(cfg, "winbar", "max_symbols", "filetype -> count", function(name, value)
    return type(name) == "string" and (value == false or (type(value) == "number" and value >= 0))
  end)

  -- peek
  normalize_positive(cfg, "peek", "width")
  normalize_positive(cfg, "peek", "height")
  normalize_boolean(cfg, "peek", "beacon")
  if type(cfg.peek.border) ~= "string" and type(cfg.peek.border) ~= "table" then
    if cfg.peek.border ~= nil then
      warn(
        ("peek.border: expected a border name or a list, using %q"):format(DEFAULTS.peek.border),
        "peek",
        "border"
      )
    end
    cfg.peek.border = DEFAULTS.peek.border
  end
  local peek_actions = { close = true, edit = true, vsplit = true, split = true, tabedit = true }
  normalize_map(cfg, "peek", "keys", "action -> key", function(name, value)
    return peek_actions[name] == true
      and (value == false or (type(value) == "string" and value ~= ""))
  end)

  -- implement
  normalize_filetype_map(cfg, "implement")
  normalize_boolean(cfg, "implement", "enable")
  normalize_string(cfg, "implement", "text")
  -- A string is not yet a format: `text` goes through `string.format` with the
  -- count on every answer, and one that cannot print a number -- no `%d`, a
  -- lone `%` -- would fail in a request handler each time and draw nothing.
  local printed_ok, printed = pcall(string.format, cfg.implement.text, 12345)
  if not (printed_ok and printed:find("12345", 1, true)) then
    warn(
      ("implement.text: %s cannot print a count (it needs a %%d, and %%%% for a percent sign), using %q"):format(
        vim.inspect(cfg.implement.text),
        DEFAULTS.implement.text
      ),
      "implement",
      "text"
    )
    cfg.implement.text = DEFAULTS.implement.text
  end
  normalize_number(cfg, "implement", "debounce_ms", true)
  normalize_number(cfg, "implement", "max_requests", false)
  normalize_map(cfg, "implement", "kinds", "kind name -> boolean", function(name, value)
    return type(name) == "string" and type(value) == "boolean"
  end)

  -- code_actions
  normalize_boolean(cfg, "code_actions", "gitsigns")
  local picker = cfg.code_actions.picker
  if picker ~= "auto" and picker ~= "fzf-lua" and picker ~= "native" then
    if picker ~= nil then
      warn(
        ('code_actions.picker: unknown value %q, using "auto"'):format(tostring(picker)),
        "code_actions",
        "picker"
      )
    end
    cfg.code_actions.picker = DEFAULTS.code_actions.picker
  end

  -- finder
  for _, field in ipairs({
    "references",
    "implementations",
    "definitions",
    "declarations",
    "typedefs",
  }) do
    normalize_boolean(cfg, "finder", field)
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
      _extra[#_extra + 1] = ("preset: unknown value %q, using %q (known: %s)"):format(
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

---@internal
--- Everything the layers cannot say by type: force each option into a shape the consumers can
--- use without re-checking, writing a warning (named by the layer it came from) for each value
--- it pulls back. Runs as the `resolve` hook, so on every change of a layer, over a fresh merge.
---@param cfg LspNvim.Config
---@return nil
local function normalize_all(cfg)
  cfg.preset = _preset
  normalize_project(cfg)

  normalize_keymaps(cfg)
  normalize_switch(cfg, "usrcmds")
  normalize_switch(cfg, "which_key")
  -- `menu` was the one top-level option nothing normalized. Every other key
  -- answered `menu = 42` with "expected a table, using defaults"; this one
  -- passed the number through with no warning at all, and
  -- `integrations/menu.lua` then raised on `mcfg.enable` -- a config error
  -- surfacing as a stack trace in an unrelated module, which is the shape this
  -- whole normalization step exists to prevent.
  normalize_switch(cfg, "menu")
  normalize_integrations(cfg)
  normalize_servers(cfg)
  for _, key in ipairs({
    "rename",
    "diagnostics",
    "formatter",
    "inlay_hints",
    "lightbulb",
    "winbar",
    "peek",
    "implement",
    "code_actions",
    "finder",
    "auto_restart",
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

  -- After the loop, because each of these reads a field off a table the loop
  -- is what guarantees is a table. See `normalize_number` for what reaching
  -- their consumers unchecked cost.
  normalize_number(cfg, "lightbulb", "priority", false)
  normalize_number(cfg, "formatter", "timeout_ms", false)
  normalize_number(cfg, "lspdoctor", "list_limit", false)
  -- These three came from driving the check off `DEFAULTS` instead of off a
  -- list written by hand. The hand-written list had the first three; the
  -- derived one found six. That is the same miss as `menu` in the switch audit,
  -- and the reason `config_spec.lua` asserts the set rather than spelling it.
  normalize_number(cfg, "lspdoctor", "probe_timeout", false)
  normalize_number(cfg, "lspdoctor", "scratch_threshold", false)
  normalize_number(cfg, "lspdoctor", "semantic_tokens_timeout", false)

  -- After the loop above, not before it. `rename` was the one top-level option
  -- of seventeen that raised instead of degrading: `rename = false` reached
  -- `cfg.rename.provider` while `cfg.rename` was still a boolean, so
  -- `config.setup()` -- and with it plugin startup -- died on
  -- "attempt to index field 'rename' (a boolean value)". Every other key
  -- answered with "expected a table, using defaults", which is the contract
  -- this module states: a typo should degrade the feature, not break startup.
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

  normalize_filetype_map(cfg, "inlay_hints")
  if type(cfg.inlay_hints.enable) ~= "boolean" then
    cfg.inlay_hints.enable = DEFAULTS.inlay_hints.enable
  end

  if type(cfg.auto_restart.enable) ~= "boolean" then
    cfg.auto_restart.enable = DEFAULTS.auto_restart.enable
  end
  -- Every one of these ends up in a `uv` timer or a comparison against a
  -- counter. A zero or a negative would either fire instantly forever or make
  -- the give-up test unreachable, and both fail far from the setup() call.
  for _, key in ipairs({
    "max_attempts",
    "initial_delay_ms",
    "max_delay_ms",
    "reset_after_ms",
  }) do
    local value = cfg.auto_restart[key]
    if type(value) ~= "number" or value <= 0 then
      if value ~= nil then
        warn(
          ("auto_restart.%s: expected a positive number, using %d"):format(
            key,
            DEFAULTS.auto_restart[key]
          ),
          "auto_restart",
          key
        )
      end
      cfg.auto_restart[key] = DEFAULTS.auto_restart[key]
    else
      cfg.auto_restart[key] = math.floor(value)
    end
  end
  -- A cap below the first delay would make the backoff shrink instead of grow.
  if cfg.auto_restart.max_delay_ms < cfg.auto_restart.initial_delay_ms then
    warn(
      ("auto_restart.max_delay_ms (%d) is below initial_delay_ms (%d), raising it"):format(
        cfg.auto_restart.max_delay_ms,
        cfg.auto_restart.initial_delay_ms
      ),
      "auto_restart",
      "max_delay_ms"
    )
    cfg.auto_restart.max_delay_ms = cfg.auto_restart.initial_delay_ms
  end

  normalize_filetype_map(cfg, "lightbulb")
  if type(cfg.lightbulb.enable) ~= "boolean" then
    cfg.lightbulb.enable = DEFAULTS.lightbulb.enable
  end
  -- A non-list here would leave `kinds` iterating nothing, which reads as
  -- "unfiltered" -- the opposite of what someone writing an allowlist means.
  if type(cfg.lightbulb.kinds) ~= "table" or not vim.islist(cfg.lightbulb.kinds) then
    if cfg.lightbulb.kinds ~= nil then
      warn(
        "lightbulb.kinds: expected a list of CodeActionKind prefixes, using defaults",
        "lightbulb",
        "kinds"
      )
    end
    cfg.lightbulb.kinds = vim.deepcopy(DEFAULTS.lightbulb.kinds)
  end
  if cfg.lightbulb.render ~= "sign" and cfg.lightbulb.render ~= "virtual_text" then
    if cfg.lightbulb.render ~= nil then
      warn(
        ('lightbulb.render: unknown value %q, using "sign"'):format(tostring(cfg.lightbulb.render)),
        "lightbulb",
        "render"
      )
    end
    cfg.lightbulb.render = DEFAULTS.lightbulb.render
  end
  -- Same reasoning as `diagnostics.debounce_ms`: a bad window reaches
  -- `uv.timer:start()` and raises there, on every cursor movement, far from
  -- the setup() call that caused it.
  if type(cfg.lightbulb.debounce_ms) ~= "number" or cfg.lightbulb.debounce_ms < 0 then
    if cfg.lightbulb.debounce_ms ~= nil then
      warn(
        ("lightbulb.debounce_ms: expected a non-negative number, using %d"):format(
          DEFAULTS.lightbulb.debounce_ms
        ),
        "lightbulb",
        "debounce_ms"
      )
    end
    cfg.lightbulb.debounce_ms = DEFAULTS.lightbulb.debounce_ms
  else
    cfg.lightbulb.debounce_ms = math.floor(cfg.lightbulb.debounce_ms)
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

  normalize_ui_features(cfg)

  normalize_boolean(cfg, "languages", "env_links")

  -- `project folder -> boolean`. A non-string key or non-boolean value is
  -- dropped here with the layer named, rather than reaching the override store
  -- where it would silently match nothing.
  normalize_map(
    cfg,
    "attach",
    "workspace_diagnostics_projects",
    "project folder -> boolean",
    function(name, value)
      return type(name) == "string" and name ~= "" and type(value) == "boolean"
    end
  )
end

---@param opts table
---@return table
local function without_unknown_keys(opts)
  for key in pairs(opts) do
    if DEFAULTS[key] == nil then
      opts[key] = nil
    end
  end
  return opts
end

--- To the schema the config object infers from `DEFAULTS`, every option is open: the typed
--- checks are `normalize_all` above (they degrade to the default and name the layer), and an
--- unknown key is reported by `unknown.scan` in `setup()` with its did-you-mean hint, then
--- left out here.
local ANY = "boolean|number|string|table|function"
---@type table<string, string>
local SCHEMA = {}
for key in pairs(DEFAULTS) do
  SCHEMA[key] = ANY
end

store = require("lib.lua.config").new(DEFAULTS, {
  name = "lsp",
  schema = SCHEMA,
  layers = { "preset", "setup", "project" },
  normalize = without_unknown_keys,
  resolve = function(cfg, found)
    _found = found
    normalize_all(cfg)
  end,
})

--- Merge the layers, normalize the result, and store it.
---@param user_opts? LspNvim.Opts|table
---@return LspNvim.Config
function M.setup(user_opts)
  -- Cleared first, not after the type check below: appending a warning and
  -- then resetting the list discards it, which is exactly what used to happen
  -- to the "expected a table" warning -- the one case where the caller most
  -- needs to be told.
  _extra = {}
  _sources = { preset = DEFAULTS.preset, project = nil }
  _labels = { setup = "setup()" }

  if type(user_opts) ~= "table" then
    if user_opts ~= nil then
      _extra[#_extra + 1] = "setup(): expected a table of options, ignoring"
    end
    user_opts = {}
  end

  _preset = resolve_preset(user_opts)
  _sources.preset = _preset
  if _preset ~= "default" then
    _labels.preset = ("preset %q"):format(_preset)
  end

  -- Stage one: everything that decides whether there is a project layer.
  store.layer("project", nil)
  store.layer("preset", _preset ~= "default" and PRESETS[_preset] or nil)
  store.layer("setup", user_opts)

  -- Stage two: the project file, merged over everything above.
  local layer, project_warnings = project.read(store.get("project"))
  vim.list_extend(_extra, project_warnings)
  if layer ~= nil then
    _sources.project = layer.path
    _labels.project = layer.label
  end

  -- A misspelled option would otherwise sit unnoticed next to the real one. Only the layers a
  -- person wrote are checked: a preset is ours, and `DEFAULTS` is the reference.
  if layer ~= nil then
    vim.list_extend(_extra, unknown.messages(unknown.scan(layer.data, DEFAULTS), layer.label))
  end
  vim.list_extend(_extra, unknown.messages(unknown.scan(user_opts, DEFAULTS), "setup()"))

  if layer ~= nil then
    store.layer("project", layer.data)
  end
  return store.get()
end

--- The active configuration. Falls back to a copy of the defaults when
--- `setup()` has not run, so `:checkhealth lsp` works on a bare install.
---@return LspNvim.Config
function M.get()
  return store.get()
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
---
--- The one choke point for warning text. Warnings echo what a layer supplied
--- (key names, values, paths), and the project layer can come from a cloned
--- repository: a newline in one breaks the scratch buffer `:Lsp status`
--- writes into, an escape sequence reaches the terminal through
--- `:checkhealth`, and an unbounded value floods both. Sanitizing here rather
--- than at each `warn()` call means a warning added later is covered too.
---@return string[]
function M.warnings()
  local out = {}
  for _, w in ipairs(_extra) do
    out[#out + 1] = unknown.sanitize(w, unknown.MAX_WARNING)
  end
  for _, w in ipairs(store.issues()) do
    out[#out + 1] = unknown.sanitize(w, unknown.MAX_WARNING)
  end
  return out
end

return M
