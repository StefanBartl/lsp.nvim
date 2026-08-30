---@module 'lsp'
---@brief Public entry point for lsp.nvim.
---@description
--- Umbrella plugin for the whole LSP setup: server registry, attach handling,
--- capabilities, the formatter and workspace-diagnostics toggles, diagnostics,
--- the per-language and per-server modules, the extra tools, and `:LspDoctor`.
---
--- `setup()` does two things in order: it resolves the configuration and binds
--- what the plugin claims (keymaps, `:Lsp`, autocommands), then it bootstraps
--- the LSP core. The bootstrap is deliberately the same shape it had in the
--- config it came from -- handlers, diagnostics, capabilities, attach,
--- formatter, commands, languages, registry, tools -- so this reads as a move,
--- not a rewrite. What changed is where its inputs come from: options instead
--- of hardcoded lists and host modules.
---
--- Every step is wrapped: one broken server module, tool or optional plugin
--- must not take the rest of the setup with it. That is blast-radius control,
--- not optionality -- a step that fails says so through `status().warnings` and
--- `:checkhealth lsp`.
---
--- The module root is `lsp` on purpose (roadmap section 5): Neovim occupies
--- only `vim.lsp` and nvim-lspconfig only `lspconfig`, so `require("lsp.…")`
--- paths from the config keep resolving. A config that still ships its own
--- `lua/lsp/**` shadows this plugin on the runtimepath -- the two swap, they do
--- not coexist.
---
--- lib.nvim is a hard dependency (LUA-01): bare `require`, no fallback.
---
--- Example: >lua
---   require("lsp").setup()
---   require("lsp").setup({
---     servers = { "lua_ls", "gopls" },
---     formatter = { on_save = true },
---   })
--- <
---
---@see lsp.config
---@see lsp.bindings
---@see lsp.core.registry
---@see lsp.health

local config = require("lsp.config")
local integrations = require("lsp.integrations")
local notify = require("lib.nvim.notify").create("[lsp.nvim]")

local M = {}

---@type boolean
local _initialized = false

---@type LspNvim.KeymapSpec[]
local _keymaps = {}

---@type boolean
local _usrcmd = false

---@type string[]
local _servers = {}

---@type string[]
local _warnings = {}

---@internal
--- Run one bootstrap step, recording a failure instead of propagating it.
---@param label string # What the step is, for the warning text.
---@param fn fun(): nil
---@return boolean ok
local function step(label, fn)
  local ok, err = pcall(fn)
  if not ok then
    _warnings[#_warnings + 1] = ("%s failed: %s"):format(label, tostring(err))
  end
  return ok
end

---@internal
--- Client capabilities: whatever `core/capabilities` resolves (cmp / blink /
--- NvChad merged in), falling back to Neovim's own when that module cannot be
--- loaded at all. Its own warnings are surfaced immediately -- a silently
--- degraded capability set is the failure mode that costs hours.
---@return table caps
local function build_capabilities()
  local ok, mod = pcall(require, "lsp.core.capabilities")
  if ok and mod and type(mod.get) == "function" then
    local caps, warnings = mod.get(integrations.capability_contributors())
    for _, w in ipairs(warnings or {}) do
      _warnings[#_warnings + 1] = tostring(w.msg)
      if w.level == "error" then
        notify.error(w.msg)
      else
        notify.warn(w.msg)
      end
    end
    return caps
  end

  _warnings[#_warnings + 1] = "capabilities: using Neovim's fallback (no cmp/blink)"
  notify.warn("Using fallback capabilities (no cmp/blink)")
  return vim.lsp.protocol.make_client_capabilities()
end

---@internal
--- The `on_attach`/`on_init` pair every server is set up with.
---@param cfg LspNvim.Config
---@return { on_attach: function, on_init: function }
local function build_attach(cfg)
  local ok, mod = pcall(require, "lsp.core.attach")
  if ok and mod and type(mod.build) == "function" then
    return mod.build({
      use_workspace_diagnostics = cfg.attach.use_workspace_diagnostics,
      hooks = integrations.attach_hooks(),
    })
  end

  _warnings[#_warnings + 1] = "attach: using minimal handlers"
  notify.warn("Using minimal attach handlers")
  return {
    on_attach = function(client, bufnr)
      if
        client
        and client.server_capabilities
        and client.server_capabilities.completionProvider
      then
        vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"
      end
    end,
    on_init = function()
      return true
    end,
  }
end

---@internal
--- The formatter API, or an inert stand-in with the same shape so callers
--- (commands, keymaps, `vim.g._formatter_api`) never have to nil-check.
---@param cfg LspNvim.Config
---@return table
local function build_formatter(cfg)
  local ok, mod = pcall(require, "lsp.formatter")
  if ok and mod and type(mod.build) == "function" then
    return mod.build({
      format_on_save = cfg.formatter.on_save,
      timeout_ms = cfg.formatter.timeout_ms,
    })
  end

  _warnings[#_warnings + 1] = "formatter: module unavailable, formatting disabled"
  return {
    format = function()
      return false
    end,
    enable = function()
      return false
    end,
    disable = function()
      return true
    end,
    toggle = function()
      return false
    end,
    is_enabled = function()
      return false
    end,
  }
end

---@internal
--- Register and enable the configured servers.
---@param cfg LspNvim.Config
---@param shared table # capabilities / on_attach / on_init / formatter
---@return string[] enabled
local function setup_servers(cfg, shared)
  local ok, registry = pcall(require, "lsp.core.registry")
  if not (ok and registry and type(registry.setup_all) == "function") then
    _warnings[#_warnings + 1] = "registry missing; no server was set up"
    notify.warn("LSP registry missing; skipping server setup")
    return {}
  end

  local names = registry.setup_all(shared, cfg.servers)
  if type(names) ~= "table" or #names == 0 then
    _warnings[#_warnings + 1] = "no server was configured"
    notify.warn("No LSP servers configured!")
    return {}
  end

  for _, name in ipairs(names) do
    pcall(vim.lsp.enable, name)
  end
  return names
end

---@internal
--- The extra tools, each behind its own switch.
---@param cfg LspNvim.Config
---@return nil
local function setup_tools(cfg)
  local tools = cfg.tools

  if tools.eslint_prettier.enable then
    step("tools.eslint_prettier", function()
      require("lsp.tools.eslint_prettier").setup({
        filetypes = tools.eslint_prettier.filetypes,
        enable_on_setup = true,
      })
    end)
  end
  if tools.lsp_signature.enable then
    step("tools.lsp_signature", function()
      require("lsp.tools.lsp_signature").setup()
    end)
  end
  if tools.ts_type_lookup.enable then
    step("tools.ts_type_lookup", function()
      require("lsp.tools.ts_type_lookup").setup()
    end)
  end
  if tools.deprecated_help.enable then
    step("tools.deprecated_help", function()
      require("lsp.tools.deprecated_help").setup()
    end)
  end
end

---@internal
--- The LSP core, in the order the pieces depend on each other: handlers and
--- diagnostics first, then the inputs every server needs, then the commands
--- that operate on them, then the servers themselves, then the extras.
---@param cfg LspNvim.Config
---@return boolean ok
local function bootstrap(cfg)
  -- Before anything reads a contributor or an attach hook.
  for _, w in ipairs(integrations.setup(cfg)) do
    _warnings[#_warnings + 1] = w
  end

  step("handlers", function()
    require("lsp.core.handlers").setup({ debounce_ms = cfg.diagnostics.debounce_ms })
  end)
  step("core diagnostics", function()
    require("lsp.core.diagnostics").setup()
  end)
  -- Before the servers, so the LspAttach handler is in place for the first
  -- attach rather than one buffer late.
  step("inlay hints", function()
    require("lsp.core.inlay_hints").setup(cfg.inlay_hints)
  end)

  local caps = build_capabilities()
  local attach = build_attach(cfg)
  local formatter = build_formatter(cfg)

  step("conform", function()
    require("lsp.formatter.conform").setup()
  end)

  -- Read by the format keymaps and commands. A global because the keymaps are
  -- registered by the host today; it goes away with roadmap phase 3, when the
  -- keymap catalogue can close over the formatter directly.
  vim.g._formatter_api = formatter

  -- The flat command family. `:Lsp` reaches the same functions through its own
  -- routes, so these are aliases; `usrcmds.legacy_aliases = false` drops them.
  -- `lsp.usercmds.attach` is told rather than skipped, because it also owns
  -- `:LspMdHints`, which is not an alias.
  local legacy = cfg.usrcmds.legacy_aliases
  if legacy then
    step("formatter commands", function()
      require("lsp.usercmds.formatter").attach(formatter)
    end)
    step("workspace-diagnostics commands", function()
      require("lsp.usercmds.workspace_diagnostics").attach()
    end)
  end
  step("lsp commands", function()
    require("lsp.usercmds").attach(legacy)
  end)

  if cfg.completion.personal_names.enable then
    -- Engine-neutral on purpose: `lsp.completion.register` decides who gets the
    -- source, so this runs the same under nvim-cmp and blink.
    step("completion sources", function()
      require("lsp.completion.personal_names").setup({
        labels = cfg.completion.personal_names.labels,
      })
    end)
  end

  if cfg.languages.enable then
    -- Before the servers: language modules install filetype-specific
    -- quality-of-life setup that the server configs then build on.
    step("languages", function()
      require("lsp.languages").enable_all()
    end)
    vim.filetype.add({ extension = { astro = "astro" } })
  end

  _servers = setup_servers(cfg, {
    capabilities = caps,
    on_attach = attach.on_attach,
    on_init = attach.on_init,
    formatter = formatter,
  })

  -- After the servers are enabled, so a server config cannot overwrite it.
  step("diagnostic config", function()
    -- `ui` picks ]d/[d's sink (lsp.bindings.actions) and `debounce_ms` sizes
    -- the publish throttle (lsp.core.handlers); vim.diagnostic.config() has
    -- neither option and would receive them verbatim otherwise.
    local diag_opts = vim.tbl_extend("force", {}, cfg.diagnostics)
    diag_opts.ui = nil
    diag_opts.debounce_ms = nil
    vim.diagnostic.config(diag_opts)
  end)

  if cfg.mason.ensure_install then
    step("mason ensure_install", function()
      require("lsp.integrations.mason.ensure_install").enable({
        lsp = true,
        dap = true,
        linters = true,
        formatters = true,
        overrides = cfg.mason.overrides,
      })
    end)
  end

  step("lspdoctor", function()
    local doctor = require("lsp.lspdoctor")
    doctor.setup(cfg.lspdoctor)
    doctor.enable_usercmd()
  end)

  setup_tools(cfg)

  if cfg.usrcmds.legacy_aliases then
    -- `:Diag*` are aliases onto `:Lsp diag` for the same reason.
    step("diagnostics commands", function()
      require("lsp.diagnostics").setup()
    end)
  end

  return #_servers > 0
end

--- Set up lsp.nvim. Safe to call once; a second call is refused rather than
--- rebinding and re-registering on top of the first.
---@param opts? LspNvim.Config|table
---@return boolean success
function M.setup(opts)
  if _initialized then
    notify.warn("setup() has already run")
    return false
  end

  local cfg = config.setup(opts)
  _warnings = {}
  for _, w in ipairs(config.warnings()) do
    _warnings[#_warnings + 1] = w
  end

  _keymaps, _usrcmd = require("lsp.bindings").setup(cfg)
  local ok = bootstrap(cfg)
  _initialized = true

  return ok
end

--- Apply the resolved capabilities to every server config as a base.
---
--- The entry point the host should call: it passes the integration layer's
--- contributors, which `lsp.core.capabilities.apply_globally()` cannot look up
--- on its own without the core reaching into the integrations.
---@return boolean ok
---@return LspCaps.Warning[] warnings
function M.apply_capabilities()
  return require("lsp.core.capabilities").apply_globally(integrations.capability_contributors())
end

--- Snapshot of what the plugin currently is. `:Lsp status` and
--- `:checkhealth lsp` both read this, so neither can drift from the other.
---@return LspNvim.Status
function M.status()
  return {
    initialized = _initialized,
    config = _initialized and config.get() or nil,
    layers = config.layers(),
    keymaps = _keymaps,
    usrcmd = _usrcmd,
    servers = _servers,
    clients = vim.lsp.get_clients(),
    warnings = _warnings,
  }
end

return M
