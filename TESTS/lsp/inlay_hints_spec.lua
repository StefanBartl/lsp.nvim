--- Covers `lsp.core.inlay_hints`: the resolution of the global default
--- against the per-filetype overrides, and the config normalization that feeds
--- it.
---
--- The resolution is where the bugs would live, because it has three states
--- and Lua only gives you two: an override that is `false` and an override
--- that is absent both look falsy at a careless call site, and the second must
--- inherit the global while the first must not. Every case below exists to pin
--- one of the four combinations of (global, override) down.
---
--- `vim.lsp.inlay_hint` itself is not exercised -- there is no language server
--- in the harness, so `apply_to()` finds no buffer with an `inlayHintProvider`
--- and does nothing. That is the point: the state machine has to be correct
--- without a server, since it is what decides what the server is asked for.

describe("lsp.core.inlay_hints", function()
  --- Fresh module state per case: the toggle is a file-local, so a previous
  --- `set()` would leak into the next assertion.
  ---@return table
  local function reload()
    package.loaded["lsp.core.inlay_hints"] = nil
    return require("lsp.core.inlay_hints")
  end

  describe("resolution", function()
    it("falls back to the global default for a filetype with no override", function()
      local hints = reload()
      hints.setup({ enable = true })

      assert.is_true(hints.enabled(nil))
      assert.is_true(hints.enabled("lua"))
      assert.is_true(hints.enabled("anything-at-all"))
    end)

    it("lets an override say 'off here' against a global on", function()
      local hints = reload()
      hints.setup({ enable = true, filetypes = { lua = false } })

      assert.is_true(hints.enabled(nil))
      assert.is_false(hints.enabled("lua"))
      assert.is_true(hints.enabled("go"))
    end)

    it("lets an override say 'on here' against a global off", function()
      local hints = reload()
      hints.setup({ enable = false, filetypes = { go = true } })

      assert.is_false(hints.enabled(nil))
      assert.is_true(hints.enabled("go"))
      assert.is_false(hints.enabled("lua"))
    end)

    -- The distinction the whole design rests on. `false` and absent are both
    -- falsy, so a lookup that does not separate them silently loses the
    -- override.
    it("distinguishes an explicit false from an absent key", function()
      local hints = reload()
      hints.setup({ enable = true, filetypes = { lua = false } })

      assert.is_false(hints.enabled("lua"))
      assert.is_true(hints.enabled("markdown"))
      assert.are.same({ "lua" }, hints.overridden())
    end)
  end)

  describe("setup", function()
    it("drops override entries that are not filetype -> boolean", function()
      local hints = reload()
      ---@diagnostic disable-next-line: assign-type-mismatch
      hints.setup({ enable = false, filetypes = { lua = "yes", [1] = true, go = true } })

      assert.are.same({ "go" }, hints.overridden())
    end)

    it("replaces the previous state rather than merging into it", function()
      local hints = reload()
      hints.setup({ enable = true, filetypes = { lua = false } })
      hints.setup({ enable = false })

      assert.are.same({}, hints.overridden())
      assert.is_false(hints.enabled("lua"))
    end)
  end)

  describe("toggle", function()
    it("flips the global default", function()
      local hints = reload()
      hints.setup({ enable = false })

      hints.toggle(nil)
      assert.is_true(hints.enabled(nil))
      hints.toggle(nil)
      assert.is_false(hints.enabled(nil))
    end)

    -- Toggling a filetype has to write an override even when the result equals
    -- the global, or a later global change would silently undo it.
    it("writes an explicit override even when the value matches the global", function()
      local hints = reload()
      hints.setup({ enable = true })

      hints.toggle("lua") -- true -> false, and now pinned
      assert.are.same({ "lua" }, hints.overridden())
      assert.is_false(hints.enabled("lua"))

      hints.toggle("lua") -- false -> true, still pinned
      assert.are.same({ "lua" }, hints.overridden())

      hints.set(false, nil)
      assert.is_false(hints.enabled(nil))
      assert.is_true(hints.enabled("lua")) -- the pin survived the global change
    end)

    it("clear() gives a filetype back to the global default", function()
      local hints = reload()
      hints.setup({ enable = true, filetypes = { lua = false } })

      hints.clear("lua")
      assert.are.same({}, hints.overridden())
      assert.is_true(hints.enabled("lua"))
    end)

    it("clear() on a filetype without an override is a no-op", function()
      local hints = reload()
      hints.setup({ enable = true })

      hints.clear("lua")
      assert.are.same({}, hints.overridden())
      assert.is_true(hints.enabled("lua"))
    end)
  end)

  describe("config", function()
    ---@return table
    local function reload_config()
      package.loaded["lsp.config"] = nil
      return require("lsp.config")
    end

    it("defaults to off with no overrides", function()
      local cfg = reload_config().setup()

      assert.is_false(cfg.inlay_hints.enable)
      assert.are.same({}, cfg.inlay_hints.filetypes)
    end)

    it("keeps a well-formed override map", function()
      local cfg = reload_config().setup({
        inlay_hints = { enable = true, filetypes = { lua = false, go = true } },
      })

      assert.is_true(cfg.inlay_hints.enable)
      assert.is_false(cfg.inlay_hints.filetypes.lua)
      assert.is_true(cfg.inlay_hints.filetypes.go)
    end)

    -- The mistake this catches is a list where a map belongs: it type-checks
    -- as a table, resolves every lookup to nil, and overrides nothing.
    it("warns about a list instead of a filetype -> boolean map", function()
      local config = reload_config()
      ---@diagnostic disable-next-line: assign-type-mismatch
      local cfg = config.setup({ inlay_hints = { filetypes = { "lua", "go" } } })

      assert.are.same({}, cfg.inlay_hints.filetypes)
      local warned = false
      for _, w in ipairs(config.warnings()) do
        if w:find("inlay_hints.filetypes", 1, true) then
          warned = true
        end
      end
      assert.is_true(warned)
    end)

    it("falls back to the default when the whole table is replaced", function()
      local config = reload_config()
      ---@diagnostic disable-next-line: assign-type-mismatch
      local cfg = config.setup({ inlay_hints = false })

      assert.is_false(cfg.inlay_hints.enable)
      assert.are.same({}, cfg.inlay_hints.filetypes)
    end)
  end)
end)
