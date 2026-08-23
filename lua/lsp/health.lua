---@module 'lsp.health'
---@brief `:checkhealth lsp`.
---@description
--- Reports the environment, the plugin's own state and what the planned
--- integrations look like from here. It reads `require("lsp").status()` rather
--- than reaching into the modules, so the health output and `:Lsp status`
--- cannot disagree.
---
--- Roadmap §11 makes this a thin second interface onto `lspdoctor`'s core once
--- that has moved (phase 2). Until then it stands alone -- but the split is
--- already the one designed there: this file formats, it does not diagnose.
---
--- Severity follows the dependency hardness from roadmap §3: a missing hard
--- dependency is an error, a missing soft one is information. The third-party
--- plugins are reported as information for now because nothing wires them yet;
--- calling them errors would report a problem the plugin does not actually
--- have.
---
---@see lsp.init
---@see lsp.config

local health = vim.health

local M = {}

--- Third-party plugins the umbrella will take over, with the probe module used
--- to detect them and the hardness planned in roadmap §3.
---@type { name: string, probe: string, hard: boolean }[]
local PLANNED = {
  { name = "lib.nvim", probe = "lib.nvim.map", hard = true },
  { name = "trouble.nvim", probe = "trouble", hard = true },
  { name = "conform.nvim", probe = "conform", hard = true },
  { name = "lazydev.nvim", probe = "lazydev", hard = true },
  { name = "mason.nvim", probe = "mason", hard = true },
  { name = "workspace-diagnostics.nvim", probe = "workspace-diagnostics", hard = true },
  { name = "nvim-cmp", probe = "cmp", hard = false },
  { name = "blink.cmp", probe = "blink.cmp", hard = false },
  { name = "lspsaga.nvim", probe = "lspsaga", hard = false },
  { name = "inc-rename.nvim", probe = "inc_rename", hard = false },
  { name = "which-key.nvim", probe = "which-key", hard = false },
}

---@internal
---@param modname string
---@return boolean
local function has(modname)
  return (pcall(require, modname))
end

---@internal
--- Neovim version and the one hard dependency the plugin cannot run without.
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
--- What setup() actually did.
---@return nil
local function check_plugin()
  health.start("lsp.nvim")

  local status = require("lsp").status()

  if not status.initialized then
    health.warn("setup() has not run", {
      'Call require("lsp").setup() -- or use `opts = {}` in your plugin spec.',
    })
  else
    health.ok("setup() has run")
  end

  for _, warning in ipairs(status.warnings) do
    health.warn("config: " .. warning)
  end

  local cfg = status.config
  if cfg ~= nil then
    if not cfg.keymaps.enable then
      health.info("keymaps: disabled (keymaps.enable = false)")
    elseif #status.keymaps == 0 then
      health.info(
        ("keymaps: preset %q is empty -- no keys bound (expected: the catalogue "):format(
          cfg.keymaps.preset
        ) .. "fills up in migration phase 3)"
      )
    else
      health.ok(("keymaps: %d bound from preset %q"):format(#status.keymaps, cfg.keymaps.preset))
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
  end
end

---@internal
--- Neovim's own LSP state -- independent of this plugin, and the thing one
--- actually wants to know when something is wrong.
---@return nil
local function check_clients()
  health.start("LSP clients")

  local clients = vim.lsp.get_clients()
  if #clients == 0 then
    health.info("No client attached to any buffer")
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
--- The ecosystem the umbrella is meant to take over. Information only: nothing
--- here is wired yet, so a missing plugin is not a fault of this one.
---@return nil
local function check_planned()
  health.start("Planned integrations (not wired yet)")

  for _, entry in ipairs(PLANNED) do
    local hardness = entry.hard and "hard" or "soft"
    if has(entry.probe) then
      health.info(("%s: installed (%s dependency once wired)"):format(entry.name, hardness))
    else
      health.info(("%s: not installed (%s dependency once wired)"):format(entry.name, hardness))
    end
  end

  health.info(
    "Migration phase 4 turns these into real adapters; until then lsp.nvim "
      .. "neither configures nor requires them. See docs/ROADMAP.md."
  )
end

--- Entry point for `:checkhealth lsp`.
---@return nil
function M.check()
  check_environment()
  check_plugin()
  check_clients()
  check_planned()
end

return M
