---@module 'lsp.servers.lua_ls.build_library'
--- Build workspace library paths for lua_ls with comprehensive type discovery

--- Build library table including directories AND standalone type files.
--- @param root string Project root directory
--- @return table<string, boolean> Map of library paths
return function(root)
  if not root or type(root) ~= "string" or root == "" then
    return {}
  end

  local library = {}

  -- ===================================================================
  -- THIRD-PARTY LIBRARIES
  -- ===================================================================
  library["${3rd}/luv/library"] = true
  library["${3rd}/busted/library"] = true

  -- ===================================================================
  -- PROJECT TYPE DIRECTORIES AND FILES
  -- ===================================================================
  -- Safe loading of find_type_dirs with fallback
  local type_paths = {}
  local ok, find_type_dirs = pcall(require, "lsp.servers.lua_ls.find_type_dirs")

  if ok and type(find_type_dirs) == "function" then
    local success, result = pcall(find_type_dirs, root, {
      max_results = 200,
      max_depth = 15,
      include_files = true,
    })

    if success and type(result) == "table" then
      type_paths = result
    else
      -- Fallback: Try without include_files option (old API)
      success, result = pcall(find_type_dirs, root, {
        max_results = 200,
        max_depth = 15,
      })
      if success and type(result) == "table" then
        type_paths = result
      end
    end
  end

  for _, path in ipairs(type_paths) do
    library[path] = true
  end

  -- ===================================================================
  -- EXPLICIT PATTERN SEARCH
  -- ===================================================================
  local explicit_patterns = {
    root .. "/lua/@types",
    root .. "/lua/types",
    root .. "/@types",
    root .. "/types",
  }

  for _, pattern in ipairs(explicit_patterns) do
    local stat = (vim.uv or vim.loop).fs_stat(pattern)
    if stat and stat.type == "directory" then
      library[pattern] = true
    end
  end

  -- ===================================================================
  -- ROOT-LEVEL TYPE FILES
  -- ===================================================================
  -- Explicitly check for type files at common locations
  local root_type_files = {
    root .. "/lua/@types.lua",
    root .. "/lua/types.lua",
    root .. "/@types.lua",
    root .. "/types.lua",
  }

  for _, file_path in ipairs(root_type_files) do
    local stat = (vim.uv or vim.loop).fs_stat(file_path)
    if stat and stat.type == "file" then
      library[file_path] = true
    end
  end

  -- ===================================================================
  -- NEOVIM RUNTIME PATHS
  -- ===================================================================
  local runtime_paths = vim.api.nvim_get_runtime_file("", true) or {}
  for _, path in ipairs(runtime_paths) do
    library[path] = true
  end

  -- ===================================================================
  -- LUAROCKS
  -- ===================================================================
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

  -- ===================================================================
  -- LOCAL DEPENDENCIES
  -- ===================================================================
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

  -- ===================================================================
  -- LOCAL DEV PLUGINS (personal *.nvim repos)
  -- ===================================================================
  -- Make the type definitions of lazy-loaded dev plugins resolvable even before
  -- the plugin is loaded (they're only on the runtimepath once their ft/cmd
  -- fires). This gives value completion in the plugin specs — e.g.
  -- `ColorMyAscii.Config` / `Mkdn.Config`, so `preset = "…"` suggests the fence
  -- presets. Guarded by fs_stat, so it's a no-op when the repos aren't present.
  local repos = vim.env.REPOS_DIR
  if type(repos) == "string" and repos ~= "" then
    repos = repos:gsub("\\", "/")
    local dev_type_dirs = {
      repos .. "/color_my_ascii.nvim/lua",
      repos .. "/markdown.nvim/lua",
    }
    for _, path in ipairs(dev_type_dirs) do
      local stat = (vim.uv or vim.loop).fs_stat(path)
      if stat and stat.type == "directory" then
        library[path] = true
      end
    end
  end

  return library
end
