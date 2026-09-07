-- need-check-nil / undefined-field / discard-returns are suppressed for the
-- whole file for the reasons given in the other specs here: the test body is
-- the guard, `assert` is busted's rather than Lua's, and a spec arranging
-- state has no return value to inspect.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `lsp.core.diagnostics` as the single owner of `vim.diagnostic.config()`.
---
--- The property under test is the merge order, because it is what makes
--- ownership mean anything: baseline < contributions (in registration order)
--- < the user's config. Everything else here guards the registry around it.

local diag = require("lsp.core.diagnostics")

describe("lsp.core.diagnostics", function()
  before_each(function()
    diag.__reset()
  end)

  after_each(function()
    diag.__reset()
  end)

  describe("baseline", function()
    it("is a fresh table each call, so a caller cannot poison it", function()
      local a, b = diag.baseline(), diag.baseline()
      assert.is_false(a == b)
      a.underline = "poisoned"
      assert.is_true(diag.baseline().underline)
    end)

    it("carries signs keyed by severity", function()
      assert.is_not_nil(diag.baseline().signs.text[vim.diagnostic.severity.ERROR])
    end)
  end)

  describe("contribute", function()
    it("accepts a name and a table", function()
      assert.is_true(diag.contribute("plugin.a", { underline = false }))
    end)

    it("refuses an empty name", function()
      local ok, err = diag.contribute("", {})
      assert.is_false(ok)
      assert.is_string(err)
    end)

    it("refuses a non-table spec", function()
      ---@diagnostic disable-next-line: param-type-mismatch
      local ok, err = diag.contribute("plugin.a", "not a table")
      assert.is_false(ok)
      assert.is_truthy(tostring(err):find("plugin.a", 1, true))
    end)

    it("replaces a repeated name in place rather than stacking", function()
      diag.contribute("plugin.a", { underline = false })
      diag.contribute("plugin.b", { severity_sort = false })
      diag.contribute("plugin.a", { underline = true })

      local names = {}
      for _, src in ipairs(diag.sources()) do
        names[#names + 1] = src.name
      end
      -- baseline, a, b -- a keeps its position, and appears once.
      assert.same({ "lsp.nvim (baseline)", "plugin.a", "plugin.b" }, names)
    end)
  end)

  describe("forget", function()
    it("removes a contribution and says so", function()
      diag.contribute("plugin.a", {})
      assert.is_true(diag.forget("plugin.a"))
      assert.is_false(diag.forget("plugin.a"))
    end)
  end)

  describe("apply", function()
    it("lets a contribution override the baseline", function()
      assert.is_true(diag.baseline().underline)
      diag.contribute("plugin.a", { underline = false })
      assert.is_false(diag.apply(nil).underline)
    end)

    it("lets the user config override a contribution", function()
      diag.contribute("plugin.a", { underline = false })
      assert.is_true(diag.apply({ underline = true }).underline)
    end)

    it("applies contributions in registration order", function()
      diag.contribute("plugin.a", { virtual_text = "from a" })
      diag.contribute("plugin.b", { virtual_text = "from b" })
      assert.equals("from b", diag.apply(nil).virtual_text)
    end)

    it("merges nested tables rather than replacing them", function()
      -- The case that matters: a plugin contributing one sign icon must not
      -- drop the other three.
      diag.contribute("plugin.a", {
        signs = { text = { [vim.diagnostic.severity.ERROR] = "X" } },
      })
      local eff = diag.apply(nil)
      assert.equals("X", eff.signs.text[vim.diagnostic.severity.ERROR])
      assert.is_not_nil(eff.signs.text[vim.diagnostic.severity.WARN])
      assert.is_not_nil(eff.signs.numhl[vim.diagnostic.severity.ERROR])
    end)

    it("strips the keys vim.diagnostic.config does not know", function()
      -- `ui` and `debounce_ms` live in opts.diagnostics for lsp.nvim's own
      -- use; passing them through would hand the API options it never
      -- declared.
      local eff = diag.apply({ ui = "trouble", debounce_ms = 150 })
      assert.is_nil(eff.ui)
      assert.is_nil(eff.debounce_ms)
    end)

    it("actually reaches vim.diagnostic.config", function()
      diag.contribute("plugin.a", { underline = false })
      diag.apply(nil)
      assert.is_false(vim.diagnostic.config().underline)
    end)

    it("records what it applied", function()
      assert.is_nil(diag.applied())
      local eff = diag.apply({ underline = true })
      assert.same(eff, diag.applied())
    end)
  end)

  describe("sources", function()
    it("lists the baseline before any contribution", function()
      assert.equals("lsp.nvim (baseline)", diag.sources()[1].name)
    end)

    it("names the user layer only once one was given", function()
      diag.apply(nil)
      for _, src in ipairs(diag.sources()) do
        assert.is_not.equals("user config", src.name)
      end

      diag.apply({ underline = true })
      local last = diag.sources()[#diag.sources()]
      assert.equals("user config", last.name)
    end)
  end)
end)
