---@module 'config.mason.ensure_install.defaults.dap'
-- =====================================================================================
-- Tool set (defaults): true = ensure install, false = ignore
-- =====================================================================================

---@type Cfg.Mason.EnsureMap
return {
  -- ["java-language-server"] = false,
  -- ["php-debug-adapter"] = true,
  ["netcoredbg"] = true,
  -- ["java-test"] = true,
  -- ["java-debug-adapter"] = true,
  -- ["go-debug-adapter"] = true,
  ["bash-debug-adapter"] = true,
  ["codelldb"] = true, -- zig, rust, c

  -- Web Development
  ["node-debug2-adapter"] = false,
  ["js-debug-adapter"] = true,
  ["firefox-debug-adapter"] = true,
}
