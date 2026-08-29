---@module 'lsp.integrations'
---@brief Registry for the third-party adapters (architecture layer 2).
---@description
--- One adapter per plugin, each owning that plugin's `require`. The core does
--- not reach into this layer and this layer does not reach into `pack/`:
--- the boundary sits there so the core stays
--- testable without a plugin manager and so swapping a completion engine is a
--- one-file change. `scripts/gen_map.lua` declares the rule as a layer check.
---
--- The dependency direction is what makes that work. Adapters do not get
--- called *by* the core -- they hand contributions to `lsp.init`, which is
--- neither layer, and it passes them into the core as plain functions. So
--- `core/attach.lua` no longer knows lazydev or NvChad exist; it takes hooks.
---
--- Every adapter call is wrapped. A broken adapter must not take the setup
--- with it -- that is blast-radius control, not optionality: a failure is
--- recorded and surfaced by `:checkhealth lsp`, never swallowed.
---
--- Order is meaningful for capabilities: NvChad first, then the completion
--- engine, then blink as a fallback merge. It is the order the single
--- `core/capabilities.lua` used before the split, kept deliberately, because
--- `tbl_deep_extend("force", …)` makes later contributors win.
---
---@see lsp.@types
---@see lsp.core.capabilities
---@see lsp.core.attach

local M = {}

--- Adapter modules, in invocation order.
---@type string[]
local ADAPTERS = {
  "nvchad",
  "cmp",
  "blink",
  "lazydev",
  "conform",
  "trouble",
  "inc_rename",
  "picker",
  "lspsaga",
  "lensline",
  "noice",
  "mason",
}

---@type table<string, LspNvim.Integration>
local _loaded = {}

---@type table<string, string> # adapter name -> failure reason
local _failed = {}

---@internal
--- Load every adapter module once. A module that does not load at all is
--- recorded rather than raised: the plugin it wraps is not why setup should
--- fail.
---@return nil
local function load_all()
  if next(_loaded) ~= nil or next(_failed) ~= nil then
    return
  end
  for _, name in ipairs(ADAPTERS) do
    local ok, mod = pcall(require, "lsp.integrations." .. name)
    if ok and type(mod) == "table" then
      _loaded[name] = mod
    else
      _failed[name] = tostring(mod)
    end
  end
end

--- Run every adapter's `setup`, in order.
---@param cfg LspNvim.Config
---@return string[] warnings
function M.setup(cfg)
  load_all()

  ---@type string[]
  local warnings = {}
  for name, reason in pairs(_failed) do
    warnings[#warnings + 1] = ("integration %s failed to load: %s"):format(name, reason)
  end

  for _, name in ipairs(ADAPTERS) do
    local adapter = _loaded[name]
    if adapter ~= nil and type(adapter.setup) == "function" then
      local ok, err = pcall(adapter.setup, cfg)
      if not ok then
        warnings[#warnings + 1] = ("integration %s: setup failed: %s"):format(name, tostring(err))
      end
    end
  end

  return warnings
end

--- Capability contributors, in order, from the adapters that provide one.
---
--- Handed to `core/capabilities.get()` by `lsp.init`, so the core merges them
--- without knowing which plugin any of them came from.
---@return LspCaps.Contributor[]
function M.capability_contributors()
  load_all()

  ---@type LspCaps.Contributor[]
  local contributors = {}
  for _, name in ipairs(ADAPTERS) do
    local adapter = _loaded[name]
    if adapter ~= nil and type(adapter.capabilities) == "function" then
      contributors[#contributors + 1] = adapter.capabilities
    end
  end
  return contributors
end

--- Attach hooks, in order, from the adapters that provide one.
---@return { on_attach: fun(client: table, bufnr: integer)[], on_init: fun(client: table)[] }
function M.attach_hooks()
  load_all()

  ---@type function[]
  local on_attach = {}
  ---@type function[]
  local on_init = {}
  for _, name in ipairs(ADAPTERS) do
    local adapter = _loaded[name]
    if adapter ~= nil then
      if type(adapter.on_attach) == "function" then
        on_attach[#on_attach + 1] = adapter.on_attach
      end
      if type(adapter.on_init) == "function" then
        on_init[#on_init + 1] = adapter.on_init
      end
    end
  end
  return { on_attach = on_attach, on_init = on_init }
end

--- One row per adapter for `:checkhealth lsp`.
---
--- Replaces the hardcoded plugin list health.lua used to carry: a list in two
--- places is a list that disagrees with itself eventually.
---@return LspNvim.IntegrationStatus[]
function M.report()
  load_all()

  ---@type LspNvim.IntegrationStatus[]
  local rows = {}
  for _, name in ipairs(ADAPTERS) do
    local adapter = _loaded[name]
    if adapter == nil then
      rows[#rows + 1] = {
        name = name,
        plugin = name,
        available = false,
        hard = false,
        note = "adapter module failed to load: " .. tostring(_failed[name]),
      }
    else
      local ok, available = pcall(adapter.available)
      rows[#rows + 1] = {
        name = name,
        plugin = adapter.plugin or name,
        available = ok and available == true,
        hard = adapter.hard == true,
        note = adapter.note or "",
      }
    end
  end
  return rows
end

return M
