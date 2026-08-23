---@module 'lsp.tools.eslint_prettier.prettier'
--- Resolves and caches the `prettier` executable (PATH, falling back to
--- Mason's bin dir) -- the one thing `format.lua` needs before it can
--- spawn anything.
local executable = require("lib.nvim.cross.executable")
local M = { prettier_bin = nil }

---@param name string
---@return string|nil
local function resolve_executable(name)
  return executable.exists(name) and name or executable.mason_bin(name)
end

function M.get_prettier_bin()
  if M.prettier_bin then
    return M.prettier_bin
  end
  M.prettier_bin = resolve_executable("prettier")
  return M.prettier_bin
end

---@param path string
function M.set_prettier_bin(path)
  M.prettier_bin = path
end

return M
