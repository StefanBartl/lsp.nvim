---@module 'lsp.core.direct_exe'
---@brief Point a server command at the real executable instead of a launcher wrapper.
---@description
--- Windows only. Package managers expose servers through launchers:
---
--- - Mason puts `mason/bin/<name>.CMD` on PATH, a batch file that starts
---   `mason/packages/<pkg>/<name>.exe`. A bare `{ "marksman", "server" }`
---   resolves to that batch file, so the process tree is
---   `nvim -> cmd.exe -> marksman.exe`.
--- - scoop puts `scoop/shims/<name>.exe` on PATH, a small launcher that starts
---   `scoop/apps/<app>/current/...`.
---
--- `client:stop(true)` (and `:LspStop`) terminates only Neovim's direct child.
--- Windows has no process groups, so with a batch wrapper only `cmd.exe` dies;
--- the server is a grandchild that inherited Neovim's stdio pipes. When it does
--- not exit on its own (it is busy, or never sees EOF) it stays alive, and the
--- handles `vim.system` keeps for the pipes -- including its `check` handle --
--- stay active with it. Live sessions showed several orphaned
--- `cmd.exe /c ...\mason\bin\marksman.CMD server` trees, each with a
--- `marksman.exe` grandchild. `lsp.core.mason_node` solves the same problem
--- for Node servers.
---
--- The fix is to start the executable itself when it is where the package
--- manager installs it, so the server is Neovim's own child and dies with the
--- kill. When none of the candidates exists the PATH name is kept unchanged: a
--- miss costs the fix, never the server.

local M = {}

---@param path string
---@return boolean
local function is_file(path)
  local stat = (vim.uv or vim.loop).fs_stat(path)
  return stat ~= nil and stat.type == "file"
end

--- Executable of a Mason package, `stdpath("data")/mason/packages/<pkg>/<exe>`.
---@param pkg string   # Mason package name, e.g. "marksman"
---@param exe string   # file inside the package, e.g. "marksman.exe"
---@return string
function M.mason_package(pkg, exe)
  return vim.fn.stdpath("data") .. "/mason/packages/" .. pkg .. "/" .. exe
end

--- Executable of a scoop app, `<scoop root>/apps/<app>/current/<rel>`.
--- The root is `$SCOOP` when set, otherwise `~/scoop` (scoop's default).
---@param app string  # scoop app name, e.g. "lua-language-server"
---@param rel string  # path inside the app's `current` dir
---@return string
function M.scoop_app(app, rel)
  local root = vim.env.SCOOP
  if root == nil or root == "" then
    root = vim.fn.expand("~") .. "/scoop"
  end
  return root .. "/apps/" .. app .. "/current/" .. rel
end

--- The first existing candidate, or `name` when there is none (or when not on
--- Windows, where launchers do not cut the server off from the kill).
---@param name string           # the PATH name to fall back to
---@param candidates string[]   # absolute paths, in order of preference
---@return string
function M.resolve(name, candidates)
  if vim.fn.has("win32") ~= 1 then
    return name
  end
  for _, path in ipairs(candidates) do
    if is_file(path) then
      return vim.fs.normalize(path)
    end
  end
  return name
end

--- `{ resolve(name, candidates), args... }` -- the shape a server config wants.
---@param name string
---@param candidates string[]
---@param args string[]|nil
---@return string[]
function M.cmd(name, candidates, args)
  local cmd = { M.resolve(name, candidates) }
  for _, a in ipairs(args or {}) do
    cmd[#cmd + 1] = a
  end
  return cmd
end

return M
