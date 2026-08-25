-- TESTS/smoke.lua — headless load/setup check for lsp.nvim.
--
-- Run from the repo root, with lib.nvim reachable:
--   nvim --headless -u NONE -c "set rtp^=." -c "set rtp^=../lib.nvim" \
--        -c "luafile TESTS/smoke.lua" -c "qa!"
--
-- `rtp^=` prepends on purpose. `-u NONE` skips the user vimrc but leaves the
-- user config directory on the runtimepath, and while the nvim config still
-- carries its own `lua/lsp/**` (until migration phase 2) an appended entry
-- loses: `require("lsp")` resolves to the config, not to this plugin, and the
-- test silently exercises the wrong code.
--
-- Deliberately a smoke test, not a suite: it checks that every module loads,
-- that the configuration resolves and degrades sanely, and that the bootstrap
-- gets far enough to register servers, commands and the formatter API. It does
-- not exercise the servers themselves -- that needs real language binaries.

local failed = 0

---@param cond any
---@param msg string
local function ok(cond, msg)
  if cond then
    print("ok    " .. msg)
  else
    failed = failed + 1
    print("FAIL  " .. msg)
  end
end

-- Every module loads on its own, so a typo in a file nothing requires yet
-- still fails the build.
for _, mod in ipairs({
  "lsp",
  "lsp.@types",
  "lsp.health",
  "lsp.config",
  "lsp.config.DEFAULTS",
  "lsp.config.KEYMAPS",
  "lsp.config.@types",
  "lsp.bindings",
  "lsp.bindings.keymaps",
  "lsp.bindings.usrcmds",
  "lsp.bindings.autocmds",
  "lsp.bindings.which_key",
  "lsp.bindings.@types",
  -- The migrated subsystem: every entry point the bootstrap touches.
  "lsp.core.registry",
  "lsp.core.capabilities",
  "lsp.core.attach",
  "lsp.core.handlers",
  "lsp.core.diagnostics",
  "lsp.formatter",
  "lsp.formatter.conform",
  "lsp.diagnostics",
  "lsp.languages",
  "lsp.lspdoctor",
  "lsp.usercmds",
  "lsp.integrations.mason.ensure_install",
}) do
  local loaded, err = pcall(require, mod)
  ok(loaded, ("require(%q)%s"):format(mod, loaded and "" or " -> " .. tostring(err)))
end

local config = require("lsp.config")

-- Defaults resolve without any user options.
local cfg = config.setup(nil)
ok(cfg.keymaps.enable == true, "defaults: keymaps.enable")
ok(cfg.keymaps.preset == "default", "defaults: keymaps.preset")
ok(cfg.usrcmds.enable == true, "defaults: usrcmds.enable")
ok(#config.warnings() == 0, "defaults: no warnings")

-- A bad value degrades to the documented default and is reported, rather than
-- being passed through or raised.
cfg = config.setup({ keymaps = { preset = "nonsense" }, which_key = "yes" })
ok(cfg.keymaps.preset == "default", "normalize: unknown preset falls back")
ok(cfg.which_key.enable == true, "normalize: malformed which_key falls back")
ok(#config.warnings() >= 1, "normalize: warnings recorded")

-- The server list is configuration now, not a constant in core/registry.lua.
ok(type(cfg.servers) == "table" and #cfg.servers > 0, "defaults: servers list is populated")
cfg = config.setup({ servers = {} })
ok(#cfg.servers > 0, "normalize: empty server list falls back to defaults")
cfg = config.setup({ servers = { "lua_ls", 42 } })
ok(#cfg.servers == 1 and cfg.servers[1] == "lua_ls", "normalize: non-string server entries dropped")
cfg = config.setup({ formatter = false })
ok(type(cfg.formatter) == "table", "normalize: malformed sub-table falls back")

-- setup() is idempotent-by-refusal and registers the command.
local lsp = require("lsp")
ok(lsp.setup({}) == true, "setup(): first call succeeds")
ok(lsp.setup({}) == false, "setup(): second call refused")

local status = lsp.status()
ok(status.initialized == true, "status: initialized")
ok(type(status.keymaps) == "table", "status: keymaps list")
ok(status.usrcmd == true, "status: `:Lsp` registered")
ok(vim.fn.exists(":Lsp") == 2, "`:Lsp` exists as a command")

-- The migrated bootstrap actually ran: servers registered, the doctor and the
-- legacy command family are there, and the formatter API was published.
ok(#status.servers > 0, "status: servers were set up (" .. #status.servers .. ")")
ok(vim.fn.exists(":LspDoctor") == 2, "`:LspDoctor` exists")
ok(vim.fn.exists(":LspStatus") == 2, "`:LspStatus` (legacy) exists")
ok(type(vim.g._formatter_api) == "table", "formatter API published for the keymaps")

-- The keymap catalogue is real now (migration phase 3), so check that the
-- mechanism around it actually does what the config options promise.
ok(#status.keymaps > 30, "keymaps: default preset bound " .. #status.keymaps .. " entries")

local KEYMAPS = require("lsp.config.KEYMAPS")
local bound = {}
for _, spec in ipairs(status.keymaps) do
  bound[spec.name] = spec.lhs
end
ok(bound.qf_next == "]q", "keymaps: ]q comes from the catalogue")
ok(bound.rename == "grn" and bound.rename_leader == "<leader>rn", "keymaps: both rename keys bound")
ok(
  KEYMAPS.entries.rename.rhs == KEYMAPS.entries.rename_leader.rhs,
  "keymaps: both rename keys share one action (B9)"
)
ok(#KEYMAPS.presets.minimal < #KEYMAPS.presets.default, "keymaps: minimal is a subset")

-- Overrides and the off switches, checked through a fresh setup rather than
-- through the module's internals.
package.loaded["lsp"] = nil
local lsp2 = require("lsp")
lsp2.setup({ keymaps = { map = { qf_next = "<leader>zz", rename = false } } })
local bound2 = {}
for _, spec in ipairs(lsp2.status().keymaps) do
  bound2[spec.name] = spec.lhs
end
ok(bound2.qf_next == "<leader>zz", "keymaps.map: a string replaces the lhs")
ok(bound2.rename == nil, "keymaps.map: false drops the mapping")

package.loaded["lsp"] = nil
local lsp3 = require("lsp")
lsp3.setup({ keymaps = { preset = "none" } })
ok(#lsp3.status().keymaps == 0, 'keymaps: preset "none" binds nothing')

package.loaded["lsp"] = nil
local lsp4 = require("lsp")
lsp4.setup({ keymaps = { enable = false } })
ok(#lsp4.status().keymaps == 0, "keymaps.enable = false binds nothing")

-- health.check() must not throw, whatever the environment looks like.
ok(pcall(require("lsp.health").check), "health.check() runs")

if failed > 0 then
  print(("\n%d check(s) failed"):format(failed))
  os.exit(1)
end

print("\nLSP_NVIM_SMOKE_OK")
