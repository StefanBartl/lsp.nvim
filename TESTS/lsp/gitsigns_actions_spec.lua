--- Covers `lsp.core.gitsigns_actions`: gitsigns' hunk actions arriving as code
--- actions from an in-process language server.
---
--- The server is exercised for real -- `vim.lsp.start` with the module's own
--- `cmd` function, no process involved -- because "does Neovim accept this as a
--- server, and does `codeAction` reach it and come back" is the part a stub
--- cannot answer. gitsigns is stubbed: the case is about what the server does
--- with the hunks gitsigns reports, not about gitsigns.

local gs_actions = require("lsp.core.gitsigns_actions")

describe("lsp.core.gitsigns_actions", function()
  ---@type integer
  local bufnr
  ---@type string[]
  local ran
  ---@type table[]
  local hunks
  --- What gitsigns was handed: the range of stage/reset (nil for the hunk under
  --- the cursor), and the line the cursor stood on when preview ran.
  ---@type { stage: table|nil, reset: table|nil, preview_line: integer|nil }
  local seen

  before_each(function()
    ran = {}
    seen = {}
    hunks = {}
    package.loaded["gitsigns"] = {
      get_hunks = function()
        return hunks
      end,
      stage_hunk = function(range)
        ran[#ran + 1] = "stage"
        seen.stage = range
      end,
      reset_hunk = function(range)
        ran[#ran + 1] = "reset"
        seen.reset = range
      end,
      preview_hunk = function()
        ran[#ran + 1] = "preview"
        seen.preview_line = vim.api.nvim_win_get_cursor(0)[1]
      end,
    }
    vim.cmd("enew!")
    bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d", "e", "f" })
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ".lua")
  end)

  after_each(function()
    gs_actions.detach()
    package.loaded["gitsigns"] = nil
    for _, client in ipairs(vim.lsp.get_clients({ name = gs_actions.NAME })) do
      client:stop(true)
    end
  end)

  describe("touches_hunk", function()
    it("is true for a line inside an added hunk, and false just outside", function()
      hunks = { { added = { start = 3, count = 2 } } } -- 1-based lines 3..4 = 0-based 2..3
      assert.is_true(gs_actions.touches_hunk(bufnr, 2, 2))
      assert.is_true(gs_actions.touches_hunk(bufnr, 3, 3))
      assert.is_false(gs_actions.touches_hunk(bufnr, 1, 1))
      assert.is_false(gs_actions.touches_hunk(bufnr, 4, 4))
    end)

    it("counts a pure deletion as the one line it sits on", function()
      hunks = { { added = { start = 4, count = 0 }, removed = { start = 4, count = 2 } } }
      assert.is_true(gs_actions.touches_hunk(bufnr, 3, 3))
      assert.is_false(gs_actions.touches_hunk(bufnr, 2, 2))
    end)

    -- gitsigns' own `find_hunk` has both of these as special cases (and so do
    -- its signs): a deletion above the first line is `added.start == 0`, drawn
    -- and acted on at line 1, and one after the last line is `line_count + 1`,
    -- acted on from the last line. The hunk is real in both, and `Stage hunk`
    -- works there -- it just was not offered.
    it("counts a deletion above the first line as line 1", function()
      hunks = {
        { type = "delete", added = { start = 0, count = 0 }, removed = { start = 1, count = 2 } },
      }
      assert.is_true(gs_actions.touches_hunk(bufnr, 0, 0))
      assert.is_false(gs_actions.touches_hunk(bufnr, 1, 1))
    end)

    it("counts a deletion after the last line as the last line", function()
      -- Six lines: the sign of a deletion past the end is `added.start == 7`.
      hunks = {
        { type = "delete", added = { start = 7, count = 0 }, removed = { start = 7, count = 1 } },
      }
      assert.is_true(gs_actions.touches_hunk(bufnr, 5, 5))
      assert.is_false(gs_actions.touches_hunk(bufnr, 4, 4))
    end)

    it("is true when a selection overlaps a hunk", function()
      hunks = { { added = { start = 3, count = 1 } } }
      assert.is_true(gs_actions.touches_hunk(bufnr, 0, 5))
      assert.is_false(gs_actions.touches_hunk(bufnr, 0, 1))
    end)

    it("is false without hunks, without gitsigns, and when gitsigns raises", function()
      hunks = {}
      assert.is_false(gs_actions.touches_hunk(bufnr, 0, 5))

      package.loaded["gitsigns"] = {
        get_hunks = function()
          error("boom")
        end,
      }
      assert.is_false(gs_actions.touches_hunk(bufnr, 0, 5))

      package.loaded["gitsigns"] = nil
      package.preload["gitsigns"] = function()
        error("not installed")
      end
      assert.is_false(gs_actions.touches_hunk(bufnr, 0, 5))
      package.preload["gitsigns"] = nil
    end)
  end)

  describe("code_actions", function()
    ---@param first integer
    ---@param last integer
    ---@return table
    local function params(first, last)
      return {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        range = {
          start = { line = first, character = 0 },
          ["end"] = { line = last, character = 0 },
        },
        context = { diagnostics = {} },
      }
    end

    it("offers stage, reset and preview on a hunk, as commands", function()
      hunks = { { added = { start = 3, count = 1 } } }
      local out = gs_actions.code_actions(params(2, 2))
      assert.are.equal(3, #out)
      assert.are.same(
        { "Stage hunk", "Reset hunk", "Preview hunk" },
        vim.tbl_map(function(a)
          return a.command.title
        end, out)
      )
      for _, action in ipairs(out) do
        assert.is_truthy(action.title:find("gitsigns", 1, true))
        assert.is_truthy(action.command.command:find("^lsp_nvim%.gitsigns%."))
      end
    end)

    -- The kind is what keeps the code-action indicator from lighting on every
    -- changed line: it lights on quickfix and source, and treats no kind at all
    -- as a match.
    it("uses a kind the indicator's default allowlist does not light on", function()
      hunks = { { added = { start = 3, count = 1 } } }
      local lightbulb = require("lsp.core.lightbulb")
      lightbulb.setup({ enable = true, kinds = { "quickfix", "source" } })
      local out = gs_actions.code_actions(params(2, 2))
      assert.are.equal(0, lightbulb._countable(out))
      lightbulb.detach()
    end)

    it("offers nothing off a hunk", function()
      hunks = { { added = { start = 3, count = 1 } } }
      assert.are.same({}, gs_actions.code_actions(params(0, 0)))
    end)

    -- A request at the cursor has no range worth passing on: gitsigns acts on
    -- the hunk under the cursor, and a `{ line, line }` range would stage that
    -- one line instead of the hunk.
    it("carries no range for a request at the cursor", function()
      hunks = { { added = { start = 3, count = 2 } } }
      for _, action in ipairs(gs_actions.code_actions(params(2, 2))) do
        assert.is_nil(action.command.arguments, action.title)
      end
    end)

    -- A selection is a different thing to act on. The offered actions used to
    -- forget it and run on whatever hunk the cursor happened to end up in.
    it("carries the selection, 1-based, when the request is for one", function()
      hunks = { { added = { start = 3, count = 2 } } }
      local out = gs_actions.code_actions(params(1, 4))
      assert.are.equal(3, #out)
      for _, action in ipairs(out) do
        assert.are.same({ { first = 2, last = 5 } }, action.command.arguments, action.title)
      end
    end)

    it("tells a selection within one line from a cursor by its columns", function()
      hunks = { { added = { start = 3, count = 1 } } }
      local p = params(2, 2)
      p.range["end"].character = 1
      for _, action in ipairs(gs_actions.code_actions(p)) do
        assert.are.same({ { first = 3, last = 3 } }, action.command.arguments, action.title)
      end
    end)
  end)

  describe("first_touched", function()
    it("is the first line of the first hunk the range touches", function()
      hunks = {
        { added = { start = 2, count = 1 } },
        { added = { start = 5, count = 2 } },
      }
      assert.are.equal(1, gs_actions.first_touched(bufnr, 0, 5))
      assert.are.equal(4, gs_actions.first_touched(bufnr, 2, 5))
    end)

    it("stays inside the range when the hunk starts above it", function()
      hunks = { { added = { start = 1, count = 4 } } } -- 0-based lines 0..3
      assert.are.equal(2, gs_actions.first_touched(bufnr, 2, 5))
    end)

    it("is nil when nothing is touched", function()
      hunks = { { added = { start = 5, count = 1 } } }
      assert.is_nil(gs_actions.first_touched(bufnr, 0, 2))
      hunks = {}
      assert.is_nil(gs_actions.first_touched(bufnr, 0, 5))
    end)
  end)

  describe("as a language server", function()
    ---@return vim.lsp.Client
    local function start()
      local id = vim.lsp.start({
        name = gs_actions.NAME,
        cmd = gs_actions.server,
        root_dir = nil,
      }, { bufnr = bufnr })
      assert.is_number(id)
      return assert(vim.lsp.get_client_by_id(id))
    end

    it("initializes and advertises only code actions", function()
      local client = start()
      assert.is_truthy(client.server_capabilities.codeActionProvider)
      assert.is_nil(client.server_capabilities.hoverProvider)
      assert.is_nil(client.server_capabilities.documentSymbolProvider)
    end)

    it("answers textDocument/codeAction through Neovim's own client", function()
      hunks = { { added = { start = 3, count = 1 } } }
      local client = start()
      local response = client:request_sync("textDocument/codeAction", {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        range = {
          start = { line = 2, character = 0 },
          ["end"] = { line = 2, character = 0 },
        },
        context = { diagnostics = {} },
      }, 2000, bufnr)
      assert.is_not_nil(response)
      assert.is_nil(response.err)
      assert.are.equal(3, #response.result)
    end)

    -- Neovim tells a synchronous in-process server's requests apart from
    -- pending ones by the fourth argument of `request`, called once the reply
    -- is out. A server that never calls it leaves every request registered as
    -- pending on `client.requests` -- one entry per code-action query, and the
    -- lightbulb asks on every CursorHold -- and `LspRequest` never sees one
    -- complete.
    it("leaves no request pending on Neovim's client once it has answered", function()
      hunks = { { added = { start = 3, count = 1 } } }
      local client = start()
      for _ = 1, 3 do
        local response = client:request_sync("textDocument/codeAction", {
          textDocument = { uri = vim.uri_from_bufnr(bufnr) },
          range = {
            start = { line = 2, character = 0 },
            ["end"] = { line = 2, character = 0 },
          },
          context = { diagnostics = {} },
        }, 2000, bufnr)
        assert.is_not_nil(response)
      end
      assert.are.equal(0, vim.tbl_count(client.requests))
    end)

    it("answers an unknown request with an error, not silence", function()
      local client = start()
      local response = client:request_sync("textDocument/hover", {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        position = { line = 0, character = 0 },
      }, 2000, bufnr)
      assert.is_not_nil(response)
      assert.is_not_nil(response.err)
      assert.are.equal(-32601, response.err.code)
    end)

    it("shows up among the buffer's code-action providers", function()
      start()
      local providers = vim.lsp.get_clients({
        bufnr = bufnr,
        method = "textDocument/codeAction",
      })
      assert.are.equal(gs_actions.NAME, providers[1].name)
    end)
  end)

  describe("setup", function()
    it("does nothing while code_actions.gitsigns is off", function()
      gs_actions.setup({ gitsigns = false })
      vim.b[bufnr].gitsigns_status_dict = {}
      vim.api.nvim_exec_autocmds("User", {
        pattern = "GitSignsUpdate",
        data = { buffer = bufnr },
      })
      vim.wait(100)
      assert.are.equal(0, #vim.lsp.get_clients({ name = gs_actions.NAME, bufnr = bufnr }))
    end)

    it("attaches to a buffer gitsigns reports on, once, and runs its actions", function()
      gs_actions.setup({ gitsigns = true })
      vim.b[bufnr].gitsigns_status_dict = {}
      vim.api.nvim_exec_autocmds("User", {
        pattern = "GitSignsUpdate",
        data = { buffer = bufnr },
      })
      vim.api.nvim_exec_autocmds("User", {
        pattern = "GitSignsUpdate",
        data = { buffer = bufnr },
      })
      vim.wait(2000, function()
        return #vim.lsp.get_clients({ name = gs_actions.NAME, bufnr = bufnr }) > 0
      end, 10)

      local clients = vim.lsp.get_clients({ name = gs_actions.NAME })
      assert.are.equal(1, #clients)

      -- The real command handler, the one `attach` registered.
      for _, command in ipairs({ "stage_hunk", "reset_hunk", "preview_hunk" }) do
        clients[1]:exec_cmd({
          title = command,
          command = "lsp_nvim.gitsigns." .. command,
        }, { bufnr = bufnr })
      end
      vim.wait(1000, function()
        return #ran == 3
      end, 10)
      assert.are.same({ "stage", "reset", "preview" }, ran)
    end)

    it("does not attach to a buffer gitsigns is not attached to", function()
      gs_actions.setup({ gitsigns = true })
      vim.api.nvim_exec_autocmds("User", {
        pattern = "GitSignsUpdate",
        data = { buffer = bufnr },
      })
      vim.wait(100)
      -- This buffer, not the client: an earlier case's buffer still carries
      -- `gitsigns_status_dict`, and `setup()` attaches to every buffer that does.
      assert.are.equal(0, #vim.lsp.get_clients({ name = gs_actions.NAME, bufnr = bufnr }))
    end)

    it("stops its client on detach", function()
      gs_actions.setup({ gitsigns = true })
      vim.b[bufnr].gitsigns_status_dict = {}
      vim.api.nvim_exec_autocmds("User", {
        pattern = "GitSignsUpdate",
        data = { buffer = bufnr },
      })
      vim.wait(2000, function()
        return #vim.lsp.get_clients({ name = gs_actions.NAME }) > 0
      end, 10)
      gs_actions.detach()
      vim.wait(2000, function()
        return #vim.lsp.get_clients({ name = gs_actions.NAME }) == 0
      end, 10)
      assert.are.equal(0, #vim.lsp.get_clients({ name = gs_actions.NAME }))
    end)
  end)

  -- `touches_hunk`/`first_touched` used to call `gitsigns.get_hunks` and
  -- rebuild every hunk's span on every single call -- once per code-action
  -- query, which the indicator sends on every `CursorHold`. gitsigns already
  -- tells us exactly when the hunks changed (`GitSignsUpdate`), so the spans
  -- only need rebuilding then.
  describe("hunk span caching", function()
    --- Wraps the stubbed `gitsigns.get_hunks` to count calls.
    ---@return fun(): integer
    local function count_get_hunks_calls()
      local n = 0
      local real = package.loaded["gitsigns"].get_hunks
      package.loaded["gitsigns"].get_hunks = function(...)
        n = n + 1
        return real(...)
      end
      return function()
        return n
      end
    end

    local function fire_update()
      vim.api.nvim_exec_autocmds("User", {
        pattern = "GitSignsUpdate",
        data = { buffer = bufnr },
      })
    end

    it("asks gitsigns once per GitSignsUpdate, not once per query", function()
      hunks = { { added = { start = 3, count = 2 } } } -- 0-based span [2, 3]
      local calls = count_get_hunks_calls()
      gs_actions.setup({ gitsigns = true })
      vim.b[bufnr].gitsigns_status_dict = {}
      fire_update()
      vim.wait(2000, function()
        return #vim.lsp.get_clients({ name = gs_actions.NAME, bufnr = bufnr }) > 0
      end, 10)

      local after_attach = calls()
      assert.is_true(after_attach >= 1)

      gs_actions.touches_hunk(bufnr, 2, 3)
      gs_actions.touches_hunk(bufnr, 2, 3)
      gs_actions.touches_hunk(bufnr, 0, 0)
      assert.are.equal(after_attach, calls())
    end)

    it("keeps serving the old spans from cache until the next GitSignsUpdate", function()
      gs_actions.setup({ gitsigns = true })
      vim.b[bufnr].gitsigns_status_dict = {}
      hunks = { { added = { start = 3, count = 1 } } } -- 0-based span [2, 2]
      local calls = count_get_hunks_calls()
      fire_update()
      vim.wait(2000, function()
        return #vim.lsp.get_clients({ name = gs_actions.NAME, bufnr = bufnr }) > 0
      end, 10)
      assert.is_true(gs_actions.touches_hunk(bufnr, 2, 2))
      assert.is_false(gs_actions.touches_hunk(bufnr, 5, 5))
      local after_first = calls()

      -- gitsigns has *not* told us the hunks moved yet: still the old spans,
      -- and still no new call to get_hunks.
      hunks = { { added = { start = 6, count = 1 } } } -- 0-based span [5, 5]
      assert.is_true(gs_actions.touches_hunk(bufnr, 2, 2))
      assert.is_false(gs_actions.touches_hunk(bufnr, 5, 5))
      assert.are.equal(after_first, calls())

      fire_update()
      vim.wait(50)

      assert.is_false(gs_actions.touches_hunk(bufnr, 2, 2))
      assert.is_true(gs_actions.touches_hunk(bufnr, 5, 5))
    end)
  end)

  -- Measured against the real config: `:LspRestartHere` force-stops every
  -- client (`Client:stop(true)`), which for a client with no process is a call
  -- to the server's `terminate()` and nothing else. Neovim drops a client from
  -- `get_clients()` only when it hears `on_exit`, and nobody told it, so the
  -- client stayed listed as stopped, `attach` counted it as attached, and the
  -- hunk actions were gone until the editor restarted.
  describe("being force-stopped", function()
    ---@return integer
    local function live_count()
      local n = 0
      for _, client in ipairs(vim.lsp.get_clients({ name = gs_actions.NAME, bufnr = bufnr })) do
        if not client:is_stopped() then
          n = n + 1
        end
      end
      return n
    end

    local function hunk_update()
      vim.api.nvim_exec_autocmds("User", {
        pattern = "GitSignsUpdate",
        data = { buffer = bufnr },
      })
    end

    ---@return vim.lsp.Client
    local function attached_client()
      gs_actions.setup({ gitsigns = true })
      vim.b[bufnr].gitsigns_status_dict = {}
      hunk_update()
      vim.wait(2000, function()
        return live_count() == 1
      end, 10)
      -- `setup()` also attaches, on the next tick, to every buffer that still
      -- carries `gitsigns_status_dict` from an earlier case. Let that happen
      -- now, not in the middle of the stop below.
      vim.wait(50)
      return assert(vim.lsp.get_clients({ name = gs_actions.NAME, bufnr = bufnr })[1])
    end

    it("leaves the client list instead of lingering as a stopped client", function()
      local id = attached_client().id
      assert.is_not_nil(vim.lsp.get_client_by_id(id))

      assert(vim.lsp.get_client_by_id(id)):stop(true)
      vim.wait(2000, function()
        return vim.lsp.get_client_by_id(id) == nil
      end, 10)

      assert.is_nil(vim.lsp.get_client_by_id(id), "the stopped client is still listed")
    end)

    it("is attached again by the next hunk update", function()
      local id = attached_client().id
      assert(vim.lsp.get_client_by_id(id)):stop(true)
      vim.wait(2000, function()
        return vim.lsp.get_client_by_id(id) == nil
      end, 10)
      assert.are.equal(0, live_count())

      hunk_update()
      vim.wait(2000, function()
        return live_count() == 1
      end, 10)
      assert.are.equal(1, live_count())
      local again = assert(vim.lsp.get_clients({ name = gs_actions.NAME, bufnr = bufnr })[1])
      assert.are_not.equal(id, again.id)
    end)

    -- The guard on its own, without the fix above: a stopped client that is
    -- still in the list (a stand-in that never reports its exit) must not count
    -- as "already attached".
    it("does not count a stopped client that is still listed as attached", function()
      gs_actions.setup({ gitsigns = true })
      vim.b[bufnr].gitsigns_status_dict = {}
      local id = assert(vim.lsp.start({
        name = gs_actions.NAME,
        cmd = function()
          local closing = false
          return {
            request = function(method, _, callback)
              if method == "initialize" then
                callback(nil, { capabilities = { codeActionProvider = true } })
              end
              return true, 1
            end,
            notify = function()
              return true
            end,
            is_closing = function()
              return closing
            end,
            terminate = function()
              closing = true -- and never `on_exit`: the client stays listed
            end,
          }
        end,
        root_dir = nil,
      }, { bufnr = bufnr }))
      local zombie = assert(vim.lsp.get_client_by_id(id))
      zombie:stop(true)
      vim.wait(200)
      assert.is_true(zombie:is_stopped())
      assert.is_not_nil(vim.lsp.get_client_by_id(id), "the stand-in is still listed")

      hunk_update()
      vim.wait(2000, function()
        return live_count() == 1
      end, 10)
      assert.are.equal(1, live_count())
    end)

    -- What the server tells Neovim, without Neovim in the way: one exit, whichever
    -- way it comes -- the graceful `exit` notification or `terminate()`.
    it("reports its exit to Neovim once, from terminate and from exit alike", function()
      local exits = {}
      local server = gs_actions.server({
        on_exit = function(code, signal)
          exits[#exits + 1] = { code, signal }
        end,
      })
      assert.is_false(server.is_closing())

      -- `terminate()` alone has to say it: for a client with no process nothing
      -- else will, and that is the whole defect.
      server.terminate()
      assert.are.same({ { 0, 0 } }, exits)
      assert.is_true(server.is_closing())

      -- And once is enough: a second terminate, or the graceful `exit` that
      -- follows a shutdown request, must not report it again.
      server.terminate()
      server.notify("exit")
      assert.are.same({ { 0, 0 } }, exits)
    end)

    it("reports the exit when Neovim asks for a graceful stop", function()
      local exits = 0
      local server = gs_actions.server({
        on_exit = function()
          exits = exits + 1
        end,
      })
      server.notify("exit")
      assert.are.equal(1, exits)
      assert.is_true(server.is_closing())
    end)
  end)

  -- The picker's choice is executed after it has closed, by which time the
  -- Visual selection it was offered for is gone and the cursor sits on one end
  -- of it. "Stage hunk" / "Reset hunk" used to act on the hunk under that
  -- cursor whatever the request was for: over a selection that spans two hunks
  -- they touched one of them, or none.
  describe("running an action on what it was offered for", function()
    ---@return vim.lsp.Client
    local function attached()
      gs_actions.setup({ gitsigns = true })
      vim.b[bufnr].gitsigns_status_dict = {}
      vim.api.nvim_exec_autocmds("User", {
        pattern = "GitSignsUpdate",
        data = { buffer = bufnr },
      })
      vim.wait(2000, function()
        return #vim.lsp.get_clients({ name = gs_actions.NAME, bufnr = bufnr }) > 0
      end, 10)
      vim.wait(50)
      return assert(vim.lsp.get_clients({ name = gs_actions.NAME, bufnr = bufnr })[1])
    end

    --- Run one of the offered commands the way Neovim does after the picker.
    ---@param client vim.lsp.Client
    ---@param id string
    ---@param arguments table|nil
    ---@param ctx_bufnr integer|nil
    local function run(client, id, arguments, ctx_bufnr)
      local before = #ran
      client:exec_cmd({
        title = id,
        command = "lsp_nvim.gitsigns." .. id,
        arguments = arguments,
      }, { bufnr = ctx_bufnr or bufnr })
      vim.wait(1000, function()
        return #ran > before
      end, 10)
    end

    it("hands a selection's range to stage and to reset", function()
      local client = attached()
      run(client, "stage_hunk", { { first = 3, last = 5 } })
      run(client, "reset_hunk", { { first = 3, last = 5 } })
      assert.are.same({ 3, 5 }, seen.stage)
      assert.are.same({ 3, 5 }, seen.reset)
    end)

    it("hands gitsigns no range for a request at the cursor", function()
      local client = attached()
      run(client, "stage_hunk")
      run(client, "reset_hunk")
      assert.are.same({ "stage", "reset" }, ran)
      assert.is_nil(seen.stage)
      assert.is_nil(seen.reset)
    end)

    -- Preview has no range: it shows the hunk under the cursor. So the cursor
    -- goes to the first hunk the selection touches, or "the hunk under the
    -- cursor" is whichever one the selection happened to end in.
    it("points preview at the first hunk a selection touches", function()
      hunks = { { added = { start = 4, count = 2 } } } -- 0-based lines 3..4
      local client = attached()
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      run(client, "preview_hunk", { { first = 1, last = 6 } })

      assert.are.same({ "preview" }, ran)
      assert.are.equal(4, seen.preview_line)
    end)

    it("keeps the cursor inside the selection when the hunk starts above it", function()
      hunks = { { added = { start = 1, count = 4 } } } -- 0-based lines 0..3
      local client = attached()
      vim.api.nvim_win_set_cursor(0, { 6, 0 })

      run(client, "preview_hunk", { { first = 3, last = 6 } })

      assert.are.equal(3, seen.preview_line)
    end)

    it("leaves the cursor alone for a request at the cursor", function()
      hunks = { { added = { start = 4, count = 2 } } }
      local client = attached()
      vim.api.nvim_win_set_cursor(0, { 5, 0 })

      run(client, "preview_hunk")

      assert.are.equal(5, seen.preview_line)
    end)

    it("does not move the cursor of a window that shows another buffer", function()
      hunks = { { added = { start = 4, count = 2 } } }
      local client = attached()
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      local other = vim.api.nvim_create_buf(true, false)

      run(client, "preview_hunk", { { first = 1, last = 6 } }, other)

      assert.are.equal(1, seen.preview_line)
      vim.api.nvim_buf_delete(other, { force = true })
    end)
  end)
end)
