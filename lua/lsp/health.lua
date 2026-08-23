---@module 'lsp.health'
---@brief `:checkhealth lsp`.
---@description
--- Reports the environment, what `setup()` actually did, the servers, and the
--- ecosystem around the plugin. It reads `require("lsp").status()` rather than
--- reaching into the modules, so the health output and `:Lsp status` cannot
--- disagree.
---
--- Roadmap section 11 makes this a thin second interface onto `lspdoctor`'s
--- core. That is what the last section is: `:LspDoctor health` answers "is this
--- buffer's LSP healthy", this answers "is the plugin healthy" and points at
--- the other for the per-buffer detail. Neither reimplements the other.
---
--- Severity follows dependency hardness: something the plugin cannot work
--- without is an error, something it uses when present is information.
---
---@see lsp.init
---@see lsp.config
---@see lsp.lspdoctor

local health = vim.health

local M = {}

--- Third-party plugins around the umbrella, with the module used to detect
--- them. `hard` marks the ones whose absence degrades the plugin's own
--- behaviour rather than merely removing an extra.
---@type { name: string, probe: string, hard: boolean, note: string }[]
local ECOSYSTEM = {
  {
    name = "lib.nvim",
    probe = "lib.nvim.map",
    hard = true,
    note = "commands, keymaps, notifications",
  },
  {
    name = "conform.nvim",
    probe = "conform",
    hard = true,
    note = "the formatter's primary engine",
  },
  {
    name = "mason.nvim",
    probe = "mason",
    hard = false,
    note = "only needed for `mason.ensure_install`",
  },
  {
    name = "lazydev.nvim",
    probe = "lazydev",
    hard = false,
    note = "lua_ls library resolution on attach",
  },
  {
    name = "workspace-diagnostics.nvim",
    probe = "workspace-diagnostics",
    hard = false,
    note = "workspace-wide diagnostics on attach",
  },
  { name = "nvim-cmp", probe = "cmp_nvim_lsp", hard = false, note = "completion capabilities" },
  {
    name = "blink.cmp",
    probe = "blink.cmp",
    hard = false,
    note = "completion capabilities (alternative)",
  },
  {
    name = "trouble.nvim",
    probe = "trouble",
    hard = false,
    note = "diagnostics UI; not wired yet (phase 4)",
  },
  {
    name = "which-key.nvim",
    probe = "which-key",
    hard = false,
    note = "group labels for bound prefixes",
  },
}

---@internal
---@param modname string
---@return boolean
local function has(modname)
  return (pcall(require, modname))
end

---@internal
--- Neovim version and the one dependency the plugin cannot run without.
---@return nil
local function check_environment()
  health.start("Environment")

  if vim.fn.has("nvim-0.11") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.11+ required, found " .. tostring(vim.version()))
  end

  if has("lib.nvim.map") then
    health.ok("lib.nvim available")
  else
    health.error("lib.nvim missing", {
      "lsp.nvim depends on it hard: the `:Lsp` command is built on "
        .. "lib.nvim.usercmd.composer and will not register without it.",
      'Install it: dependencies = { "StefanBartl/lib.nvim" }',
    })
  end
end

---@internal
--- What setup() did, and anything it had to work around.
---@return nil
local function check_plugin()
  health.start("lsp.nvim")

  local status = require("lsp").status()

  if not status.initialized then
    health.warn("setup() has not run", {
      'Call require("lsp").setup() -- or use `opts = {}` in your plugin spec.',
    })
    return
  end
  health.ok("setup() has run")

  for _, warning in ipairs(status.warnings) do
    health.warn(warning)
  end
  if #status.warnings == 0 then
    health.ok("no warnings during setup")
  end

  local cfg = status.config
  if cfg == nil then
    return
  end

  if not cfg.keymaps.enable then
    health.info("keymaps: disabled (keymaps.enable = false)")
  elseif #status.keymaps == 0 then
    health.info(
      ("keymaps: preset %q is empty -- no keys bound (the catalogue fills up in "):format(
        cfg.keymaps.preset
      ) .. "migration phase 3)"
    )
  else
    health.ok(("keymaps: %d bound from preset %q"):format(#status.keymaps, cfg.keymaps.preset))

    -- `requires` is recorded at bind time, not enforced (see
    -- lsp.bindings.keymaps for why). This is where it pays off: a key that is
    -- bound but whose plugin is missing fails only when pressed, which is the
    -- worst moment to find out.
    ---@type table<string, string[]>
    local missing = {}
    for _, spec in ipairs(status.keymaps) do
      if spec.requires ~= nil and not has(spec.requires) then
        missing[spec.requires] = missing[spec.requires] or {}
        table.insert(missing[spec.requires], spec.lhs)
      end
    end
    for plugin, lhs_list in pairs(missing) do
      table.sort(lhs_list)
      health.warn(
        ("%d keymap(s) bound for %s, which is not installed: %s"):format(
          #lhs_list,
          plugin,
          table.concat(lhs_list, ", ")
        ),
        { ("Install %s, or switch them off via keymaps.map."):format(plugin) }
      )
    end
  end

  if not cfg.usrcmds.enable then
    health.info("`:Lsp`: disabled (usrcmds.enable = false)")
  elseif status.usrcmd then
    health.ok("`:Lsp` registered")
  else
    health.error("`:Lsp` failed to register", {
      "The composer refused the route spec, or lib.nvim is missing.",
    })
  end

  health.info(
    ("formatter: on_save = %s, timeout %dms"):format(
      tostring(cfg.formatter.on_save),
      cfg.formatter.timeout_ms
    )
  )
end

---@internal
--- Configured versus actually set up versus actually attached. The gap between
--- the three is what one wants to see when a server "does not work".
---@return nil
local function check_servers()
  health.start("Servers")

  local status = require("lsp").status()
  local configured = status.config and status.config.servers or {}

  if not status.initialized then
    health.info("setup() has not run; nothing configured")
    return
  end

  health.info(("configured: %d (%s)"):format(#configured, table.concat(configured, ", ")))

  if #status.servers == 0 then
    health.error("no server was set up", {
      "Every configured name failed to resolve to an `lsp.servers.<name>` module,",
      "or its setup() threw. The reasons are in the warnings above.",
    })
  elseif #status.servers < #configured then
    ---@type table<string, true>
    local ok_set = {}
    for _, name in ipairs(status.servers) do
      ok_set[name] = true
    end
    ---@type string[]
    local missing = {}
    for _, name in ipairs(configured) do
      if not ok_set[name] then
        missing[#missing + 1] = name
      end
    end
    health.warn(
      ("set up %d of %d; missing: %s"):format(
        #status.servers,
        #configured,
        table.concat(missing, ", ")
      )
    )
  else
    health.ok(("set up: %d"):format(#status.servers))
  end

  local clients = vim.lsp.get_clients()
  if #clients == 0 then
    health.info("no client attached to any buffer (expected until a matching file is opened)")
    return
  end
  for _, client in ipairs(clients) do
    local buffers = vim.tbl_keys(client.attached_buffers or {})
    health.ok(
      ("%s (id %d): %d buffer(s), root %s"):format(
        client.name,
        client.id,
        #buffers,
        client.root_dir or "-"
      )
    )
  end
end

---@internal
--- The plugins around the umbrella.
---@return nil
local function check_ecosystem()
  health.start("Ecosystem")

  for _, entry in ipairs(ECOSYSTEM) do
    local present = has(entry.probe)
    local line = ("%s -- %s"):format(entry.name, entry.note)
    if present then
      health.ok(line)
    elseif entry.hard then
      health.error(line .. " [missing]")
    else
      health.info(line .. " [not installed]")
    end
  end
end

---@internal
--- Point at the per-buffer diagnosis rather than repeating it.
---@return nil
local function check_doctor()
  health.start("Per-buffer diagnosis")

  if has("lsp.lspdoctor") then
    health.ok("`:LspDoctor health|debug|quick|deep|all` available")
    health.info("This report covers the plugin; :LspDoctor covers the current buffer.")
  else
    health.warn("lsp.lspdoctor did not load")
  end
end

--- Entry point for `:checkhealth lsp`.
---@return nil
function M.check()
  check_environment()
  check_plugin()
  check_servers()
  check_ecosystem()
  check_doctor()
end

return M
