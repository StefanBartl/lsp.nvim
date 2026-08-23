---@module 'lsp.core.mason_node'
---@brief Resolve a Mason-installed Node language server to a direct `node <entry>` command.
---@description
--- Fixes a hanging quit on Windows, diagnosed in
--- docs/ROADMAP/QuitCrash_NVIM.md and confirmed by measurement.
---
--- ## The problem
---
--- Mason exposes Node servers through batch shims, and there are two layers of
--- them. `mason/bin/tailwindcss-language-server.cmd` calls
--- `mason/packages/<pkg>/node_modules/.bin/<name>.cmd`, which finally starts
--- `node <entry>`. Starting the server through that shim gives:
---
---     nvim
---      └─ cmd.exe          <- the shim
---          └─ node.exe     <- the actual server
---
--- On quit, Neovim tears down the UI, kills its children, and then waits for
--- the stdout/stderr pipes to those children to CLOSE before calling `exit()`.
--- Windows has no process groups: Neovim kills `cmd.exe`, but `node.exe`
--- inherited the same pipe and keeps it open, so the wait never ends. The
--- screen is cleared and the terminal never comes back.
---
--- Measured on this config: quitting hung indefinitely with exactly that tree
--- (tailwindcss-language-server). Killing the `node.exe` by hand let Neovim
--- exit within seconds — which is what makes this a diagnosis rather than a
--- theory.
---
--- ## The fix
---
--- Skip the shims and run `node <entry>` directly, so the server is Neovim's
--- own child and the pipe closes when it dies. The entry point is read out of
--- npm's `.bin` shim, which has a stable generated shape ending in:
---
---     "%_prog%"  "%dp0%\..\@scope\pkg\bin\name" %*
---
--- so the path after `%dp0%` is what we want, resolved against the `.bin`
--- directory.
---
--- Parsing a generated file is not elegant, but the alternative -- hardcoding
--- one entry path per server -- breaks silently on every Mason update. This
--- returns nil whenever anything is unexpected, and callers then keep their
--- previous command: a failed parse costs the fix, never the server.

local M = {}

---@return string
local function mason_root()
  return vim.fn.stdpath("data") .. "/mason"
end

--- Read the entry script out of npm's generated `.bin/<name>.cmd` shim.
---@param bin_dir string  # the package's node_modules/.bin directory
---@param name string
---@return string|nil  # absolute path to the JS entry point
local function entry_from_shim(bin_dir, name)
  local shim = bin_dir .. "/" .. name .. ".cmd"
  local ok, lines = pcall(vim.fn.readfile, shim)
  if not ok or type(lines) ~= "table" then
    return nil
  end

  for _, line in ipairs(lines) do
    -- The invocation line ends with: "%_prog%"  "%dp0%\..\<rel>" %*
    -- Long-bracket pattern on purpose: no string escapes to get wrong, and
    -- `%%` is a literal `%` to the pattern matcher either way.
    local rel = line:match([["%%dp0%%(.-)"]])
    if rel and rel ~= "" then
      rel = rel:gsub("\\", "/"):gsub("^/+", "")
      local abs = vim.fs.normalize(bin_dir .. "/" .. rel)
      if (vim.uv or vim.loop).fs_stat(abs) then
        return abs
      end
    end
  end

  return nil
end

--- Build a direct `node <entry>` command for a Mason-installed Node server.
---
--- Returns nil off Windows (the shim indirection only exists there, and the
--- pipe problem it causes is Windows-specific), when the package is not
--- installed, or when the shim does not parse.
---@param mason_pkg string   # Mason package name, e.g. "tailwindcss-language-server"
---@param bin_name string|nil  # binary inside the package; defaults to `mason_pkg`
---@return string[]|nil cmd
function M.cmd(mason_pkg, bin_name)
  if vim.fn.has("win32") ~= 1 then
    return nil
  end

  bin_name = bin_name or mason_pkg

  local bin_dir = mason_root() .. "/packages/" .. mason_pkg .. "/node_modules/.bin"
  if not (vim.uv or vim.loop).fs_stat(bin_dir) then
    return nil
  end

  local entry = entry_from_shim(bin_dir, bin_name)
  if not entry then
    return nil
  end

  return { "node", entry }
end

--- `M.cmd()` with the server's arguments appended, falling back to `fallback`
--- unchanged when the direct command cannot be built. This is the shape server
--- configs want:
---
---     cmd = mason_node.cmd_or(
---       "tailwindcss-language-server",
---       { "tailwindcss-language-server", "--stdio" },
---       { "--stdio" }
---     )
---@param mason_pkg string
---@param fallback string[]   # the command to keep when resolution fails
---@param args string[]|nil   # arguments appended to `node <entry>`
---@param bin_name string|nil
---@return string[] cmd
function M.cmd_or(mason_pkg, fallback, args, bin_name)
  local direct = M.cmd(mason_pkg, bin_name)
  if not direct then
    return fallback
  end
  for _, a in ipairs(args or {}) do
    direct[#direct + 1] = a
  end
  return direct
end

return M
