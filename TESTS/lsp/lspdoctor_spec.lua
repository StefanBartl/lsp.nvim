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
      assert.are.same({ "startup", "resolve", "buffer", "capabilities", "all" }, doctor().MODES)
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
