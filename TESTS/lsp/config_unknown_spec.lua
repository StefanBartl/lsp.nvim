--- Covers the unknown-key warning: a misspelled option must be reported, and
--- every documented option -- including the ones that merely *look* free-form
--- -- must stay quiet.
---
--- The false-positive direction is the dangerous one. A warning that fires on a
--- valid config teaches people to ignore `:checkhealth lsp`, so the "valid full
--- config" case is driven off `DEFAULTS` itself rather than a list written here.

describe("lsp.config unknown keys", function()
  local DEFAULTS = require("lsp.config.DEFAULTS")
  local unknown = require("lsp.config.unknown")

  ---@return table
  local function reload()
    package.loaded["lsp.config"] = nil
    return require("lsp.config")
  end

  ---@param warnings string[]
  ---@param needle string
  ---@return boolean
  local function has(warnings, needle)
    for _, w in ipairs(warnings) do
      if w:find(needle, 1, true) then
        return true
      end
    end
    return false
  end

  describe("scan()", function()
    it("reports a misspelled leaf with a suggestion", function()
      local found = unknown.scan({ mason = { ensure_installing = true } }, DEFAULTS)
      assert.are.equal(1, #found)
      assert.are.equal("mason.ensure_installing", found[1].path)
      assert.are.equal("ensure_install", found[1].suggestion)
    end)

    it("reports a misspelled top-level key", function()
      local found = unknown.scan({ lightbulbs = {} }, DEFAULTS)
      assert.are.equal("lightbulbs", found[1].path)
      assert.are.equal("lightbulb", found[1].suggestion)
    end)

    it("offers no suggestion for something far from every known key", function()
      local found = unknown.scan({ rename = { zzzzzzzz = 1 } }, DEFAULTS)
      assert.are.equal("rename.zzzzzzzz", found[1].path)
      assert.is_nil(found[1].suggestion)
    end)

    it("accepts the defaults themselves", function()
      assert.are.same({}, unknown.scan(vim.deepcopy(DEFAULTS), DEFAULTS))
    end)

    it("accepts the option whose default is nil", function()
      local layer = { completion = { personal_names = {
        labels = function()
          return {}
        end,
      } } }
      assert.are.same({}, unknown.scan(layer, DEFAULTS))
    end)

    it("does not look inside free-form maps and lists", function()
      local layer = {
        servers = { "lua_ls", "anything_goes" },
        inlay_hints = { filetypes = { whatever = true } },
        winbar = { max_symbols = { someft = 3 } },
        peek = { keys = { my_own_action = "x" } },
        implement = { kinds = { SomeKind = true } },
        mason = { overrides = { lsp = { ["any-package"] = false }, extra_family = {} } },
        keymaps = { map = { custom = "<leader>x" } },
        workspace = { markers = { ".custom-marker" } },
      }
      assert.are.same({}, unknown.scan(layer, DEFAULTS))
    end)

    it("ignores a non-table layer and a table where a scalar is expected", function()
      assert.are.same({}, unknown.scan(nil, DEFAULTS))
      assert.are.same({}, unknown.scan({ rename = "native" }, DEFAULTS))
    end)
  end)

  describe("setup()", function()
    it("warns about a misspelled option and names the layer", function()
      local config = reload()
      config.setup({ mason = { ensure_installing = true } })
      assert.is_true(has(config.warnings(), "mason.ensure_installing"))
      assert.is_true(has(config.warnings(), 'did you mean "ensure_install"'))
      assert.is_true(has(config.warnings(), "from setup()"))
    end)

    it("still keeps the value (warn, never fatal)", function()
      local cfg = reload().setup({ mason = { ensure_installing = true } })
      assert.is_true(cfg.mason.ensure_installing)
    end)

    it("is silent for a valid full config", function()
      local config = reload()
      config.setup(vim.deepcopy(DEFAULTS))
      assert.are.same({}, config.warnings())
    end)

    it("is silent for no options at all", function()
      local config = reload()
      config.setup()
      assert.are.same({}, config.warnings())
    end)

    it("does not blame a preset for keys the user did not write", function()
      for _, preset in ipairs({ "lean", "full" }) do
        local config = reload()
        config.setup({ preset = preset })
        assert.is_false(has(config.warnings(), "unknown option"), preset)
      end
    end)
  end)
end)
