--- Covers the `[severity]` argument shared by `:DiagLoc`, `:DiagQF`,
--- `:DiagNextLoc` and `:DiagPrevLoc`.
---
--- The interesting half is the failure mode, not the happy path. `to_severity`
--- is deliberately lenient -- it maps anything it does not recognize to nil,
--- which downstream means "no filter, every severity". That is right for a Lua
--- caller and wrong for the command line: `:DiagLoc eror` would list *more*
--- than the typo asked for and look like it worked. `parse_severity` exists to
--- separate those two cases, so it is what these cases pin down.

describe("lsp.diagnostics.util severity", function()
  local util = require("lsp.diagnostics.util")
  local S = vim.diagnostic.severity

  describe("parse_severity", function()
    it("treats nil and empty as 'all severities', not as an error", function()
      for _, input in ipairs({ nil, "" }) do
        local sev, err = util.parse_severity(input)
        assert.is_nil(sev)
        assert.is_nil(err)
      end
    end)

    it("accepts 'all' as an explicit spelling of the same thing", function()
      local sev, err = util.parse_severity("all")
      assert.is_nil(sev)
      assert.is_nil(err)
    end)

    it("resolves canonical names", function()
      assert.are.equal(S.ERROR, util.parse_severity("error"))
      assert.are.equal(S.WARN, util.parse_severity("warn"))
      assert.are.equal(S.INFO, util.parse_severity("info"))
      assert.are.equal(S.HINT, util.parse_severity("hint"))
    end)

    it("still accepts the short aliases, which completion does not offer", function()
      assert.are.equal(S.ERROR, util.parse_severity("err"))
      assert.are.equal(S.ERROR, util.parse_severity("e"))
      assert.are.equal(S.WARN, util.parse_severity("warning"))
      assert.are.equal(S.WARN, util.parse_severity("w"))
      assert.are.equal(S.INFO, util.parse_severity("i"))
      assert.are.equal(S.HINT, util.parse_severity("h"))
    end)

    it("is case-insensitive", function()
      assert.are.equal(S.ERROR, util.parse_severity("ERROR"))
      assert.are.equal(S.WARN, util.parse_severity("Warn"))
    end)

    -- The whole point of this function: a typo must not widen the filter.
    it("reports an unknown word instead of silently meaning 'all'", function()
      local sev, err = util.parse_severity("eror")
      assert.is_nil(sev)
      assert.is_string(err)
      assert.is_truthy(err:find("eror", 1, true))
      assert.is_truthy(err:find("error", 1, true)) -- names the valid set
    end)
  end)

  describe("complete_severity", function()
    it("offers the canonical words only, not the eleven accepted spellings", function()
      assert.are.same({ "all", "error", "warn", "info", "hint" }, util.complete_severity(""))
    end)

    it("filters by what has been typed", function()
      assert.are.same({ "warn" }, util.complete_severity("w"))
      assert.are.same({ "error" }, util.complete_severity("e"))
      assert.are.same({ "all" }, util.complete_severity("a"))
    end)

    it("returns nothing rather than everything for an unmatched lead", function()
      assert.are.same({}, util.complete_severity("zz"))
    end)
  end)
end)

describe("lsp.diagnostics.commands", function()
  local NAMES = { "DiagLoc", "DiagNextLoc", "DiagPrevLoc", "DiagQF", "DiagNextQF", "DiagPrevQF" }

  before_each(function()
    -- `enable()` self-guards via a global, so clear it to register fresh.
    vim.g._diagnostics_cmds_enabled = nil
    require("lsp.diagnostics.commands").enable()
  end)

  it("registers every diagnostics command with a description", function()
    local cmds = vim.api.nvim_get_commands({})
    for _, name in ipairs(NAMES) do
      assert.is_truthy(cmds[name], name .. " is not registered")
      assert.is_truthy(#cmds[name].definition > 0, name .. " has no desc")
    end
  end)

  it("completes the severity argument on the four commands that take one", function()
    for _, name in ipairs({ "DiagLoc", "DiagNextLoc", "DiagPrevLoc", "DiagQF" }) do
      assert.are.same(
        { "all", "error", "warn", "info", "hint" },
        vim.fn.getcompletion(name .. " ", "cmdline"),
        name .. " does not complete severities"
      )
    end
  end)

  -- These two walk the quickfix list itself, which `:DiagQF` already filtered.
  it("takes no argument on the two quickfix-stepping commands", function()
    local cmds = vim.api.nvim_get_commands({})
    assert.are.equal("0", tostring(cmds.DiagNextQF.nargs))
    assert.are.equal("0", tostring(cmds.DiagPrevQF.nargs))
  end)
end)
