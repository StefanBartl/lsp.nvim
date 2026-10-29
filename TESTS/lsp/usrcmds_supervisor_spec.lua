--- Wiring of `:Lsp stop` and `:Lsp restart` to `lsp.core.supervisor`.
---
--- supervisor_spec.lua and recovery_spec.lua test the supervisor's functions,
--- usercmds_impl_spec.lua calls `lsp.usercmds.stop/restart.execute()` directly.
--- This spec runs the real Ex commands through the `:Lsp` verb and spies on the
--- supervisor boundary, so a route that stops reaching the supervisor fails:
---
---  * every deliberate stop is declared with `supervisor.expect_stop` before the
---    client goes down (otherwise the SIGTERM of a force-stop reads as a crash
---    and the supervisor restarts what the user just stopped);
---  * the start half of a restart goes through `supervisor.start` (the shared
---    attempt counter and config lookup), not `vim.lsp.start`/`enable`.
---
--- Clients are in-process stub servers (`cmd` is a function), as in
--- usercmds_impl_spec.lua: no process is spawned. `supervisor.start` is a spy
--- that does not start anything, so only what the command asked for is seen.

local supervisor = require("lsp.core.supervisor")
require("lsp.bindings.usrcmds").setup()

describe(":Lsp stop / :Lsp restart -> lsp.core.supervisor", function()
  ---@type { expect_stop: any[], start: { name: string, bufnr: integer }[] }
  local calls
  local original = {}
  ---@type integer[]
  local spawned = {}

  ---@return fun(dispatchers: table): table
  local function stub_server()
    return function(dispatchers)
      local closing = false
      local function close(signal)
        if not closing then
          closing = true
          vim.schedule(function()
            dispatchers.on_exit(0, signal)
          end)
        end
      end
      return {
        request = function(method, _, callback)
          if method == "initialize" then
            callback(nil, { capabilities = {} })
          elseif method == "shutdown" then
            callback(nil, nil)
          end
          return true, 1
        end,
        notify = function(method)
          if method == "exit" then
            close(0)
          end
          return true
        end,
        is_closing = function()
          return closing
        end,
        terminate = function()
          close(15)
        end,
      }
    end
  end

  ---@param name string
  ---@param bufnr integer
  ---@return integer client_id
  local function attach(name, bufnr)
    local id = assert(vim.lsp.start({ name = name, cmd = stub_server(), root_dir = vim.uv.cwd() }, {
      bufnr = bufnr,
      reuse_client = function()
        return false
      end,
    }))
    spawned[#spawned + 1] = id
    return id
  end

  ---@param ms integer
  ---@param cond (fun(): boolean)|nil
  local function settle(ms, cond)
    vim.wait(ms, cond or function()
      return false
    end, 20)
  end

  ---@param bufnr integer
  ---@return integer
  local function attached(bufnr)
    return #vim.lsp.get_clients({ bufnr = bufnr })
  end

  ---@return integer bufnr
  local function current_buffer()
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
  end

  before_each(function()
    calls = { expect_stop = {}, start = {} }
    -- silenced for the whole case: restart reports from a deferred callback
    original.notify = vim.notify
    vim.notify = function() end
    original.expect_stop = supervisor.expect_stop
    original.start = supervisor.start
    supervisor.expect_stop = function(ids)
      calls.expect_stop[#calls.expect_stop + 1] = ids
      return original.expect_stop(ids)
    end
    supervisor.start = function(name, bufnr)
      calls.start[#calls.start + 1] = { name = name, bufnr = bufnr }
      return true
    end
  end)

  after_each(function()
    supervisor.expect_stop = original.expect_stop
    supervisor.start = original.start
    for _, id in ipairs(spawned) do
      local client = vim.lsp.get_client_by_id(id)
      if client then
        pcall(function()
          client:stop(true)
        end)
      end
    end
    spawned = {}
    settle(100)
    vim.notify = original.notify
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(b) == "" and b ~= vim.api.nvim_get_current_buf() then
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end
  end)

  it(":Lsp stop <name> declares the stop to the supervisor and stops the client", function()
    local bufnr = current_buffer()
    local id = attach("spec_sup_a", bufnr)

    vim.cmd("Lsp stop spec_sup_a")
    assert.are.same({ id }, calls.expect_stop, "expect_stop(client id) before the stop")
    settle(2000, function()
      return attached(bufnr) == 0
    end)
    assert.are.equal(0, attached(bufnr), "the client went down")
    assert.are.same({}, calls.start, "a stop starts nothing")
  end)

  it(":Lsp restart <name> declares the stop and starts the server via supervisor.start", function()
    local bufnr = current_buffer()
    local id = attach("spec_sup_a", bufnr)

    vim.cmd("Lsp restart spec_sup_a")
    assert.are.same({ id }, calls.expect_stop, "expect_stop(client id) before the stop")
    settle(2000, function()
      return #calls.start > 0
    end)
    assert.are.same({ { name = "spec_sup_a", bufnr = bufnr } }, calls.start)
  end)

  it(":Lsp restart (all) declares every client and starts each name once", function()
    local bufnr = current_buffer()
    local a = attach("spec_sup_a", bufnr)
    local b = attach("spec_sup_b", bufnr)

    vim.cmd("Lsp restart")
    assert.are.equal(1, #calls.expect_stop, "one declaration covering all clients")
    local ids = calls.expect_stop[1]
    table.sort(ids)
    assert.are.same({ a, b }, ids)
    settle(2000, function()
      return #calls.start >= 2
    end)
    local names = vim.tbl_map(function(c)
      return c.name
    end, calls.start)
    table.sort(names)
    assert.are.same({ "spec_sup_a", "spec_sup_b" }, names)
  end)
end)
