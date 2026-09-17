--- Covers `lsp.lspdoctor`'s report surface: that every name reachable from a
--- command actually produces a report, and that the names it replaced are
--- gone.
---
--- This file exists because of a regression it would have caught. Renaming the
--- reports on 2026-08-29 left `M.all` calling `inspect.deep`, which no longer
--- existed — so `:LspDoctor` with no argument, the most common way to invoke
--- it, raised "attempt to call field 'deep' (a nil value)". Nothing failed:
--- 230 specs passed, the smoke test passed, and the command's own `pcall`
--- swallowed it. No spec called `M.all`, and a rename is exactly the change
--- that breaks a call site nobody exercises.
---
--- So these cases run every report for real rather than asserting that a
--- function exists. A report that raises is indistinguishable from one that
--- was never wired up, and both look like a working plugin from the outside.

describe("lsp.lspdoctor", function()
  ---@return table
  local function doctor()
    package.loaded["lsp.lspdoctor"] = nil
    local mod = require("lsp.lspdoctor")
    mod.setup({})
    return mod
  end

  describe("reports", function()
    it("names exactly the reports it offers in completion", function()
      assert.are.same(
        { "startup", "resolve", "buffer", "capabilities", "probe", "all" },
        doctor().MODES
      )
    end)

    -- Running them, not probing for them: the regression this file was written
    -- for was a function that existed and raised on call.
    it("every offered report runs", function()
      local mod = doctor()
      for _, name in ipairs(mod.MODES) do
        local ok, err = pcall(mod[name], 0, false)
        assert.is_true(ok, ("report %q raised: %s"):format(name, tostring(err)))
      end
    end)

    -- The four names the reports carried until 2026-08-29 were kept as
    -- forwarding functions and as an accepted-but-unoffered command argument,
    -- and dropped on 2026-09-02. Asserted as *absent* rather than deleted
    -- along with them: `M.deep` was reachable by anything doing `doctor[name]`
    -- with a name from an old mapping, and a silent reappearance -- a stray
    -- `M.deep = ...`, or the map coming back -- would restore a spelling that
    -- is supposed to be gone.
    it("no longer answers to the names it replaced", function()
      local mod = doctor()
      assert.is_nil(rawget(mod, "LEGACY_MODES"))
      for _, legacy in ipairs({ "health", "debug", "quick", "deep" }) do
        assert.is_nil(mod[legacy], ("%q is still callable"):format(legacy))
      end
    end)
  end)

  -- `probe` is in MODES but not in `all`, and that is a decision rather than
  -- an oversight: it creates a buffer, talks to the servers and waits. If it
  -- ever slips into `all`, `:LspDoctor` with no argument stops being instant
  -- and harmless, which is the whole reason it is the default.
  it("keeps `probe` out of the combined report", function()
    local mod = doctor()
    local combined = mod.all(0, false)
    assert.is_nil(combined.probe)
    assert.are.same(
      { "capabilities", "resolve", "startup" },
      (function()
        local keys = vim.tbl_keys(combined)
        table.sort(keys)
        return keys
      end)()
    )
  end)

  describe("probe", function()
    ---@return table
    local function probe()
      package.loaded["lsp.lspdoctor.probe"] = nil
      local mod = require("lsp.lspdoctor.probe")
      mod.setup({ probe_timeout = 60 })
      return mod
    end

    ---@param filetype string
    ---@return integer
    local function buffer_of(filetype)
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_option_value("filetype", filetype, { buf = bufnr })
      return bufnr
    end

    local saved

    before_each(function()
      saved = {
        get_clients = vim.lsp.get_clients,
        buf_attach_client = vim.lsp.buf_attach_client,
        get_namespace = vim.lsp.diagnostic.get_namespace,
        diagnostic_get = vim.diagnostic.get,
      }
    end)

    after_each(function()
      vim.lsp.get_clients = saved.get_clients
      vim.lsp.buf_attach_client = saved.buf_attach_client
      vim.lsp.diagnostic.get_namespace = saved.get_namespace
      vim.diagnostic.get = saved.diagnostic_get
    end)

    --- One fake client, attaching successfully, answering with `count`
    --- diagnostics on every namespace it is asked about.
    ---@param count integer
    ---@return nil
    local function with_client(count)
      vim.lsp.get_clients = function()
        return { { id = 4242, name = "fake_ls" } }
      end
      -- Three stdlib doubles for this case, all restored afterwards.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.lsp.buf_attach_client = function()
        return true
      end
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.lsp.diagnostic.get_namespace = function(_id, is_pull)
        -- One namespace answers, the other does not, so a double count would
        -- show up as a wrong number rather than passing unnoticed.
        return is_pull and 998 or 999
      end
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.diagnostic.get = function(_bufnr, opts)
        if opts and opts.namespace == 999 and count > 0 then
          local items = {}
          for i = 1, count do
            items[i] = { message = "probe error " .. i, severity = vim.diagnostic.severity.ERROR }
          end
          return items
        end
        return {}
      end
    end

    it("refuses a filetype it has no guaranteed-broken content for", function()
      vim.lsp.get_clients = function()
        return { { id = 1, name = "fake_ls" } }
      end
      local lines, report = probe().run(buffer_of("fortran"))
      assert.are.equal("no snippet", report.reason)
      assert.is_false(report.ok)
      -- The report has to name the alternatives, or the answer is a dead end.
      assert.is_truthy(table.concat(lines, "\n"):find("lua", 1, true))
    end)

    it("says there is nothing to probe when no client is attached", function()
      vim.lsp.get_clients = function()
        return {}
      end
      local _, report = probe().run(buffer_of("lua"))
      assert.are.equal("no clients", report.reason)
      assert.is_false(report.ok)
    end)

    it("reports a client that answers, with a count and a duration", function()
      with_client(2)
      local _, report = probe().run(buffer_of("lua"))
      assert.is_true(report.ok)
      assert.are.equal(1, #report.clients)
      assert.are.equal("fake_ls", report.clients[1].name)
      assert.are.equal(2, report.clients[1].count)
      assert.is_truthy(report.clients[1].elapsed_ms)
    end)

    -- The distinction the whole report exists for: silence is a finding, not
    -- an absence of one.
    it("reports silence as a failure rather than as no errors", function()
      with_client(0)
      local lines, report = probe().run(buffer_of("lua"))
      assert.is_false(report.ok)
      assert.are.equal(0, report.clients[1].count)
      assert.is_truthy(table.concat(lines, "\n"):find("none within", 1, true))
    end)

    it("writes nothing to disk and leaves no buffer behind", function()
      with_client(1)
      local _, report = probe().run(buffer_of("lua"))
      assert.is_truthy(report.path)
      assert.is_nil((vim.uv or vim.loop).fs_stat(report.path))
      assert.are.equal(0, vim.fn.bufexists(report.path))
    end)

    -- The report printed "nothing was asked of this server, so this is not a
    -- verdict on it" and then let that same server hold `ok` down: `answered`
    -- was compared against every client, including the ones that refused the
    -- probe buffer and were therefore sent nothing at all. One refusing client
    -- made `ok` false forever, however healthy the rest were.
    it("does not count a client it never reached", function()
      vim.lsp.get_clients = function()
        return { { id = 1, name = "good_ls" }, { id = 2, name = "refuses_ls" } }
      end
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.lsp.buf_attach_client = function(_bufnr, id)
        return id == 1
      end
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.lsp.diagnostic.get_namespace = function(id, is_pull)
        return (not is_pull) and (100 + id) or nil
      end
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.diagnostic.get = function(_bufnr, opts)
        if opts and opts.namespace == 101 then
          return { { message = "boom", severity = vim.diagnostic.severity.ERROR } }
        end
        return {}
      end

      local lines, report = probe().run(buffer_of("lua"))
      assert.is_true(report.ok, "the one client that was asked answered")
      assert.are.equal(1, report.asked)
      -- Still reported, just not counted -- a denominator quietly smaller than
      -- the client list reads as a rendering bug.
      local rendered = table.concat(lines, "\n")
      assert.is_truthy(rendered:find("1/1 client", 1, true), rendered)
      assert.is_truthy(rendered:find("1 refused the probe buffer", 1, true), rendered)
    end)

    -- `:LspDoctor probe` documents that it does not start servers -- and then
    -- started one every run. Giving the probe buffer its filetype fires
    -- `FileType`, which is the event `vim.lsp.enable` starts servers on, so a
    -- server that was enabled but not running came up for a file that does not
    -- exist. Asserted on the event rather than on a real server, because the
    -- event is the whole mechanism and needs nothing installed.
    it("does not fire FileType for its own buffer", function()
      with_client(1)
      local fired = {}
      local id = vim.api.nvim_create_autocmd("FileType", {
        callback = function(ev)
          fired[#fired + 1] = vim.api.nvim_buf_get_name(ev.buf)
        end,
      })
      local ok, err = pcall(function()
        probe().run(buffer_of("lua"))
      end)
      vim.api.nvim_del_autocmd(id)
      assert.is_true(ok, tostring(err))

      for _, name in ipairs(fired) do
        assert.is_nil(
          name:find("lspdoctor_probe", 1, true),
          "FileType fired for the probe buffer: " .. name
        )
      end
      -- And the option it borrowed is handed back, or every autocommand in the
      -- session stays silenced afterwards.
      assert.are.equal("", vim.o.eventignore)
    end)

    it("names a probe file for every filetype it claims to cover", function()
      local mod = probe()
      local names = mod.filetypes()
      assert.is_true(#names > 0)
      for _, ft in ipairs(names) do
        local snippet = mod.SNIPPETS[ft]
        assert.is_truthy(snippet.ext, ft .. " has no extension")
        assert.is_true(#snippet.lines > 0, ft .. " has no content")
      end
    end)
  end)

  describe("inspect", function()
    ---@return table
    local function inspect()
      package.loaded["lsp.lspdoctor.inspect"] = nil
      local mod = require("lsp.lspdoctor.inspect")
      mod.setup({})
      return mod
    end

    -- `all` composes these two directly rather than going through the public
    -- report functions, which is how the rename slipped past: the public names
    -- were updated and this call site was not.
    it("exposes the two report builders `all` composes", function()
      local mod = inspect()
      assert.are.equal("function", type(mod.buffer))
      assert.are.equal("function", type(mod.capabilities))
    end)

    it("builds both reports without raising", function()
      local mod = inspect()
      for _, name in ipairs({ "buffer", "capabilities" }) do
        local ok, lines = pcall(mod[name], 0)
        assert.is_true(ok, ("inspect.%s raised: %s"):format(name, tostring(lines)))
        assert.are.equal("table", type(lines))
      end
    end)

    it("tags the report with the name it was built under", function()
      local mod = inspect()
      local _, report = mod.capabilities(0)
      assert.are.equal("capabilities", report.mode)
      local _, buffer_report = mod.buffer(0)
      assert.are.equal("buffer", buffer_report.mode)
    end)

    -- Two clients can share a name: two roots of one server in a monorepo, or
    -- the same server started twice for different projects. The report kept a
    -- `name -> client` map, so the second one overwrote the first and became
    -- invisible to every check that walked the map -- while the parallel list
    -- of names still held the name twice, so the count said two and the detail
    -- printed one client's data under both entries.
    --
    -- Measured against two real `lua_ls`, one `utf-16` and one `utf-8`: the
    -- report said "✅ All clients: `utf-8`" and `ok = true`. A mismatch missed
    -- by the section whose whole job is to catch it.
    describe("two clients of the same name", function()
      local saved_get_clients

      before_each(function()
        saved_get_clients = vim.lsp.get_clients
        vim.lsp.get_clients = function()
          return {
            { id = 7, name = "lua_ls", offset_encoding = "utf-16", server_capabilities = {} },
            { id = 9, name = "lua_ls", offset_encoding = "utf-8", server_capabilities = {} },
          }
        end
      end)

      after_each(function()
        vim.lsp.get_clients = saved_get_clients
      end)

      it("sees both, and catches the encoding mismatch between them", function()
        local mod = inspect()
        mod.setup({ show_workspace = true, show_capabilities = true, show_conflicts = true })
        local lines, report = mod.capabilities(vim.api.nvim_get_current_buf())
        local rendered = table.concat(lines, "\n")

        assert.is_false(report.ok, "a mixed offset encoding is not ok\n" .. rendered)
        assert.is_truthy(rendered:find("Mismatch detected", 1, true), rendered)
        -- Disambiguated by id, or the two are indistinguishable in the report.
        assert.is_truthy(rendered:find("lua_ls#7", 1, true), rendered)
        assert.is_truthy(rendered:find("lua_ls#9", 1, true), rendered)
        assert.is_truthy(rendered:find("Clients: 2", 1, true), rendered)
      end)

      -- The disambiguation is not paid for by everyone: one client of a name
      -- keeps the plain name, so the ordinary report reads as it always did.
      it("leaves a unique name alone", function()
        vim.lsp.get_clients = function()
          return {
            { id = 7, name = "lua_ls", offset_encoding = "utf-16", server_capabilities = {} },
          }
        end
        local mod = inspect()
        local lines = mod.capabilities(vim.api.nvim_get_current_buf())
        local rendered = table.concat(lines, "\n")
        assert.is_nil(rendered:find("lua_ls#", 1, true), rendered)
        assert.is_truthy(rendered:find("`lua_ls`", 1, true), rendered)
      end)
    end)
  end)

  -- The semantic-tokens line used to go through `lsp.buf_request_sync`, which
  -- is buffer-wide: it asks every client on the buffer that supports the
  -- method and waits for all of them, so one unrelated client that never
  -- answers makes it return nothing. The line is written about *one* named
  -- server, so it then reported that server as mute because of a neighbour.
  --
  -- Measured against a real `lua_ls`: alone it answered within 8000ms and the
  -- report said so; with any silent client on the same buffer the identical
  -- `lua_ls`, asked directly, still answered while this line flipped to
  -- "no answer". It was also one broadcast per expected server, each blocking
  -- up to `semantic_tokens_timeout`.
  describe("startup", function()
    local saved

    before_each(function()
      saved = {
        get_clients = vim.lsp.get_clients,
        buf_request_sync = vim.lsp.buf_request_sync,
        start_mod = package.loaded["lsp.usercmds.start"],
      }
    end)

    after_each(function()
      vim.lsp.get_clients = saved.get_clients
      vim.lsp.buf_request_sync = saved.buf_request_sync
      package.loaded["lsp.usercmds.start"] = saved.start_mod
    end)

    it("asks the named client for semantic tokens, not the whole buffer", function()
      local went_buffer_wide = false
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.lsp.buf_request_sync = function()
        went_buffer_wide = true
        return nil
      end

      local asked
      vim.lsp.get_clients = function()
        return {
          {
            id = 3,
            name = "fake_ls",
            server_capabilities = { semanticTokensProvider = {} },
            request_sync = function(_self, method, _params, _timeout, _bufnr)
              asked = method
              return { result = { data = {} } }
            end,
          },
        }
      end
      package.loaded["lsp.usercmds.start"] = {
        get_servers_for_buffer = function()
          return { "fake_ls" }
        end,
      }

      package.loaded["lsp.lspdoctor.health"] = nil
      local health = require("lsp.lspdoctor.health")
      health.setup({ semantic_tokens_timeout = 50, show_tools = false })

      local lines = health.check(vim.api.nvim_get_current_buf())
      local rendered = table.concat(lines, "\n")

      assert.is_false(
        went_buffer_wide,
        "the probe broadcast to the buffer instead of asking the server it reports on"
      )
      assert.are.equal("textDocument/semanticTokens/full", asked)
      assert.is_truthy(rendered:find("Semantic tokens: ✅", 1, true), rendered)
    end)
  end)
end)
