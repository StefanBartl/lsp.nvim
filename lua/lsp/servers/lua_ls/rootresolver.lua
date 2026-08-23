---@module 'lsp.servers.lua_ls.rootresolver'
--- Utilities to resolve a project's root directory from a filename or buffer.
--- This module exposes:
---  - strict_root_from(fname) : determine a strict project root from a filename or CWD
---  - make_root_dir_resolver() : return a polymorphic resolver usable by LSP configs

-- Import filesystem helper to check if a path is contained within another
local is_subpath = require("lib.nvim.fs.is_subpath")
-- Global cwd/git/path switch (see lsp.core.root_scope_picker, <leader>lsp)
local root_scope = require("lsp.core.root_scope")

--- Determine a strict root directory from a filename or use sensible fallbacks.
---
--- Algorithm Steps:
--- 1. Determine a starting directory: directory of fname or CWD.
--- 2. If the start dir is under Neovim's stdpath("config"), return that config path.
--- 3. If a VCS root (git/hg/svn) is found upward, return it.
--- 4. If certain Lua/tool config markers are found upward, return the marker's dirname.
--- 5. Otherwise return the start dir itself.
---
--- This ensures lua_ls always has a well-defined project boundary, which is crucial
--- for proper workspace library configuration and performance.
---
--- @param fname string|nil filename or filepath; can be empty string
--- @return string|nil root directory or nil when no directory could be determined
local function strict_root_from(fname)
  -- Start at the directory component of the file; fallback to CWD
  -- We normalize the path to handle different path representations
  local dir = (type(fname) == "string" and fname ~= "" and vim.fs.dirname(vim.fs.normalize(fname)))
    -- Try to get current working directory from multiple sources for compatibility
    or ((vim.uv or vim.loop).cwd and (vim.uv or vim.loop).cwd())
    or vim.fn.getcwd()

  -- Special case: If we're inside Neovim's config directory, treat that as the root
  -- This is common when editing init.lua or plugin configurations
  local stdconfig = vim.fn.stdpath("config")
  if is_subpath(dir, stdconfig) then
    return stdconfig
  end

  -- Guard against invalid directory
  if not dir or dir == "" then
    return nil
  end

  -- Root-scope switch (<leader>lsp): "cwd" and "path" bypass the VCS/marker
  -- search below entirely; "git" (default) keeps the original algorithm.
  local scope = root_scope.get()

  if scope == "cwd" then
    return (vim.uv or vim.loop).cwd() or vim.fn.getcwd()
  end

  if scope == "path" then
    return dir
  end

  -- Step 1: Look for version control system markers
  -- These are the strongest indicators of a project boundary
  -- vim.fs.root searches upward from dir for these markers
  local vcs_root = vim.fs.root(dir, { ".git", ".hg", ".svn" })
  if vcs_root then
    return vcs_root
  end

  -- Step 2: Look for Lua-specific configuration files
  -- These files typically sit at the project root
  local lua_markers = vim.fs.find(
    { ".luarc.json", ".neoconf.json", "selene.toml", "stylua.toml" },
    { path = dir, upward = true } -- Search upward from current directory
  )

  -- If we found a marker file, use its directory as the root
  if lua_markers and lua_markers[1] then
    return vim.fs.dirname(lua_markers[1])
  end

  -- Step 3: Fallback to the starting directory itself
  -- This ensures single-file support still works
  return dir
end

--- Create a polymorphic root-directory resolver.
---
--- The returned function is compatible with LSP root_dir configurations and
--- accepts either:
---   - (bufnr: number, cb: function?) OR
---   - (fname: string, cb: function?)
---
--- Behavior:
--- - If a buffer number is given, the buffer's filename is extracted and used.
--- - If a callback `cb` is provided, it is invoked with the resolved root.
--- - The resolved root is always returned synchronously for immediate use.
---
--- This flexibility allows the resolver to work with both traditional LSP configs
--- and newer callback-based configurations.
---
--- @return string|nil function Resolver function compatible with vim.lsp root_dir configs
return function(arg, cb)
  local fname = ""

  -- Determine if we received a buffer number or a filename
  if type(arg) == "number" then
    -- Extract filename from buffer number
    fname = vim.api.nvim_buf_get_name(arg) or ""
  elseif type(arg) == "string" then
    -- Use the string directly as filename
    fname = arg
  end

  -- Resolve the root directory using our strict algorithm
  local root_dir = strict_root_from(fname)

  -- If a callback was provided, invoke it with the resolved root
  -- Use pcall to prevent errors from propagating
  if cb and type(cb) == "function" then
    pcall(cb, root_dir)
  end

  -- Always return the root directory synchronously
  return root_dir
end
