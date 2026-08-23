--- Covers `lsp.config`'s merge and normalization: the layer that decides what
--- every other module gets to assume about its options.
---
--- Normalization is the part worth testing hardest. It exists so a typo costs a
--- feature instead of the startup, which means its failure mode is *silent* --
--- a value that degrades wrongly looks exactly like a value the user chose.

describe("lsp.config", function()
  --- Fresh module state per case: `_active` and `_warnings` are file-locals, so
  --- a previous setup() would leak into the next assertion.
  ---@return table
  local function reload()
    package.loaded["lsp.config"] = nil
    return require("lsp.config")
  end

  local DEFAULTS = require("lsp.config.DEFAULTS")

  describe("defaults", function()
    it("setup() without options yields a complete config", function()
      local cfg = reload().setup()

      assert.is_true(cfg.keymaps.enable)
      assert.are.equal("default", cfg.keymaps.preset)
      assert.is_true(cfg.usrcmds.enable)
      assert.is_true(cfg.which_key.enable)
      assert.are.equal("auto", cfg.rename.provider)
      assert.is_true(#cfg.servers > 0)
    end)

    it("clean defaults produce no warnings", function()
      local config = reload()
      config.setup()
      assert.are.same({}, config.warnings())
    end)

    it("get() before setup() still returns the defaults", function()
      local cfg = reload().get()
      assert.are.equal("default", cfg.keymaps.preset)
    end)

    it("user options do not mutate DEFAULTS", function()
      local before = vim.deepcopy(DEFAULTS.servers)
      reload().setup({ servers = { "only_one" } })
      assert.are.same(before, DEFAULTS.servers)
    end)
  end)

  describe("servers", function()
    it("keeps a valid list as given", function()
      local cfg = reload().setup({ servers = { "lua_ls", "gopls" } })
      assert.are.same({ "lua_ls", "gopls" }, cfg.servers)
    end)

    it("falls back to the defaults on an empty list", function()
      -- "No language server at all" looks exactly like a broken install, so it
      -- must never be what an empty list produces.
      local config = reload()
      local cfg = config.setup({ servers = {} })
      assert.is_true(#cfg.servers > 0)
      assert.is_true(#config.warnings() > 0)
    end)

    it("falls back when it is not a list at all", function()
      local cfg = reload().setup({ servers = "lua_ls" })
      assert.is_true(#cfg.servers > 0)
    end)

    it("drops non-string entries and keeps the rest", function()
      local config = reload()
      local cfg = config.setup({ servers = { "lua_ls", 42, false, "gopls" } })
      assert.are.same({ "lua_ls", "gopls" }, cfg.servers)
      assert.is_true(#config.warnings() >= 2)
    end)

    it("falls back when every entry was dropped", function()
      local cfg = reload().setup({ servers = { 1, 2, 3 } })
      assert.is_true(#cfg.servers > 0)
    end)
  end)

  describe("keymaps", function()
    it("falls back on an unknown preset and says so", function()
      local config = reload()
      local cfg = config.setup({ keymaps = { preset = "nonsense" } })
      assert.are.equal("default", cfg.keymaps.preset)
      assert.is_true(#config.warnings() > 0)
    end)

    it("accepts every preset the catalogue defines", function()
      local KEYMAPS = require("lsp.config.KEYMAPS")
      for preset in pairs(KEYMAPS.presets) do
        local cfg = reload().setup({ keymaps = { preset = preset } })
        assert.are.equal(preset, cfg.keymaps.preset, "preset " .. preset .. " survives merge")
      end
    end)

    it("replaces a malformed override table with an empty one", function()
      local cfg = reload().setup({ keymaps = { map = "nope" } })
      assert.are.same({}, cfg.keymaps.map)
    end)

    it("keeps overrides untouched", function()
      local cfg = reload().setup({ keymaps = { map = { rename = false, qf_next = "<leader>zz" } } })
      assert.is_false(cfg.keymaps.map.rename)
      assert.are.equal("<leader>zz", cfg.keymaps.map.qf_next)
    end)

    it("recovers when keymaps is replaced by a non-table", function()
      local cfg = reload().setup({ keymaps = false })
      assert.is_true(cfg.keymaps.enable)
      assert.are.equal("default", cfg.keymaps.preset)
    end)
  end)

  describe("rename.provider", function()
    for _, provider in ipairs({ "auto", "inc_rename", "native" }) do
      it(("accepts %q"):format(provider), function()
        local cfg = reload().setup({ rename = { provider = provider } })
        assert.are.equal(provider, cfg.rename.provider)
      end)
    end

    it("falls back to auto on an unknown value and says so", function()
      local config = reload()
      local cfg = config.setup({ rename = { provider = "magic" } })
      assert.are.equal("auto", cfg.rename.provider)
      assert.is_true(#config.warnings() > 0)
    end)
  end)

  describe("sub-tables", function()
    -- Deep-merge fills the fields; this catches the `formatter = false` shape,
    -- where every field access downstream would error instead of degrading.
    for _, key in ipairs({
      "diagnostics",
      "formatter",
      "attach",
      "mason",
      "lspdoctor",
      "tools",
      "languages",
      "usrcmds",
      "which_key",
    }) do
      it(("restores %s when replaced by a non-table"):format(key), function()
        local cfg = reload().setup({ [key] = false })
        assert.are.equal("table", type(cfg[key]))
      end)
    end

    it("merges a partial sub-table over the defaults", function()
      local cfg = reload().setup({ formatter = { on_save = true } })
      assert.is_true(cfg.formatter.on_save)
      -- The field the user did not mention keeps its default rather than
      -- disappearing, which is the whole point of a deep merge.
      assert.are.equal(DEFAULTS.formatter.timeout_ms, cfg.formatter.timeout_ms)
    end)
  end)

  describe("warnings", function()
    it("are cleared by the next setup()", function()
      local config = reload()
      config.setup({ servers = {} })
      assert.is_true(#config.warnings() > 0)
      config.setup({})
      assert.are.same({}, config.warnings())
    end)

    it("records a non-table argument instead of raising", function()
      local config = reload()
      assert.has_no.errors(function()
        config.setup("not a table")
      end)
      assert.is_true(#config.warnings() > 0)
    end)
  end)
end)
