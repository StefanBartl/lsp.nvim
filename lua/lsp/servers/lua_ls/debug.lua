---@module 'lsp.servers.lua_ls.debug'
--- Utilities for debugging LuaLS setup: root detection and workspace library inspection.

-- Use the appropriate async I/O library (vim.uv preferred, vim.loop fallback)
local notify = require("lib.nvim.notify").create("[lsp.servers.lua_ls.debug]")

local uv = vim.uv or vim.loop

-- Import filesystem helper utilities
local is_subpath = require("lib.nvim.fs.is_subpath")
local find_upward_dir = require("lib.nvim.fs.find_upward_dir")

---@class LuaLsDebug
local M = {}

-- ===================================================================
-- ROOT RESOLUTION
-- ===================================================================

---@param start_dir? string Starting directory path (optional)
---@return string|nil Detected root directory or nil if none found
local function strict_root(start_dir)
  -- Determine starting directory: use provided dir or fall back to current working directory
  local dir = start_dir or (uv.cwd and uv.cwd()) or vim.fn.getcwd()

  -- Bail early if no valid directory could be determined
  if not dir or dir == "" then
    return nil
  end

  -- Step 1: Check for version control system roots (.git, .hg, .svn)
  -- These are strong indicators of a project boundary
  local vcs_root = find_upward_dir({ ".git", ".hg", ".svn" }, dir)
  if vcs_root then
    return vcs_root
  end

  -- Step 2: Check for Lua-specific project markers
  -- These config files typically sit at the project root
  local lua_markers =
    find_upward_dir({ ".luarc.json", ".neoconf.json", "selene.toml", "stylua.toml" }, dir)
  if lua_markers then
    return lua_markers
  end

  -- Step 3: Check if we're inside Neovim's config directory
  -- This is common when editing init.lua or plugin files
  local stdconfig = vim.fn.stdpath("config")
  if is_subpath(dir, stdconfig) then
    return stdconfig
  end

  -- Step 4: Fallback to the starting directory itself
  -- This ensures single-file editing still works
  return dir
end

--- Get root directory for a specific buffer
---@param bufnr? integer Buffer number (optional, defaults to current buffer)
---@return string|nil Root directory path or nil
function M.root_for_buf(bufnr)
  local fname = ""

  -- Get the filename for the specified buffer
  if type(bufnr) == "number" then
    fname = vim.api.nvim_buf_get_name(bufnr) or ""
  end

  -- Extract directory from filename, or use nil to trigger CWD fallback
  return strict_root(fname ~= "" and vim.fs.dirname(fname) or nil)
end

--- Debug helper: Get the root for the current working directory
---@nodiscard
---@return string|nil Root directory path
function M.debug_root()
  return strict_root()
end

-- ===================================================================
-- WORKSPACE LIBRARY
-- ===================================================================

--- Build workspace library paths for a given root directory
--- This shows which directories lua_ls will scan for type definitions
---@param root? string Root directory (optional, defaults to detected root)
---@return string[] Array of library paths
function M.debug_library(root)
  -- Use provided root or detect from CWD
  root = root or strict_root()
  if not root then
    return {}
  end

  -- Try to load the build_library module (may not exist in all configs)
  local ok, build_library = pcall(require, "lsp.servers.lua_ls.build_library")
  if not ok or type(build_library) ~= "function" then
    return {}
  end

  -- Call build_library with the root to get project-specific libraries
  return build_library(root)
end

-- ===================================================================
-- UTILITIES
-- ===================================================================

--- Print comprehensive debug information to Neovim's message area
--- Useful for troubleshooting lua_ls configuration issues
---@param bufnr? integer
---@return nil
function M.print_debug_info(bufnr)
  local root = M.root_for_buf(bufnr)

  if not root then
    notify.warn("No root directory detected")
    return
  end

  -- Get full library including type files
  local ok, build_library = pcall(require, "lsp.servers.lua_ls.build_library")
  if not ok then
    notify.error("Could not load build_library")
    return
  end

  local library = build_library(root)

  -- Separate directories and files for clarity
  local dirs = {}
  local files = {}

  for path, _ in pairs(library) do
    local stat = (vim.uv or vim.loop).fs_stat(path)
    if stat then
      if stat.type == "directory" then
        dirs[#dirs + 1] = path
      elseif stat.type == "file" then
        files[#files + 1] = path
      end
    end
  end

  notify.info("=== LuaLS Debug Info ===")
  notify.info("Root: " .. root)
  notify.info("\nType Directories (" .. #dirs .. "):")
  for _, dir in ipairs(dirs) do
    notify.info("  " .. dir)
  end
  notify.info("\nType Files (" .. #files .. "):")
  for _, file in ipairs(files) do
    notify.info("  " .. file)
  end
end

return M
