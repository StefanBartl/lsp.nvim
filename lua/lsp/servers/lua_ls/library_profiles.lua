---@module 'lsp.servers.lua_ls.library_profiles'
--- Different library profiles for lua_ls performance tuning

local M = {}

---@alias LibraryProfile "minimal"|"normal"|"full"

---@class LibraryProfileConfig
---@field max_results integer
---@field max_depth integer
---@field include_files boolean
---@field include_luarocks boolean
---@field include_local_deps boolean

---@type table<LibraryProfile, LibraryProfileConfig>
local PROFILES = {
  -- Minimal: Nur Third-Party + explizite Type-Dirs
  minimal = {
    max_results = 50,
    max_depth = 5,
    include_files = false,
    include_luarocks = false,
    include_local_deps = false,
  },

  -- Normal: Standard-Setup (schnell genug für tägliche Arbeit)
  normal = {
    max_results = 100,
    max_depth = 10,
    include_files = true,
    include_luarocks = false,
    include_local_deps = true,
  },

  -- Full: Komplett (für Debugging/Plugin-Development)
  full = {
    max_results = 200,
    max_depth = 15,
    include_files = true,
    include_luarocks = true,
    include_local_deps = true,
  },
}

--- Get current profile from environment or default to "normal"
---@return LibraryProfile
function M.get_active_profile()
  local profile = vim.env.LUA_LS_PROFILE or "normal"
  if not PROFILES[profile] then
    return "normal"
  end
  return profile
end

--- Get profile configuration
---@param profile? LibraryProfile
---@return LibraryProfileConfig
function M.get_config(profile)
  profile = profile or M.get_active_profile()
  return PROFILES[profile]
end

--- Build only the part of the library that is cheap to compute: the `${3rd}`
--- meta definitions and Neovim's own runtime paths. Measured at 0.0ms, versus
--- ~157ms for the full `build_library` -- all of that difference is
--- `find_type_dirs`' filesystem scan.
---
--- This is the part that actually matters for editing a Neovim config: the
--- runtime paths are what give lua_ls the `vim.*` API types. `find_type_dirs`
--- searches BELOW the project root, so everything it finds is already inside
--- the workspace and gets indexed anyway -- declaring those paths as `library`
--- would only exempt them from diagnostics (`diagnostics.libraryFiles` is
--- "Disable" in .luarc.json), which does not justify a 197ms scan on the
--- startup path.
---
--- Returned as an array, which is what lua_ls' `workspace.library` expects.
---@return string[]
function M.build_runtime_library()
  local library = {
    "${3rd}/luv/library",
    "${3rd}/busted/library",
  }

  -- Only $VIMRUNTIME/lua, deliberately NOT every runtimepath entry. The first
  -- version of this handed lua_ls all 52 rtp paths -- which is the whole
  -- Neovim runtime *plus every loaded plugin* -- and lua_ls then sat there
  -- parsing them: a probe file got no diagnostics at all within 60s, where the
  -- same file reported `unused-local` before. $VIMRUNTIME/lua is what carries
  -- the `vim.*` meta definitions, and lazydev (enabled in lsp/core/attach)
  -- pulls in plugin types on demand, which is the whole point of it.
  if vim.env.VIMRUNTIME and vim.env.VIMRUNTIME ~= "" then
    library[#library + 1] = vim.env.VIMRUNTIME .. "/lua"
  end

  return library
end

--- Build library with active profile
---@param root string
---@param profile? LibraryProfile
---@return table<string, boolean>
function M.build_library(root, profile)
  local config = M.get_config(profile)
  local library = {}

  -- Always include third-party
  library["${3rd}/luv/library"] = true
  library["${3rd}/busted/library"] = true

  -- Type directories (with profile limits)
  local ok, find_type_dirs = pcall(require, "lsp.servers.lua_ls.find_type_dirs")
  if ok then
    local success, type_paths = pcall(find_type_dirs, root, {
      max_results = config.max_results,
      max_depth = config.max_depth,
      include_files = config.include_files,
    })
    if success and type(type_paths) == "table" then
      for _, path in ipairs(type_paths) do
        library[path] = true
      end
    end
  end

  -- Neovim runtime (always)
  local runtime_paths = vim.api.nvim_get_runtime_file("", true) or {}
  for _, path in ipairs(runtime_paths) do
    library[path] = true
  end

  -- LuaRocks (optional)
  if config.include_luarocks then
    local home = vim.fn.expand("~")
    local luarocks_paths = {
      home .. "/.luarocks/share/lua/5.1",
      home .. "/.luarocks/share/lua/5.4",
      "/usr/local/share/lua/5.1",
      "/usr/local/share/lua/5.4",
    }
    for _, path in ipairs(luarocks_paths) do
      local stat = (vim.uv or vim.loop).fs_stat(path)
      if stat and stat.type == "directory" then
        library[path] = true
      end
    end
  end

  -- Local dependencies (optional)
  if config.include_local_deps then
    local local_dep_dirs = {
      root .. "/lua_modules/share/lua/5.1",
      root .. "/lua_modules/share/lua/5.4",
      root .. "/deps",
      root .. "/vendor",
    }
    for _, path in ipairs(local_dep_dirs) do
      local stat = (vim.uv or vim.loop).fs_stat(path)
      if stat and stat.type == "directory" then
        library[path] = true
      end
    end
  end

  return library
end

return M
