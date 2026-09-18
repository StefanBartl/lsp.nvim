--- Covers `lsp.core.filter`: the two pure diagnostic-list helpers
--- `lsp.core.handlers` sits on top of. Both operate on a plain list with no
--- LSP client involved, so every case here is a plain table in, plain table
--- out -- no stubbing needed.

describe("lsp.core.filter", function()
  local filter = require("lsp.core.filter")

  ---@param line integer
  ---@param message string
  ---@param extra table|nil
  ---@return table
  local function lsp_diag(line, message, extra)
    return vim.tbl_extend("force", {
      range = { start = { line = line, character = 0 }, ["end"] = { line = line, character = 4 } },
      severity = 1,
      source = "test_ls",
      message = message,
    }, extra or {})
  end

  ---@param lnum integer
  ---@param message string
  ---@return table
  local function vim_diag(lnum, message)
    return { lnum = lnum, col = 0, severity = 1, source = "test_ls", message = message }
  end

  describe("filter", function()
    it("passes everything through with no patterns configured", function()
      local diags = { lsp_diag(1, "unused variable") }
      assert.are.same(diags, filter.filter(diags, nil))
      assert.are.same(diags, filter.filter(diags, { patterns = {} }))
    end)

    it("drops entries whose message matches a configured pattern", function()
      local keep = lsp_diag(1, "unused variable 'x'")
      local drop = lsp_diag(2, "deprecated call")
      local out = filter.filter({ keep, drop }, { patterns = { "deprecated" } })

      assert.are.equal(1, #out)
      assert.are.equal(keep, out[1])
    end)

    it("drops on the first pattern that matches, checking every configured one", function()
      local a = lsp_diag(1, "foo warning")
      local b = lsp_diag(2, "bar warning")
      local c = lsp_diag(3, "baz warning")
      local out = filter.filter({ a, b, c }, { patterns = { "^foo", "^bar" } })

      assert.are.equal(1, #out)
      assert.are.equal(c, out[1])
    end)

    -- `msg:find(pat)` is a Lua pattern search, not a plain substring: a magic
    -- character in a configured pattern is not literal, and this is the case
    -- that would notice a silent switch to plain matching.
    it("treats a configured pattern as a Lua pattern, not a literal string", function()
      local diags = { lsp_diag(1, "value is 3.14 exactly") }
      -- "3.14" as a Lua pattern also matches "3x14" (`.` is "any character").
      local out = filter.filter(diags, { patterns = { "3.14" } })

      assert.are.equal(0, #out)
    end)

    it("ignores a non-string entry in patterns rather than raising", function()
      local diags = { lsp_diag(1, "unused variable") }
      ---@diagnostic disable-next-line: assign-type-mismatch
      local out = filter.filter(diags, { patterns = { 42, "" } })

      assert.are.equal(1, #out)
    end)

    it("treats an entry with no message as an empty string, not a crash", function()
      local diags = { lsp_diag(1, "") }
      diags[1].message = nil
      local out = filter.filter(diags, { patterns = { "unused" } })

      assert.are.equal(1, #out)
    end)

    it("returns the same list unchanged for an empty diagnostics table", function()
      local diags = {}
      assert.are.equal(diags, filter.filter(diags, { patterns = { "x" } }))
    end)

    it("returns non-table input unchanged instead of raising", function()
      ---@diagnostic disable-next-line: param-type-mismatch
      assert.is_nil(filter.filter(nil, { patterns = { "x" } }))
    end)
  end)

  describe("dedup", function()
    it("collapses exact duplicates and keeps the first occurrence", function()
      local first = lsp_diag(3, "unused")
      local second = lsp_diag(3, "unused")
      local out = filter.dedup({ first, second })

      assert.are.equal(1, #out)
      assert.are.equal(first, out[1])
    end)

    it("preserves order of the surviving entries", function()
      local a, b, c = lsp_diag(1, "a"), lsp_diag(2, "b"), lsp_diag(1, "a")
      local out = filter.dedup({ a, b, c })

      assert.are.same({ a, b }, out)
    end)

    -- The bug the module header documents: reading only `lnum`/`col` (the
    -- `vim.diagnostic` shape) against a raw LSP payload, which carries
    -- `range.start` instead, keys every entry at (0, 0) and collapses
    -- everything with the same message regardless of where it actually is.
    it("keys off range.start on a raw LSP payload, not lnum/col", function()
      local at_3 = lsp_diag(3, "unused")
      local at_42 = lsp_diag(42, "unused")
      local out = filter.dedup({ at_3, at_42 })

      assert.are.equal(2, #out)
    end)

    it("keys off lnum/col on the vim.diagnostic shape", function()
      local at_3 = vim_diag(3, "unused")
      local at_42 = vim_diag(42, "unused")
      local out = filter.dedup({ at_3, at_42 })

      assert.are.equal(2, #out)
    end)

    it("treats a different severity at the same position as distinct", function()
      local warn = lsp_diag(1, "shadowed", { severity = 2 })
      local err = lsp_diag(1, "shadowed", { severity = 1 })
      local out = filter.dedup({ warn, err })

      assert.are.equal(2, #out)
    end)

    it("treats a different source at the same position as distinct", function()
      local a = lsp_diag(1, "unused", { source = "eslint" })
      local b = lsp_diag(1, "unused", { source = "tsserver" })
      local out = filter.dedup({ a, b })

      assert.are.equal(2, #out)
    end)

    it("trims trailing whitespace from the message before comparing", function()
      local a = lsp_diag(1, "unused variable")
      local b = lsp_diag(1, "unused variable   ")
      local out = filter.dedup({ a, b })

      assert.are.equal(1, #out)
    end)

    it("does not mutate the input list", function()
      local diags = { lsp_diag(1, "x"), lsp_diag(1, "x") }
      local before = #diags
      filter.dedup(diags)

      assert.are.equal(before, #diags)
    end)

    it("returns the same list unchanged for an empty diagnostics table", function()
      local diags = {}
      assert.are.equal(diags, filter.dedup(diags))
    end)

    it("returns non-table input unchanged instead of raising", function()
      ---@diagnostic disable-next-line: param-type-mismatch
      assert.is_nil(filter.dedup(nil))
    end)
  end)
end)
