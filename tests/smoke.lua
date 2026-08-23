-- tests/smoke.lua — headless load/setup check for lsp.nvim.
--
-- Run from the repo root, with lib.nvim reachable:
--   nvim --headless -u NONE -c "set rtp^=." -c "set rtp^=../lib.nvim" \
--        -c "luafile tests/smoke.lua" -c "qa!"
--
-- `rtp^=` prepends on purpose. `-u NONE` skips the user vimrc but leaves the
-- user config directory on the runtimepath, and while the nvim config still
-- carries its own `lua/lsp/**` (until migration phase 2) an appended entry
-- loses: `require("lsp")` resolves to the config, not to this plugin, and the
-- test silently exercises the wrong code.
--
-- Deliberately a smoke test, not a suite: at this stage the plugin's job is to
-- load cleanly, resolve its configuration and register `:Lsp`. Real specs
-- arrive with the code they would cover (see docs/ROADMAP.md).

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

-- setup() is idempotent-by-refusal and registers the command.
local lsp = require("lsp")
ok(lsp.setup({}) == true, "setup(): first call succeeds")
ok(lsp.setup({}) == false, "setup(): second call refused")

local status = lsp.status()
ok(status.initialized == true, "status: initialized")
ok(type(status.keymaps) == "table", "status: keymaps list")
ok(status.usrcmd == true, "status: `:Lsp` registered")
ok(vim.fn.exists(":Lsp") == 2, "`:Lsp` exists as a command")

-- health.check() must not throw, whatever the environment looks like.
ok(pcall(require("lsp.health").check), "health.check() runs")

if failed > 0 then
  print(("\n%d check(s) failed"):format(failed))
  os.exit(1)
end

print("\nLSP_NVIM_SMOKE_OK")
