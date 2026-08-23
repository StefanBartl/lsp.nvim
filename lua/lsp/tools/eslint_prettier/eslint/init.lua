---@module 'lsp.tools.eslint_prettier.eslint'
--- eslint utilities and bin resolution
local executable = require("lib.nvim.cross.executable")

local M = {
  eslint_bin = nil, -- resolved executable (string)
}

--- Try to resolve executable by name, then mason bin folder, add .cmd on Windows.
---@param name string
---@return string|nil
local function resolve_executable(name)
  return executable.exists(name) and name or executable.mason_bin(name)
end

function M.get_eslint_bin()
  if M.eslint_bin then
    return M.eslint_bin
  end
  M.eslint_bin = resolve_executable("eslint_d")
  return M.eslint_bin
end

---@param path string
function M.set_eslint_bin(path)
  M.eslint_bin = path
end

return M
