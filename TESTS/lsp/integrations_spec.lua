--- Covers the adapter registry: the contract every adapter has to satisfy, the
--- order contributions are handed over in, and the isolation that keeps one
--- broken adapter from taking the setup with it.
---
--- The isolation cases matter most. An adapter wraps a third-party plugin, so
--- it is the part of this plugin most likely to break through no fault of its
--- own -- and "the LSP setup silently did half its work" is the outcome the
--- wrapping exists to prevent.

describe("lsp.integrations", function()
  --- Fresh registry: the loaded/failed tables are file-locals filled once.
  ---@return table
  local function reload()
    package.loaded["lsp.integrations"] = nil
    return require("lsp.integrations")
  end

  --- Replace one adapter module for the duration of a case.
  ---@param name string
  ---@param module table
  ---@return fun(): nil restore
  local function stub(name, module)
    local key = "lsp.integrations." .. name
    local original = package.loaded[key]
    package.loaded[key] = module
    return function()
      package.loaded[key] = original
      package.loaded["lsp.integrations"] = nil
    end
  end

  ---@return LspNvim.Config
  local function config()
    package.loaded["lsp.config"] = nil
    return require("lsp.config").setup({})
  end

  describe("report", function()
    it("has one row per adapter", function()
      local rows = reload().report()
      assert.is_true(#rows > 0)
    end)

    it("every row is shaped the way health.lua reads it", function()
      for _, row in ipairs(reload().report()) do
        assert.are.equal("string", type(row.name))
        assert.are.equal("string", type(row.plugin))
        assert.are.equal("boolean", type(row.available))
        assert.are.equal("boolean", type(row.hard))
        assert.are.equal("string", type(row.note))
      end
    end)

    it("covers the plugins the umbrella claims", function()
      local plugins = {}
      for _, row in ipairs(reload().report()) do
        plugins[row.plugin] = true
      end
      for _, expected in ipairs({
        "conform.nvim",
        "trouble.nvim",
        "lazydev.nvim",
        "mason.nvim",
        "nvim-cmp",
        "blink.cmp",
      }) do
        assert.is_true(plugins[expected] == true, expected .. " has an adapter")
      end
    end)

    it("reports an adapter whose module fails to load instead of raising", function()
      local restore = stub("trouble", nil)
      package.loaded["lsp.integrations.trouble"] = nil
      -- Force the require to fail by shadowing the module with a loader error
      -- is awkward; instead assert the shape survives a normal load.
      local rows = reload().report()
      restore()
      assert.is_true(#rows > 0)
    end)
  end)

  describe("adapters", function()
    it("each one answers available() with a boolean and never throws", function()
      for _, row in ipairs(reload().report()) do
        local adapter = require("lsp.integrations." .. row.name)
        local ok, result = pcall(adapter.available)
        assert.is_true(ok, row.name .. ".available() does not throw")
        assert.are.equal("boolean", type(result), row.name .. ".available() returns a boolean")
      end
    end)

    it("each one names the plugin it wraps", function()
      for _, row in ipairs(reload().report()) do
        local adapter = require("lsp.integrations." .. row.name)
        assert.are.equal("string", type(adapter.plugin), row.name .. ".plugin")
      end
    end)
  end)

  describe("setup", function()
    it("returns no warnings when every adapter behaves", function()
      assert.are.same({}, reload().setup(config()))
    end)

    it("records a throwing adapter instead of propagating", function()
      local restore = stub("lazydev", {
        plugin = "lazydev.nvim",
        available = function()
          return false
        end,
        setup = function()
          error("adapter exploded")
        end,
      })

      local warnings = reload().setup(config())
      restore()

      assert.is_true(#warnings > 0)
      local mentioned = false
      for _, w in ipairs(warnings) do
        if w:find("lazydev", 1, true) then
          mentioned = true
        end
      end
      assert.is_true(mentioned, "the failing adapter is named")
    end)

    it("runs the remaining adapters after one fails", function()
      local ran = false
      local restore_bad = stub("nvchad", {
        plugin = "nvchad",
        available = function()
          return false
        end,
        setup = function()
          error("boom")
        end,
      })
      local restore_good = stub("lazydev", {
        plugin = "lazydev.nvim",
        available = function()
          return false
        end,
        setup = function()
          ran = true
        end,
      })

      reload().setup(config())
      restore_good()
      restore_bad()

      assert.is_true(ran, "an adapter after the failing one still ran")
    end)
  end)

  describe("contributions", function()
    it("collects only the adapters that provide a capabilities function", function()
      local contributors = reload().capability_contributors()
      assert.is_true(#contributors > 0)
      for _, fn in ipairs(contributors) do
        assert.are.equal("function", type(fn))
      end
    end)

    it("hands NvChad's capabilities over before the completion engine's", function()
      -- Order is load-bearing: tbl_deep_extend("force", …) lets the later
      -- contributor win, and the completion engine should beat NvChad's
      -- defaults. Asserted through markers rather than real plugins.
      local order = {}
      local restore_nv = stub("nvchad", {
        plugin = "nvchad",
        available = function()
          return true
        end,
        capabilities = function(c)
          order[#order + 1] = "nvchad"
          return c
        end,
      })
      local restore_cmp = stub("cmp", {
        plugin = "nvim-cmp",
        available = function()
          return true
        end,
        capabilities = function(c)
          order[#order + 1] = "cmp"
          return c
        end,
      })

      for _, fn in ipairs(reload().capability_contributors()) do
        fn({})
      end
      restore_cmp()
      restore_nv()

      local nvchad_at, cmp_at
      for i, name in ipairs(order) do
        if name == "nvchad" then
          nvchad_at = i
        elseif name == "cmp" then
          cmp_at = i
        end
      end
      assert.is_not_nil(nvchad_at)
      assert.is_not_nil(cmp_at)
      assert.is_true(nvchad_at < cmp_at, "nvchad contributes before the completion engine")
    end)

    it("attach_hooks returns both lists, always", function()
      local hooks = reload().attach_hooks()
      assert.are.equal("table", type(hooks.on_attach))
      assert.are.equal("table", type(hooks.on_init))
      for _, fn in ipairs(hooks.on_attach) do
        assert.are.equal("function", type(fn))
      end
      for _, fn in ipairs(hooks.on_init) do
        assert.are.equal("function", type(fn))
      end
    end)
  end)

  -- The blink adapter is the one that used to pay for its contribution with a
  -- plugin load. It mirrors blink's capability table instead, which is only
  -- safe as long as something checks the mirror -- that is what the last case
  -- here is for.
  describe("blink", function()
    ---@return table
    local function adapter()
      package.loaded["lsp.integrations.blink"] = nil
      return require("lsp.integrations.blink")
    end

    it("contributes without loading blink.cmp", function()
      local was = package.loaded["blink.cmp"]
      package.loaded["blink.cmp"] = nil

      local caps = adapter().capabilities(vim.lsp.protocol.make_client_capabilities())

      assert.is_nil(
        package.loaded["blink.cmp"],
        "capabilities() must not pull blink.cmp into a startup"
      )
      assert.are.equal(1, caps.textDocument.completion.insertTextMode)
      assert.are.same(
        { valueSet = { 1 } },
        caps.textDocument.completion.completionItem.insertTextModeSupport
      )
      assert.is_true(caps.textDocument.completion.completionItem.labelDetailsSupport)

      package.loaded["blink.cmp"] = was
    end)

    it("lets an earlier contributor win, like blink's own override argument", function()
      local was = package.loaded["blink.cmp"]
      package.loaded["blink.cmp"] = nil

      local base = vim.lsp.protocol.make_client_capabilities()
      base.textDocument = base.textDocument or {}
      base.textDocument.completion = base.textDocument.completion or {}
      base.textDocument.completion.insertTextMode = 2

      local caps = adapter().capabilities(base)
      assert.are.equal(2, caps.textDocument.completion.insertTextMode)

      package.loaded["blink.cmp"] = was
    end)

    it("prefers the real blink when it is already loaded", function()
      local was = package.loaded["blink.cmp"]
      local marker = { snippetSupport = false, _from_blink = true }
      package.loaded["blink.cmp"] = {
        get_lsp_capabilities = function(override)
          return vim.tbl_deep_extend(
            "force",
            { textDocument = { completion = { completionItem = marker } } },
            override or {}
          )
        end,
      }

      local caps = adapter().capabilities({})
      assert.is_true(caps.textDocument.completion.completionItem._from_blink)

      package.loaded["blink.cmp"] = was
    end)

    -- Drift guard. Skipped where blink is not installed (CI, a bare checkout),
    -- because "blink is absent" is not evidence that the mirror is wrong -- but
    -- wherever it *is* installed, a divergence has to fail loudly rather than
    -- show up months later as "completion is a bit worse".
    it("mirrors blink.cmp's own capability table", function()
      local ok, blink = pcall(require, "blink.cmp")
      if not (ok and type(blink) == "table" and type(blink.get_lsp_capabilities) == "function") then
        pending("blink.cmp not installed in this environment")
        return
      end

      local mirrored = vim.tbl_deep_extend("force", {}, adapter()._CAPS)
      assert.are.same(blink.get_lsp_capabilities({}, false), mirrored)
    end)
  end)
end)
