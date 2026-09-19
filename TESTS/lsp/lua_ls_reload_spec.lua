--- Covers `lsp.servers.lua_ls.reload.recompute_root`, the handler behind the
--- root-scope switch (`<leader>lsp` -> `LspRootScopeChanged`).
---
--- It stops every `lua_ls` client and starts them again so `root_dir` is
--- recomputed for the open buffers. Both halves were broken, and the pair was
--- destructive: it stopped the clients and could not bring them back, so one
--- scope switch killed `lua_ls` for the session while reporting
--- "lua_ls root recomputed (0 buffer(s))". Measured against a real client:
--- one before, zero after.
---
--- * The config lookup went through `vim.lsp.config.get()`, which does not
---   exist -- `vim.lsp.config` is a table with an `__index` resolver -- so no
---   config was ever found and the start could only return `false`. That is
---   roadmap B16, whose third copy this was.
--- * And `vim.lsp.start` does not resolve a function-valued `root_dir`, which
---   is exactly what `lua_ls` registers (`servers/lua_ls/rootresolver`). Even
---   with the lookup fixed it would have come back in single-file mode -- in
---   the function whose whole purpose is to recompute the root.
---
--- Both are `lsp.core.supervisor.start`'s job, so it does them now.
---
--- The stop was also never declared. `on_exit` cannot tell a wanted stop from
--- a crash, which is why every other deliberate-stop site in the plugin calls
--- `supervisor.expect_stop` first; this one did not, so a scope switch logged
--- "lua_ls exited with code 1, signal 15; restarting in 1000ms (attempt 1/4)"
--- at the user and raced the supervisor's backoff restart against its own.

describe("lsp.servers.lua_ls.reload", function()
  local saved

  before_each(function()
    saved = {
      get_clients = vim.lsp.get_clients,
      supervisor = package.loaded["lsp.core.supervisor"],
    }
  end)

  after_each(function()
    vim.lsp.get_clients = saved.get_clients
    package.loaded["lsp.core.supervisor"] = saved.supervisor
    package.loaded["lsp.servers.lua_ls.reload"] = nil
  end)

  --- One attached `lua_ls`, plus a supervisor double that records what it is
  --- asked to do.
  ---@return table calls
  local function stub(bufnr)
    local calls = { expect_stop = {}, started = {}, stopped = 0 }

    vim.lsp.get_clients = function()
      return {
        {
          id = 11,
          name = "lua_ls",
          attached_buffers = { [bufnr] = true },
          stop = function()
            calls.stopped = calls.stopped + 1
          end,
        },
      }
    end

    package.loaded["lsp.core.supervisor"] = {
      expect_stop = function(ids)
        calls.expect_stop[#calls.expect_stop + 1] = ids
      end,
      start = function(name, buf)
        calls.started[#calls.started + 1] = { name = name, bufnr = buf }
        return true
      end,
    }

    return calls
  end

  it("starts the clients it stopped, through the supervisor", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local calls = stub(bufnr)

    require("lsp.servers.lua_ls.reload").recompute_root()
    -- `recompute_root` restarts on a `defer_fn(100)`.
    vim.wait(2000, function()
      return #calls.started > 0
    end, 20)

    assert.are.equal(1, calls.stopped)
    assert.are.equal(1, #calls.started, "the client was stopped and never started again")
    assert.are.equal("lua_ls", calls.started[1].name)
    assert.are.equal(bufnr, calls.started[1].bufnr)
  end)

  it("declares the stop so the supervisor does not read it as a crash", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local calls = stub(bufnr)

    require("lsp.servers.lua_ls.reload").recompute_root()
    vim.wait(2000, function()
      return #calls.started > 0
    end, 20)

    assert.are.equal(1, #calls.expect_stop, "the deliberate stop was not declared")
    assert.are.same({ 11 }, calls.expect_stop[1])
  end)
end)

--- `:LuaLsSetProfile` used to set `LUA_LS_PROFILE` and echo it straight back
--- ("Switched to profile: %s") no matter what was typed, while the reload it
--- ran (`build_library.lua`) never read that variable at all -- a provably
--- inert env var, confirmed by a real reload. Now that `build_library.lua`
--- does read it (see `servers_lua_ls_spec.lua`), the command's own reporting
--- is worth pinning down too: an unrecognized name must not be echoed back
--- as if it took effect.
describe("lsp.servers.lua_ls.reload: LuaLsSetProfile (LLS-31)", function()
  local saved

  before_each(function()
    saved = {
      get_clients = vim.lsp.get_clients,
      notify = vim.notify,
      env = vim.env.LUA_LS_PROFILE,
    }
  end)

  after_each(function()
    vim.lsp.get_clients = saved.get_clients
    vim.notify = saved.notify
    vim.env.LUA_LS_PROFILE = saved.env
    package.loaded["lsp.servers.lua_ls.reload"] = nil
  end)

  --- One attached `lua_ls` client, real enough for `reload_library` to run
  --- its course against (a nonexistent root scans to nothing, harmlessly).
  ---@return string[] notified
  local function stub_client()
    local notified = {}
    vim.lsp.get_clients = function()
      return {
        {
          config = {
            root_dir = "/tmp/lua_ls_set_profile_spec",
            settings = { Lua = { workspace = {} } },
          },
          notify = function() end,
        },
      }
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg)
      notified[#notified + 1] = tostring(msg)
    end
    return notified
  end

  it(
    "falls back to 'normal' and warns on an unrecognized profile, instead of echoing it back",
    function()
      local notified = stub_client()
      require("lsp.servers.lua_ls.reload").setup()

      vim.cmd("LuaLsSetProfile ful")

      assert.are.equal("normal", vim.env.LUA_LS_PROFILE)
      local all = table.concat(notified, "\n")
      assert.is_truthy(all:match("Unknown profile 'ful'"), all)
      assert.is_truthy(all:match("Switched to profile: normal"), all)
    end
  )

  it("sets the env var a recognized profile name resolves to", function()
    stub_client()
    require("lsp.servers.lua_ls.reload").setup()

    vim.cmd("LuaLsSetProfile minimal")

    assert.are.equal("minimal", vim.env.LUA_LS_PROFILE)
  end)
end)
