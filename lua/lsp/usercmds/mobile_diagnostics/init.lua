---@module 'lsp.usercmds.mobile_diagnostics'
--- Diagnostic command to check mobile development setup.

local notify = require("lib.nvim.notify").create("[lsp.mobile_diagnostics]")
local usercmd = require("lib.nvim.usercmd")

local M = {}

---Check if executable exists
---@param name string
---@return boolean
local function is_executable(name)
  return vim.fn.executable(name) == 1
end

---Check environment variable
---@param name string
---@return string|nil
local function get_env(name)
  local val = vim.env[name]
  return (val and val ~= "") and val or nil
end

---Run diagnostics for mobile development environment
---@return nil
function M.run()
  local results = {}

  -- Java/Android
  results[#results + 1] = "=== Java/Android ==="
  results[#results + 1] = string.format("  java: %s", is_executable("java") and "✓" or "✗")
  results[#results + 1] = string.format("  JAVA_HOME: %s", get_env("JAVA_HOME") or "not set")
  results[#results + 1] = string.format("  jdtls: %s", is_executable("jdtls") and "✓" or "✗")
  results[#results + 1] = string.format(
    "  kotlin-language-server: %s",
    is_executable("kotlin-language-server") and "✓" or "✗"
  )

  -- Flutter/Dart
  results[#results + 1] = ""
  results[#results + 1] = "=== Flutter/Dart ==="
  results[#results + 1] = string.format("  dart: %s", is_executable("dart") and "✓" or "✗")
  results[#results + 1] =
    string.format("  flutter: %s", is_executable("flutter") and "✓" or "✗")
  results[#results + 1] = string.format("  FLUTTER_ROOT: %s", get_env("FLUTTER_ROOT") or "not set")

  -- iOS (macOS only)
  results[#results + 1] = ""
  results[#results + 1] = "=== iOS (macOS only) ==="
  local is_macos = (vim.loop or vim.uv).os_uname().sysname == "Darwin"
  results[#results + 1] = string.format("  Platform: %s", is_macos and "macOS ✓" or "not macOS")
  results[#results + 1] =
    string.format("  sourcekit-lsp: %s", is_executable("sourcekit-lsp") and "✓" or "✗")

  notify.info(table.concat(results, "\n"))
end

---@return nil
function M.attach()
  usercmd.create("LspMobileDiagnostics", function()
    M.run()
  end, {
    desc = "Check mobile development LSP setup",
  })
end

return M
