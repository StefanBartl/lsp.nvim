---@module 'lsp.servers.lua_ls.rootresolver'
--- Root resolver for lua_ls.
---
--- Only the *algorithm* lives here. The wrapper around it -- buffer number or
--- filename, unnamed-buffer fallback, the optional callback the `vim.lsp`
--- root_dir contract allows -- comes from
--- `lib.nvim.fs.polymorphic_rootresolver` via its `resolve` hook, because that
--- part is identical in every resolver and used to be copied (roadmap finding
--- B8).
---
--- The algorithm is not: lua_ls needs a strict project boundary for its
--- workspace library, honours the global cwd/git/path scope switch, and treats
--- the Neovim config directory as a root of its own -- none of which a marker
--- list can express, which is why the hook exists rather than a longer
--- `markers` array.
---
---@see lsp.core.root_scope

local rootresolver = require("lib.nvim.fs.polymorphic_rootresolver")
-- Import filesystem helper to check if a path is contained within another
local is_subpath = require("lib.nvim.fs.is_subpath")
-- Global cwd/git/path switch (see lsp.core.root_scope_picker, <leader>lsp)
local root_scope = require("lsp.core.root_scope")

--- Determine a strict root directory from a filename or use sensible fallbacks.
---
--- Algorithm Steps:
--- 1. If the start dir is under Neovim's stdpath("config"), return that config path.
--- 3. If a VCS root (git/hg/svn) is found upward, return it.
--- 4. If certain Lua/tool config markers are found upward, return the marker's dirname.
--- 5. Otherwise return the start dir itself.
---
--- This ensures lua_ls always has a well-defined project boundary, which is crucial
--- for proper workspace library configuration and performance.
---
--- @param dir string starting directory, already normalized by the caller
--- @return string|nil root directory, or nil to fall back to `dir`
local function strict_root_from(dir)
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

--- The resolver `lsp.servers.lua_ls` hands to `root_dir`.
---
--- `include_stdpath_config = false` because `strict_root_from` does that check
--- itself, and does it *first* -- before the scope switch and the marker
--- search, not as a correction afterwards.
---@type fun(arg: string|integer, cb?: fun(root: string)): string
return rootresolver({
  include_stdpath_config = false,
  resolve = strict_root_from,
})
