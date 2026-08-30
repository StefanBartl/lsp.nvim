--- Covers `lsp.usercmds.recovery`: that it starts servers through
--- `supervisor.start` rather than `vim.lsp.enable`, and the two guards around
--- the attempt counter it shares with the supervisor.
---
--- Both guards are the kind that fail silently. `vim.lsp.enable` only arms an
--- autocommand, so using it after a force-restart produced a command that
--- stopped a server, retried three times, and reported "Try :edit" -- while
--- looking exactly like a server that refuses to start. And because the
--- counter is shared, a server the supervisor gave up on arrives here past
--- every cap, so `:Lsp recover` refused to make a single attempt in precisely
--- the situation it exists for.
---
--- The supervisor is stubbed rather than loaded: what is under test is which
--- function `recovery` reaches for and in what order, not whether
--- `vim.lsp.start` works -- there is no language server in the harness.

describe("lsp.usercmds.recovery", function()
  --- Load `recovery` against a fresh stub supervisor and return both.
  ---@param overrides table|nil # Fields to merge over the stub.
  ---@return table recovery, table supervisor
  local function reload(overrides)
    local calls = { started = {}, reset = {} }
    local attempts = {}

    local stub = vim.tbl_extend("force", {
      calls = calls,
      attempts = function(name)
        return attempts[name] or 0
      end,
      note_attempt = function(name)
        attempts[name] = (attempts[name] or 0) + 1
        return attempts[name]
      end,
      note_error = function(name, msg)
        calls.last_error = { name = name, msg = msg }
      end,
      last_error = function()
        return calls.last_error and calls.last_error.msg or nil
      end,
      reset = function(name)
        attempts[name] = nil
        calls.reset[#calls.reset + 1] = name
      end,
      expect_stop = function() end,
      config_for = function(name)
        return name == "known" and { cmd = { "true" }, name = name } or nil
      end,
      start = function(name, bufnr)
        calls.started[#calls.started + 1] = { name = name, bufnr = bufnr }
        return true
      end,
      -- Test-only handle so a case can pre-load the counter.
      _set_attempts = function(name, n)
        attempts[name] = n
      end,
    }, overrides or {})

    package.loaded["lsp.core.supervisor"] = stub
    package.loaded["lsp.usercmds.recovery"] = nil
    return (require("lsp.usercmds.recovery")), stub
  end

  after_each(function()
    package.loaded["lsp.usercmds.recovery"] = nil
    package.loaded["lsp.core.supervisor"] = nil
  end)

  describe("retry_start", function()
    -- The bug this file exists for: `vim.lsp.enable` arms an autocommand and
    -- never touches a buffer that is already open, which is the only situation
    -- a retry is ever in.
    it("starts through the supervisor, attached to the given buffer", function()
      local recovery, sup = reload()

      recovery.retry_start("known", 7, 3)

      assert.are.equal(1, #sup.calls.started)
      assert.are.equal("known", sup.calls.started[1].name)
      assert.are.equal(7, sup.calls.started[1].bufnr)
    end)

    -- Trying again cannot conjure a configuration, and the counter is shared,
    -- so burning it on a typo would also poison the next real attempt.
    it("refuses a name with no configuration without spending an attempt", function()
      local recovery, sup = reload()

      local ok = recovery.retry_start("unknown", 0, 3)

      assert.is_false(ok)
      assert.are.equal(0, #sup.calls.started)
      assert.are.equal(0, sup.attempts("unknown"))
      assert.are.equal("no registered configuration", sup.calls.last_error.msg)
    end)

    it("counts an attempt when it does start", function()
      local recovery, sup = reload()

      recovery.retry_start("known", 0, 3)

      assert.are.equal(1, sup.attempts("known"))
    end)

    it("stops once the cap is reached", function()
      local recovery, sup = reload()
      sup._set_attempts("known", 3)

      local ok = recovery.retry_start("known", 0, 3)

      assert.is_false(ok)
      assert.are.equal(0, #sup.calls.started)
    end)

    it("records why a refused start failed", function()
      local recovery, sup = reload({
        start = function()
          return false
        end,
      })

      local ok = recovery.retry_start("known", 0, 1)

      assert.is_false(ok)
      assert.is_truthy(sup.calls.last_error.msg:find("vim.lsp.start", 1, true))
    end)
  end)

  describe("auto_recover", function()
    --- `auto_recover` reads the expected-server list out of lspdoctor; stub
    --- that so the case controls which servers are considered missing.
    ---@param results table[]
    ---@return nil
    local function stub_health(results)
      package.loaded["lsp.lspdoctor.health"] = {
        check = function()
          return {}, results
        end,
      }
    end

    after_each(function()
      package.loaded["lsp.lspdoctor.health"] = nil
    end)

    it("starts the servers that are configured but not running", function()
      local recovery, sup = reload()
      stub_health({
        { name = "known", config_exists = true, running = false },
        { name = "other", config_exists = true, running = true },
      })

      recovery.auto_recover(0)

      assert.are.equal(1, #sup.calls.started)
      assert.are.equal("known", sup.calls.started[1].name)
    end)

    -- The counter is shared with the supervisor, so a server it gave up on
    -- arrives here past every cap. Without the reset, `:Lsp recover` refuses
    -- to make one attempt in exactly the situation it exists for.
    it("clears a counter the supervisor left exhausted", function()
      local recovery, sup = reload()
      sup._set_attempts("known", 5)
      stub_health({ { name = "known", config_exists = true, running = false } })

      recovery.auto_recover(0)

      assert.are.same({ "known" }, sup.calls.reset)
      assert.are.equal(1, #sup.calls.started)
    end)

    it("starts nothing when everything expected is running", function()
      local recovery, sup = reload()
      stub_health({ { name = "known", config_exists = true, running = true } })

      recovery.auto_recover(0)

      assert.are.equal(0, #sup.calls.started)
    end)
  end)
end)
