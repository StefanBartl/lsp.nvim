--- Covers what `:Lsp stop`, `:Lsp restart`, `:Lsp start`, `:Lsp info`,
--- `:Lsp force-restart` and the command-line completion actually *do* to a
--- buffer, as opposed to what they print while doing it.
---
--- Every case here pins a measurement taken against the unfixed code:
---
---  * `Client:is_stopped()` means "shutdown has been requested", not "the
---    process is gone". On 0.12.2 it flipped to true in the same tick as
---    `client:stop(false)` and stayed true while the client sat in
---    `get_clients()` six seconds later -- so the poll in `stop.lua` reported
---    success on its first 50ms tick and its force-stop fallback was
---    unreachable. A server that ignores `shutdown` was never killed.
---  * A client name is not unique. Two clients named `dup` on one buffer, and
---    `:Lsp stop dup` / `:Lsp restart dup` stopped the first and left the
---    second attached while reporting the name as handled.
---  * `:Lsp info` and the `:Lsp start` completion each kept a private
---    hardcoded filetype table -- copies of the one `lsp.usercmds.start` was
---    rewritten to get rid of. On an `html` buffer with `tailwindcss`
---    attached and running, the report named `html` and `emmet_ls` (which
---    this plugin does not configure) and never mentioned the server that was
---    running.
---  * `:Lsp force-restart X` with nothing running does not reset the shared
---    attempt counter, so after a crash loop it refused to make one attempt.
---  * `:Lsp start` counted an already-attached server as one it started.
---
--- Real `vim.lsp.config` registrations and in-process stub servers, because
--- what is under test is the state the commands leave behind. `cmd` is a
--- function, so no process is ever spawned.

describe("lsp.usercmds", function()
  ---@type integer[]
  local spawned = {}

  --- In-process stub server.
  ---@param opts { mute: boolean|nil }|nil # `mute` never answers `shutdown`.
  ---@return fun(dispatchers: table): table
  local function stub_server(opts)
    opts = opts or {}
    return function(dispatchers)
      local closing = false
      return {
        request = function(method, _params, callback)
          if method == "initialize" then
            callback(nil, { capabilities = {} })
          elseif method == "shutdown" and not opts.mute then
            callback(nil, nil)
          end
          return true, 1
        end,
        notify = function(method)
          if method == "exit" then
            closing = true
            vim.schedule(function()
              dispatchers.on_exit(0, 0)
            end)
          end
          return true
        end,
        is_closing = function()
          return closing
        end,
        terminate = function()
          if not closing then
            closing = true
            vim.schedule(function()
              dispatchers.on_exit(0, 15)
            end)
          end
        end,
      }
    end
  end

  --- Attach one more client under `name`, even if one is already there.
  ---@param name string
  ---@param bufnr integer
  ---@param opts table|nil # passed to `stub_server`
  ---@return integer client_id
  local function attach(name, bufnr, opts)
    local id = assert(vim.lsp.start({
      name = name,
      cmd = stub_server(opts),
      root_dir = vim.uv.cwd(),
    }, {
      bufnr = bufnr,
      -- The point of several cases below: a name can be carried by more than
      -- one client, which is exactly what the default reuse forbids.
      reuse_client = function()
        return false
      end,
    }))
    spawned[#spawned + 1] = id
    return id
  end

  ---@param bufnr integer
  ---@return string[] # `name#id` per attached client, sorted
  local function attached(bufnr)
    local out = {}
    for _, c in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
      out[#out + 1] = c.name .. "#" .. c.id
    end
    table.sort(out)
    return out
  end

  ---@param ms integer
  local function settle(ms)
    vim.wait(ms, function()
      return false
    end, 20)
  end

  ---@param ft string|nil
  ---@return integer bufnr
  local function current_buffer(ft)
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(bufnr)
    if ft then
      vim.bo[bufnr].filetype = ft
    end
    return bufnr
  end

  --- Collect what a call notifies, without printing it.
  ---@param fn fun()
  ---@return string[]
  local function messages_of(fn)
    local seen = {}
    local original = vim.notify
    vim.notify = function(msg)
      seen[#seen + 1] = tostring(msg)
    end
    local ok, err = pcall(fn)
    vim.notify = original
    assert(ok, err)
    return seen
  end

  ---@param list string[]
  ---@param pattern string
  ---@return boolean
  local function any_matches(list, pattern)
    for _, line in ipairs(list) do
      if line:match(pattern) then
        return true
      end
    end
    return false
  end

  before_each(function()
    vim.lsp.config("spec_css_a", { cmd = { "true" }, filetypes = { "css" } })
    vim.lsp.config("spec_css_b", { cmd = { "true" }, filetypes = { "css", "scss" } })
    vim.lsp.enable("spec_css_a")
    vim.lsp.enable("spec_css_b")
  end)

  after_each(function()
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
  end)

  describe("stop", function()
    it("stops every client carrying the name, not the first one found", function()
      local bufnr = current_buffer()
      attach("dup", bufnr)
      attach("dup", bufnr)
      assert.are.equal(2, #attached(bufnr))

      require("lsp.usercmds.stop").execute({ args = "dup" })
      settle(1000)

      assert.are.same({}, attached(bufnr), "both instances went down")
    end)

    it("force-stops a server that never answers shutdown", function()
      local bufnr = current_buffer()
      attach("mute", bufnr, { mute = true })

      require("lsp.usercmds.stop").execute({ args = "mute" })

      -- Still there while the graceful window is open: `is_stopped()` is true
      -- from the first tick, so a poll that trusted it would have declared
      -- victory here and never reached the deadline.
      settle(1000)
      assert.are.equal(1, #attached(bufnr), "graceful shutdown is still being waited on")

      -- The 3s deadline, plus room for the SIGTERM to land.
      settle(3000)
      assert.are.same({}, attached(bufnr), "the deadline force-stopped it")
    end)

    it("warns when the name is not attached, and stops nothing", function()
      local bufnr = current_buffer()
      attach("other", bufnr)

      local said = messages_of(function()
        require("lsp.usercmds.stop").execute({ args = "absent" })
      end)
      settle(200)

      assert.is_true(any_matches(said, "not running"))
      assert.are.equal(1, #attached(bufnr))
    end)
  end)

  describe("restart", function()
    it("stops every client carrying the name before restarting", function()
      local bufnr = current_buffer()
      attach("dup", bufnr)
      attach("dup", bufnr)

      require("lsp.usercmds.restart").execute({ args = "dup" })
      settle(600)

      -- `dup` has no registered configuration, so nothing comes back up; what
      -- is asserted is that nothing was left behind. The old loop `break`ed
      -- after the first client and the second one survived the restart.
      for _, entry in ipairs(attached(bufnr)) do
        assert.is_nil(entry:match("^dup#"), "no instance of dup survived: " .. entry)
      end
    end)

    it("counts servers, not clients, when restarting everything", function()
      local bufnr = current_buffer("css")
      attach("spec_css_a", bufnr)
      attach("spec_css_a", bufnr)

      require("lsp.usercmds.restart").execute({ args = "" })
      local said = {}
      local original = vim.notify
      vim.notify = function(msg)
        said[#said + 1] = tostring(msg)
      end
      settle(400)
      vim.notify = original

      -- One name, so one server: `supervisor.start` reuses the client it made
      -- for the first call. The old loop collected a name per client and
      -- reported "2/2" for what is one restart.
      assert.is_true(any_matches(said, "Restarted %d+/1 LSP server"), table.concat(said, " | "))
    end)
  end)

  describe("start", function()
    it("does not count an already attached server as one it started", function()
      local bufnr = current_buffer("css")
      attach("spec_css_a", bufnr)
      attach("spec_css_b", bufnr)

      local said = messages_of(function()
        require("lsp.usercmds.start").execute({ args = "" })
      end)

      assert.is_false(any_matches(said, "Started 2/2"), "nothing was started")
      assert.is_true(any_matches(said, "Started 0/2"))
      assert.is_true(any_matches(said, "2 already running"))
    end)
  end)

  describe("info", function()
    --- Run `:Lsp info` with the viewer replaced by a collector.
    ---@return string[]
    local function report()
      local kit = require("ui.kit")
      local original = kit.viewer
      local lines
      kit.viewer = function(opts)
        lines = opts.lines
      end
      local ok, err = pcall(require("lsp.usercmds.info").execute)
      kit.viewer = original
      assert(ok, err)
      return lines
    end

    it("reports the servers registered for the filetype, not a hardcoded list", function()
      local bufnr = current_buffer("css")
      local lines = report()

      assert.is_true(any_matches(lines, "spec_css_a"), "the registered config is expected")
      assert.is_true(any_matches(lines, "spec_css_b"), "both registered configs are expected")
      -- What the hardcoded table said for `css`, and this plugin has no such
      -- configuration: `:Lsp start cssls` answers "No registered LSP
      -- configuration for 'cssls'".
      assert.is_false(any_matches(lines, "cssls"), "no server the plugin cannot start")
      assert.is_false(
        any_matches(lines, "%(none configured%)"),
        "a filetype with registered servers is not 'none configured'"
      )
      assert.are.equal(bufnr, vim.api.nvim_get_current_buf())
    end)

    it("names a running server the hardcoded table did not know about", function()
      local bufnr = current_buffer("css")
      attach("spec_css_b", bufnr)

      local lines = report()
      assert.is_true(any_matches(lines, "spec_css_b %[✓ running%]"))
    end)

    it("prints the buffer it is reporting on", function()
      local bufnr = current_buffer("css")
      local lines = report()

      assert.is_true(
        any_matches(lines, "^Buffer:%s+" .. bufnr .. "$"),
        "the report names buffer " .. bufnr .. ", not the literal 0"
      )
    end)
  end)

  describe("completion", function()
    it("offers only names :Lsp start can actually start", function()
      current_buffer("css")
      local got = require("lsp.usercmds.completion").complete_start("", "", 0)
      table.sort(got)

      -- The registered set, and nothing else. `lsp.core.registry.ACTIVE` --
      -- the field this used to read -- does not exist (that module exports
      -- `setup_all` alone), so the six-name "fallback" was the whole answer,
      -- and the hardcoded filetype table added `cssls` on top of it.
      assert.are.same({ "spec_css_a", "spec_css_b" }, got)
    end)

    it("drops a server that is already running", function()
      local bufnr = current_buffer("css")
      attach("spec_css_a", bufnr)

      local got = require("lsp.usercmds.completion").complete_start("", "", 0)
      assert.are.same({ "spec_css_b" }, got)
    end)

    it("offers a shared name once", function()
      local bufnr = current_buffer("css")
      attach("dup", bufnr)
      attach("dup", bufnr)

      assert.are.same({ "dup" }, require("lsp.usercmds.completion").complete_stop("", "", 0))
    end)
  end)

  describe("force-restart", function()
    it("clears the shared attempt counter before starting a server that is down", function()
      local supervisor = require("lsp.core.supervisor")
      local bufnr = current_buffer("css")

      -- The history a crash loop leaves behind: the counter is shared with
      -- `lsp.core.supervisor`, which gives up after four attempts.
      for _ = 1, 4 do
        supervisor.note_attempt("spec_css_a")
      end
      supervisor.note_error("spec_css_a", "spawn failed")

      local started = {}
      local original = supervisor.start
      supervisor.start = function(name)
        started[#started + 1] = name
        return true
      end
      local ok, err = pcall(function()
        require("lsp.usercmds.recovery").force_restart("spec_css_a", bufnr)
      end)
      supervisor.start = original
      assert(ok, err)

      assert.are.same(
        { "spec_css_a" },
        started,
        "force-restart made an attempt instead of refusing at the cap"
      )
      settle(100)
      supervisor.reset("spec_css_a")
    end)
  end)
end)
