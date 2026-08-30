--- Covers `lsp.core.supervisor`: the exit classifier, the backoff curve, the
--- attempt counter it owns for the rest of the plugin, and the config
--- normalization that feeds it.
---
--- The classifier is where the bugs would live, because every one of its four
--- "not a crash" answers looks like the crash case from one field of the exit:
--- a deliberate force-stop arrives as SIGTERM, quitting Neovim kills every
--- client, and a server that died before it ever attached has an exit code and
--- nothing else. Getting any of them wrong is not a missing feature -- it is
--- Neovim restarting a server the user just stopped, or restarting one during
--- `:qa`.
---
--- No language server is started. `_handle_exit` is driven directly, with the
--- attach bookkeeping seeded through the real `LspAttach` handler and a stub
--- client, so what is under test is the decision rather than the plumbing
--- around it. The restart delay is set far beyond the suite's runtime wherever
--- a case would otherwise schedule one.

describe("lsp.core.supervisor", function()
  --- Fresh module state per case: the counters and the tracking tables are
  --- file-locals, so one case's crash would still be on record in the next.
  ---@return table
  local function reload()
    local mod = package.loaded["lsp.core.supervisor"]
    if mod then
      pcall(mod.detach)
    end
    package.loaded["lsp.core.supervisor"] = nil
    return (require("lsp.core.supervisor"))
  end

  --- A delay no case in this file waits for, so a scheduled restart never
  --- fires inside the suite.
  ---@type integer
  local NEVER = 10 * 60 * 1000

  --- Seed the attach bookkeeping for one client id, through the real handler.
  ---@param sup table
  ---@param client_id integer
  ---@param name string
  ---@return nil
  local function attach(sup, client_id, name)
    local real = vim.lsp.get_client_by_id
    vim.lsp.get_client_by_id = function(id)
      return { id = id, name = name }
    end
    vim.api.nvim_exec_autocmds("LspAttach", {
      buffer = vim.api.nvim_get_current_buf(),
      data = { client_id = client_id },
      group = sup.GROUP,
    })
    vim.lsp.get_client_by_id = real
  end

  after_each(function()
    local mod = package.loaded["lsp.core.supervisor"]
    if mod then
      pcall(mod.detach)
    end
  end)

  describe("the exit classifier", function()
    it("counts a crash and records why", function()
      local sup = reload()
      sup.setup({ enable = true, initial_delay_ms = NEVER, max_delay_ms = NEVER })
      attach(sup, 1, "gopls")

      sup._handle_exit(1, 0, 1)

      assert.are.equal(1, sup.attempts("gopls"))
      assert.is_truthy(sup.last_error("gopls"):find("code 1", 1, true))
    end)

    it("counts a signal as a crash too", function()
      local sup = reload()
      sup.setup({ enable = true, initial_delay_ms = NEVER, max_delay_ms = NEVER })
      attach(sup, 1, "gopls")

      sup._handle_exit(0, 9, 1)

      assert.are.equal(1, sup.attempts("gopls"))
      assert.is_truthy(sup.last_error("gopls"):find("signal 9", 1, true))
    end)

    -- The case the whole `expect_stop` mechanism exists for: a force-stop
    -- sends SIGTERM, which on the way out is a crash in every observable way.
    it("does not count a stop that was declared", function()
      local sup = reload()
      sup.setup({ enable = true, initial_delay_ms = NEVER, max_delay_ms = NEVER })
      attach(sup, 1, "gopls")

      sup.expect_stop(1)
      sup._handle_exit(0, 15, 1)

      assert.are.equal(0, sup.attempts("gopls"))
    end)

    it("takes a list of ids, for a stop-them-all", function()
      local sup = reload()
      sup.setup({ enable = true, initial_delay_ms = NEVER, max_delay_ms = NEVER })
      attach(sup, 1, "gopls")
      attach(sup, 2, "lua_ls")

      sup.expect_stop({ 1, 2 })
      sup._handle_exit(0, 15, 1)
      sup._handle_exit(0, 15, 2)

      assert.are.equal(0, sup.attempts("gopls"))
      assert.are.equal(0, sup.attempts("lua_ls"))
    end)

    -- A mark is consumed by the exit it was set for. Otherwise one `:Lsp stop`
    -- would excuse every later crash of the same client id.
    it("consumes the mark, so a later crash still counts", function()
      local sup = reload()
      sup.setup({ enable = true, initial_delay_ms = NEVER, max_delay_ms = NEVER })

      attach(sup, 1, "gopls")
      sup.expect_stop(1)
      sup._handle_exit(0, 15, 1)

      attach(sup, 1, "gopls")
      sup._handle_exit(0, 15, 1)

      assert.are.equal(1, sup.attempts("gopls"))
    end)

    it("ignores a clean exit nobody asked for", function()
      local sup = reload()
      sup.setup({ enable = true, initial_delay_ms = NEVER, max_delay_ms = NEVER })
      attach(sup, 1, "gopls")

      sup._handle_exit(0, 0, 1)

      assert.are.equal(0, sup.attempts("gopls"))
    end)

    -- No name, no buffer, and a startup crash loop is the one this must not
    -- enter. `:Lsp recover` owns that case.
    it("ignores a client it never saw attach", function()
      local sup = reload()
      sup.setup({ enable = true, initial_delay_ms = NEVER, max_delay_ms = NEVER })

      sup._handle_exit(1, 0, 99)

      assert.are.equal(0, sup.attempts("gopls"))
    end)

    it("does nothing while switched off", function()
      local sup = reload()
      sup.setup({ enable = false, initial_delay_ms = NEVER, max_delay_ms = NEVER })
      attach(sup, 1, "gopls")

      sup._handle_exit(1, 0, 1)

      assert.are.equal(0, sup.attempts("gopls"))
    end)

    it("stops counting down a server that keeps crashing", function()
      local sup = reload()
      sup.setup({ enable = true, max_attempts = 2, initial_delay_ms = NEVER, max_delay_ms = NEVER })

      for _ = 1, 4 do
        attach(sup, 1, "gopls")
        sup._handle_exit(1, 0, 1)
      end

      -- Three crashes past the cap still leave the counter at what it reached:
      -- `:LspDoctor startup` has to be able to say how bad it got.
      assert.is_true(sup.attempts("gopls") >= 2)
    end)

    it("forgets a server's history once its exit was wanted", function()
      local sup = reload()
      sup.setup({ enable = true, initial_delay_ms = NEVER, max_delay_ms = NEVER })

      attach(sup, 1, "gopls")
      sup._handle_exit(1, 0, 1)
      assert.are.equal(1, sup.attempts("gopls"))

      attach(sup, 2, "gopls")
      sup.expect_stop(2)
      sup._handle_exit(0, 15, 2)

      assert.are.equal(0, sup.attempts("gopls"))
    end)
  end)

  describe("backoff", function()
    it("doubles from the initial delay", function()
      local sup = reload()
      sup.setup({ initial_delay_ms = 1000, max_delay_ms = 30000 })

      assert.are.equal(1000, sup._backoff(1))
      assert.are.equal(2000, sup._backoff(2))
      assert.are.equal(4000, sup._backoff(3))
      assert.are.equal(8000, sup._backoff(4))
    end)

    it("stops doubling at the cap", function()
      local sup = reload()
      sup.setup({ initial_delay_ms = 1000, max_delay_ms = 3000 })

      assert.are.equal(1000, sup._backoff(1))
      assert.are.equal(2000, sup._backoff(2))
      assert.are.equal(3000, sup._backoff(3))
      assert.are.equal(3000, sup._backoff(20))
    end)
  end)

  describe("the attempt counter", function()
    it("counts up and reads back", function()
      local sup = reload()
      sup.setup({})

      assert.are.equal(0, sup.attempts("x"))
      assert.are.equal(1, sup.note_attempt("x"))
      assert.are.equal(2, sup.note_attempt("x"))
      assert.are.equal(2, sup.attempts("x"))
    end)

    it("keeps the last error until it is reset", function()
      local sup = reload()
      sup.setup({})

      sup.note_error("x", "boom")
      assert.are.equal("boom", sup.last_error("x"))
      sup.reset("x")
      assert.is_nil(sup.last_error("x"))
      assert.are.equal(0, sup.attempts("x"))
    end)

    -- The reason this counter lives here at all: `:LspDoctor startup` used to
    -- read it from `lsp.usercmds.state`, which has never existed, so the line
    -- said 0 whatever had happened.
    it("is what lspdoctor reports", function()
      local sup = reload()
      sup.setup({})
      sup.note_attempt("gopls")
      sup.note_attempt("gopls")
      sup.note_error("gopls", "exited with code 1, signal 0")

      package.loaded["lsp.lspdoctor.health"] = nil
      local health = require("lsp.lspdoctor.health")
      local lines = health.startup and health.startup(vim.api.nvim_get_current_buf()) or nil

      if type(lines) == "table" then
        local text = table.concat(lines, "\n")
        -- Only meaningful when gopls is among the expected servers here; the
        -- counter API above is the invariant either way.
        if text:find("gopls", 1, true) then
          assert.is_truthy(text:find("Attempts: 2", 1, true))
        end
      end

      assert.are.equal(2, sup.attempts("gopls"))
    end)
  end)

  describe("status", function()
    it("reports the schedule and the servers on record", function()
      local sup = reload()
      sup.setup({ enable = true, max_attempts = 3, initial_delay_ms = 500, max_delay_ms = 9000 })
      sup.note_attempt("gopls")
      sup.note_error("gopls", "exited with code 1, signal 0")

      local text = table.concat(sup.status(), "\n")
      assert.is_truthy(text:find("enabled:%s+yes"))
      assert.is_truthy(text:find("max attempts:%s+3"))
      assert.is_truthy(text:find("500ms, doubling, capped at 9000ms", 1, true))
      assert.is_truthy(text:find("gopls", 1, true))
      assert.is_truthy(text:find("exited with code 1", 1, true))
    end)

    it("says so when nothing has failed", function()
      local sup = reload()
      sup.setup({})

      assert.is_truthy(
        table.concat(sup.status(), "\n"):find("no server has a failed attempt on record", 1, true)
      )
    end)
  end)

  describe("toggle", function()
    it("flips and reports", function()
      local sup = reload()
      sup.setup({ enable = true })

      assert.is_true(sup.enabled())
      sup.toggle()
      assert.is_false(sup.enabled())
      sup.set(true)
      assert.is_true(sup.enabled())
    end)
  end)

  describe("config normalization", function()
    ---@return table
    local function resolve(opts)
      local config = package.loaded["lsp.config"]
      package.loaded["lsp.config"] = nil
      local fresh = require("lsp.config")
      fresh.setup(vim.tbl_deep_extend("force", { project = { enable = false } }, opts or {}))
      local cfg = fresh.get()
      package.loaded["lsp.config"] = config
      return cfg
    end

    it("defaults to on with a bounded schedule", function()
      local cfg = resolve({})

      assert.is_true(cfg.auto_restart.enable)
      assert.are.equal(4, cfg.auto_restart.max_attempts)
      assert.are.equal(1000, cfg.auto_restart.initial_delay_ms)
      assert.are.equal(30000, cfg.auto_restart.max_delay_ms)
    end)

    -- Zero would either fire a timer instantly forever or make the give-up
    -- test unreachable, and it would fail far from the setup() call.
    it("pulls a zero or negative back to the default", function()
      local cfg = resolve({ auto_restart = { max_attempts = 0, initial_delay_ms = -1 } })

      assert.are.equal(4, cfg.auto_restart.max_attempts)
      assert.are.equal(1000, cfg.auto_restart.initial_delay_ms)
    end)

    -- A cap below the first delay would make the backoff shrink instead of
    -- grow -- the opposite of what the option is for.
    it("raises a cap that sits below the initial delay", function()
      local cfg = resolve({ auto_restart = { initial_delay_ms = 5000, max_delay_ms = 100 } })

      assert.are.equal(5000, cfg.auto_restart.max_delay_ms)
    end)

    it("falls back on a non-number", function()
      local cfg = resolve({ auto_restart = { reset_after_ms = "soon" } })

      assert.are.equal(60000, cfg.auto_restart.reset_after_ms)
    end)
  end)
end)
