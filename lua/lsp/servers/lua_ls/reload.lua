---@module 'lsp.servers.lua_ls.reload'
--- Manual library reload command for lua_ls
--- Use when @types are not detected automatically

local notify = require("lib.nvim.notify").create("[lsp.servers.lua_ls.reload]")
local usercmd = require("lib.nvim.bindings.usercmd")
local Autocmd = require("lib.nvim.bindings.autocmd")

local M = {}

--- Start lua_ls and attach it to the given buffer.
---
--- Through `lsp.core.supervisor`, which is the only place that starts a
--- registered server correctly. This used to do it here, and got both halves
--- wrong:
---
--- * it looked the config up with `vim.lsp.config.get()`, which does not exist
---   -- `vim.lsp.config` is a table with an `__index` resolver -- so the list
---   was always empty, no config was ever found, and this function could only
---   ever return `false` (roadmap B16, a third copy of it);
--- * and `vim.lsp.start` does not resolve a function-valued `root_dir`, which
---   is exactly what `lua_ls` registers. Even with the lookup fixed it would
---   have started in single-file mode -- in the function whose whole purpose
---   is to recompute the root.
---
--- What that cost: `recompute_root` stops every `lua_ls` client and then calls
--- this to bring them back. It never could, so one `<leader>lsp` scope switch
--- killed `lua_ls` for the session and said "root recomputed (0 buffer(s))"
--- about it. Measured: one client before, zero after.
---@param bufnr integer
---@return boolean success
local function start_lua_ls(bufnr)
  local ok, supervisor = pcall(require, "lsp.core.supervisor")
  if not ok or type(supervisor.start) ~= "function" then
    return false
  end
  return supervisor.start("lua_ls", bufnr)
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
  ---@type integer[]
  local ids = {}
  for _, c in ipairs(clients) do
    ids[#ids + 1] = c.id
    for bufnr in pairs(c.attached_buffers or {}) do
      bufs[bufnr] = true
    end
  end

  -- Declared before stopping, the way `:Lsp stop`, `:Lsp restart` and
  -- `:Lsp recover` all do it. `on_exit` cannot tell a wanted stop from a
  -- crash, so intent is declared rather than guessed -- and this was the one
  -- deliberate-stop site in the plugin that never declared it. A scope switch
  -- therefore logged "lua_ls exited with code 1, signal 15; restarting in
  -- 1000ms (attempt 1/4)" at the user and raced the supervisor's own backoff
  -- restart against the one below.
  local ok_supervisor, supervisor = pcall(require, "lsp.core.supervisor")
  if ok_supervisor and type(supervisor.expect_stop) == "function" then
    supervisor.expect_stop(ids)
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

  -- Update client settings. `settings` is a plain table as far as the type
  -- system is concerned, so the lua_ls-specific path is walked through a
  -- local rather than annotated key by key.
  ---@type table
  local settings = client.config.settings
  settings.Lua.workspace.library = library

  -- Notify client of configuration change.
  --
  -- `notify` is a method: `client.notify(method, params)` passed the method
  -- name as `self`, so this call raised inside `Client:notify` the moment it
  -- ran -- the settings table was updated and the server never told.
  client:notify("workspace/didChangeConfiguration", {
    settings = settings,
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
