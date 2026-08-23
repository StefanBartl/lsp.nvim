--- Covers `lsp.core.capabilities`: the contributor chain, and the check that
--- catches a completion stack contributing nothing.
---
--- This is the module roadmap finding B1 lived in -- a broken merge that fell
--- back silently, so servers advertised a poorer protocol and the editor just
--- felt worse with nothing pointing at the cause. Every case below is about
--- that failure staying loud.

local capabilities = require("lsp.core.capabilities")

--- A capability table with a completion section, i.e. what a real completion
--- engine contributes.
---@return table
local function with_completion()
  return {
    textDocument = {
      completion = {
        completionItem = { snippetSupport = true },
      },
    },
  }
end

describe("lsp.core.capabilities", function()
  describe("without contributors", function()
    it("still produces usable completion capabilities", function()
      local caps = capabilities.get({})
      assert.is_not_nil(caps.textDocument.completion)
      assert.is_true(caps.textDocument.completion.completionItem.snippetSupport)
    end)

    it("does not cry wolf when no engine contributed", function()
      -- Neovim's own `make_client_capabilities()` already carries a completion
      -- section, so "no contributors" is a poorer setup, not a broken one. The
      -- error branch below guards against a contributor *removing* the
      -- section, which is the case that actually looks like nothing.
      local _, warnings = capabilities.get({})
      for _, w in ipairs(warnings) do
        assert.are_not.equal("error", w.level, "unexpected error: " .. tostring(w.msg))
      end
    end)

    it("treats a nil contributor list like an empty one", function()
      assert.has_no.errors(function()
        capabilities.get(nil)
      end)
    end)
  end)

  describe("contributors", function()
    it("applies what a contributor returns", function()
      local caps = capabilities.get({
        function(c)
          return vim.tbl_deep_extend("force", c, with_completion())
        end,
      })
      assert.is_true(caps.textDocument.completion.completionItem.snippetSupport)
    end)

    it("leaves the table alone when a contributor returns nil", function()
      local caps = capabilities.get({
        function()
          return nil
        end,
      })
      assert.is_not_nil(caps.textDocument)
    end)

    it("propagates a contributor's warnings", function()
      local _, warnings = capabilities.get({
        function(c)
          return vim.tbl_deep_extend("force", c, with_completion()),
            { { level = "warn", msg = "from the contributor" } }
        end,
      })
      local found = false
      for _, w in ipairs(warnings) do
        if w.msg == "from the contributor" then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("applies contributors in order, so a later one wins", function()
      local caps = capabilities.get({
        function(c)
          return vim.tbl_deep_extend("force", c, { marker = "first" })
        end,
        function(c)
          return vim.tbl_deep_extend("force", c, { marker = "second" })
        end,
      })
      assert.are.equal("second", caps.marker)
    end)

    it("records a throwing contributor and keeps going", function()
      -- Blast-radius control: one broken adapter must not cost the whole
      -- capability set, but it must not pass unnoticed either.
      local reached = false
      local caps, warnings = capabilities.get({
        function()
          error("adapter exploded")
        end,
        function(c)
          reached = true
          return vim.tbl_deep_extend("force", c, with_completion())
        end,
      })

      assert.is_true(reached, "the contributor after the failing one still ran")
      assert.is_true(caps.textDocument.completion.completionItem.snippetSupport)

      local mentioned = false
      for _, w in ipairs(warnings) do
        if w.msg:find("contributor failed", 1, true) then
          mentioned = true
        end
      end
      assert.is_true(mentioned, "the failure is reported")
    end)

    it("warns when a completion stack contributed no completion section", function()
      local _, warnings = capabilities.get({
        function(c)
          local stripped = vim.deepcopy(c)
          stripped.textDocument.completion = nil
          return stripped
        end,
      })
      assert.is_true(#warnings > 0)
    end)
  end)

  describe("apply_globally", function()
    it("passes its contributors through to get()", function()
      local seen = false
      local ok, warnings = capabilities.apply_globally({
        function(c)
          seen = true
          return vim.tbl_deep_extend("force", c, with_completion())
        end,
      })
      assert.is_true(seen, "the contributor was called")
      assert.are.equal("boolean", type(ok))
      assert.are.equal("table", type(warnings))
    end)
  end)
end)
