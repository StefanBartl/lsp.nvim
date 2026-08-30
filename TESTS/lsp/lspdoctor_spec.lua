--- Covers `lsp.lspdoctor`'s report surface: that every name reachable from a
--- command actually produces a report, and that the names it replaced still
--- resolve.
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

    it("every replaced name still runs, and reaches its replacement", function()
      local mod = doctor()
      for legacy, current in pairs(mod.LEGACY_MODES) do
        assert.are.same(
          mod.MODES,
          vim.tbl_filter(function(m)
            return m ~= nil
          end, mod.MODES),
          "MODES intact"
        )
        assert.is_truthy(vim.tbl_contains(mod.MODES, current), legacy .. " maps into MODES")

        local ok, err = pcall(mod[legacy], 0, false)
        assert.is_true(ok, ("legacy report %q raised: %s"):format(legacy, tostring(err)))
      end
    end)

    it("maps every replaced name to a current one", function()
      assert.are.same({
        debug = "resolve",
        deep = "capabilities",
        health = "startup",
        quick = "buffer",
      }, doctor().LEGACY_MODES)
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
      vim.lsp.buf_attach_client = function()
        return true
      end
      vim.lsp.diagnostic.get_namespace = function(_id, is_pull)
        -- One namespace answers, the other does not, so a double count would
        -- show up as a wrong number rather than passing unnoticed.
        return is_pull and 998 or 999
      end
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
  end)
end)
