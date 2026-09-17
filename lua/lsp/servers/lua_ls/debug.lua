---@module 'lsp.servers.lua_ls.debug'
--- Utilities for debugging LuaLS setup: root detection and workspace library inspection.

local notify = require("lib.nvim.notify").create("[lsp.servers.lua_ls.debug]")

-- The resolver `lua_ls` is actually registered with. This module used to carry
-- its own copy of the algorithm, and the copy had drifted: it tried VCS
-- markers first and the `stdpath("config")` check only as step 3, where
-- `rootresolver` does the config check *first* and deliberately says so.
--
-- Measured with `stdpath("config")` pointed at a fixture holding a nested repo
-- at `<config>/lua/vendor/plug/.git`, on a buffer for
-- `<config>/lua/vendor/plug/a.lua`:
--
--   rootresolver      -> <config>
--   debug.root_for_buf -> <config>/lua/vendor/plug
--
-- The README sends people here to "check whether the root was detected
-- correctly", so a second answer is worse than no answer. The copy also knew
-- nothing about the `<leader>lsp` root-scope switch, which `rootresolver`
-- honours -- under scope "cwd" every root printed here was wrong as well.
local rootresolver = require("lsp.servers.lua_ls.rootresolver")

---@class LuaLsDebug
local M = {}

-- ===================================================================
-- ROOT RESOLUTION
-- ===================================================================

--- Get root directory for a specific buffer, exactly as the server resolves it.
---@param bufnr? integer Buffer number (optional, defaults to current buffer)
---@return string|nil Root directory path or nil
function M.root_for_buf(bufnr)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    bufnr = vim.api.nvim_get_current_buf()
  end

  local ok, root = pcall(rootresolver, bufnr)
  if not ok then
    return nil
  end
  return root
end

--- Debug helper: Get the root for the current buffer.
---
--- Named `debug_root` for the buffer-less caller; it goes through the same
--- resolver, so an unnamed buffer lands on the resolver's own fallback rather
--- than on a second one invented here.
---@nodiscard
---@return string|nil Root directory path
function M.debug_root()
  return M.root_for_buf()
end

-- ===================================================================
-- WORKSPACE LIBRARY
-- ===================================================================

--- Build workspace library paths for a given root directory
--- This shows which directories lua_ls will scan for type definitions
---
--- Returns the array this has always been annotated (and documented in the
--- README) to return. `build_library` hands back a `{ [path] = true }` map, and
--- this used to pass that straight through: measured on this repo, the result
--- had 22 keys and an array length of 0, so `#libs` was 0 and `ipairs(libs)`
--- yielded nothing -- for a helper whose only job is to list paths for a human.
--- Sorted, because a debug dump that reorders itself between runs cannot be
--- diffed.
---@param root? string Root directory (optional, defaults to the detected root)
---@return string[] Array of library paths
function M.debug_library(root)
  -- Use provided root or resolve the current buffer's
  root = root or M.debug_root()
  if not root then
    return {}
  end

  -- Try to load the build_library module (may not exist in all configs)
  local ok, build_library = pcall(require, "lsp.servers.lua_ls.build_library")
  if not ok or type(build_library) ~= "function" then
    return {}
  end

  local built = build_library(root)
  if type(built) ~= "table" then
    return {}
  end

  local paths = {}
  for path in pairs(built) do
    paths[#paths + 1] = path
  end
  table.sort(paths)
  return paths
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

  -- Through `debug_library`, so the dump and the programmatic accessor can
  -- never disagree, and so the order is stable between runs.
  local library = M.debug_library(root)
  if #library == 0 then
    notify.error("Could not build a library for " .. root)
    return
  end

  -- Separate directories and files for clarity. The third bucket is the point:
  -- an entry that `fs_stat` cannot see used to be dropped with no trace, and
  -- three of this repo's 22 entries are exactly that -- `${3rd}/luv/library`,
  -- `${3rd}/busted/library`, `${3rd}/luassert/library`, placeholders the
  -- server expands itself. Printing "17 directories, 2 files" for a 22-entry
  -- library is how a missing `${3rd}` entry stays invisible, which is the one
  -- thing this dump exists to catch.
  local dirs = {}
  local files = {}
  local unresolved = {}

  for _, path in ipairs(library) do
    local stat = (vim.uv or vim.loop).fs_stat(path)
    if stat and stat.type == "directory" then
      dirs[#dirs + 1] = path
    elseif stat and stat.type == "file" then
      files[#files + 1] = path
    else
      unresolved[#unresolved + 1] = path
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
  notify.info("\nNot on disk -- server-expanded or stale (" .. #unresolved .. "):")
  for _, path in ipairs(unresolved) do
    notify.info("  " .. path)
  end
end

return M
