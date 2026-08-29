---@module 'lsp.servers.lua_ls.reload'
--- Manual library reload command for lua_ls
--- Use when @types are not detected automatically

local notify = require("lib.nvim.notify").create("[lsp.servers.lua_ls.reload]")
local usercmd = require("lib.nvim.bindings.usercmd")
local Autocmd = require("lib.nvim.bindings.autocmd")

local M = {}

--- Start the lua_ls server config (as registered via vim.lsp.config) and
--- attach it to the given buffer.
---@param bufnr integer
---@return boolean success
local function start_lua_ls(bufnr)
  if type(vim.lsp.config) ~= "table" then
    return false
  end

  local config_list = vim.lsp.config.get and vim.lsp.config.get() or {}
  local server_config = nil
  for _, cfg in pairs(config_list) do
    if cfg.name == "lua_ls" then
      server_config = cfg
      break
    end
  end
  if not server_config then
    return false
  end

  -- The server table is assembled by `lsp.servers.*`, not written here;
  -- LuaLS matches it against vim.lsp.start's own meta, which wants `cmd`
  -- even when the resolved config supplies it dynamically.
  ---@diagnostic disable-next-line: missing-fields
  local ok, client_id = pcall(vim.lsp.start, server_config, { bufnr = bufnr })
  return ok and client_id ~= nil
end

--- Restart every attached lua_ls client so `root_dir` is recomputed for the
--- currently open buffers. Used after the root-scope switch changes
--- (see lsp.core.root_scope / lsp.core.root_scope_picker, <leader>lsp).
---@return nil
function M.recompute_root()
  local clients = vim.lsp.get_clients({ name = "lua_ls" })
  if #clients == 0 then
    return
  end

  local bufs = {}
  for _, c in ipairs(clients) do
    for bufnr in pairs(c.attached_buffers or {}) do
      bufs[bufnr] = true
    end
  end

  for _, c in ipairs(clients) do
    c:stop(true)
  end

  vim.defer_fn(function()
    local restarted = 0
    for bufnr in pairs(bufs) do
      if vim.api.nvim_buf_is_valid(bufnr) and start_lua_ls(bufnr) then
        restarted = restarted + 1
      end
    end
    notify.info(string.format("lua_ls root recomputed (%d buffer(s))", restarted))
  end, 100)
end

--- Reload lua_ls workspace library for current buffer
---@return boolean success
function M.reload_library()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Find lua_ls client
  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "lua_ls" })
  if #clients == 0 then
    notify.warn("lua_ls not attached to current buffer")
    return false
  end

  local client = clients[1]

  -- Get current root
  local root = client.config.root_dir
  if not root then
    notify.error("Could not determine lua_ls root directory")
    return false
  end

  -- Rebuild library
  local ok, build_library = pcall(require, "lsp.servers.lua_ls.build_library")
  if not ok then
    notify.error("Could not load build_library module")
    return false
  end

  local library = build_library(root)
  local count = 0
  for _ in pairs(library) do
    count = count + 1
  end

  -- Update client settings
  client.config.settings.Lua.workspace.library = library

  -- Notify client of configuration change
  client.notify("workspace/didChangeConfiguration", {
    settings = client.config.settings,
  })

  notify.info(string.format("Reloaded lua_ls workspace library: %d paths", count))

  return true
end

--- Setup user command
function M.setup()
  usercmd.create("LuaLsReloadLibrary", function()
    M.reload_library()
  end, {
    desc = "[lsp.lua_ls] Reload workspace library (useful when @types not detected)",
  })

  usercmd.create("LuaLsInspectLibrary", function()
    local debug = require("lsp.servers.lua_ls.debug")
    debug.print_debug_info(vim.api.nvim_get_current_buf())
  end, {
    desc = "[lsp.lua_ls] Inspect current workspace library configuration",
  })

  usercmd.create("LuaLsSetProfile", function(opts)
    local profile = opts.args
    if profile == "" then
      profile = "normal"
    end

    vim.env.LUA_LS_PROFILE = profile
    M.reload_library()

    notify.info(string.format("Switched to profile: %s - Reloading...", profile))
  end, {
    nargs = "?",
    complete = function()
      return { "minimal", "normal", "full" }
    end,
    desc = "[lsp.lua_ls] Set library profile (minimal/normal/full)",
  })

  -- Recompute root_dir for open buffers whenever <leader>lsp switches scope.
  --
  -- The cleared augroup is load-bearing, not decoration: `setup()` has no
  -- idempotency guard and runs again on every config reload. The user commands
  -- above survive that because `usercmd.create` defaults to `force = true`, but
  -- a groupless autocmd has no such overwrite -- it would stack, and after N
  -- reloads one scope switch would run `recompute_root()` N times.
  Autocmd.create("User", function()
    M.recompute_root()
  end, {
    group = Autocmd.group("LspLuaLsRootScope", true),
    pattern = "LspRootScopeChanged",
    desc = "[lsp.lua_ls] Recompute root_dir on root-scope change",
  })
end

return M
