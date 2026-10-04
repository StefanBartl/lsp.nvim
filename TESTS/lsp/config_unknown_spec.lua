--- Covers the unknown-key warning: a misspelled option must be reported, and
--- every documented option -- including the ones that merely *look* free-form
--- -- must stay quiet.
---
--- The false-positive direction is the dangerous one. A warning that fires on a
--- valid config teaches people to ignore `:checkhealth lsp`. Driving the "valid
--- config" cases off `DEFAULTS` alone cannot catch an option that `DEFAULTS`
--- forgot, which is how `diagnostics.*` and `lspdoctor.show_*` slipped through
--- the first version; hence the cases that start from the *consumer* side.

describe("lsp.config unknown keys", function()
  local DEFAULTS = require("lsp.config.DEFAULTS")
  local PRESETS = require("lsp.config.PRESETS")
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
      local layer = {
        completion = {
          personal_names = {
            labels = function()
              return {}
            end,
          },
        },
      }
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

    it("treats diagnostics as a pass-through to vim.diagnostic.config()", function()
      local layer = {
        diagnostics = {
          ui = "native",
          virtual_text = false,
          severity_sort = true,
          signs = { text = {} },
          float = { border = "rounded" },
        },
      }
      assert.are.same({}, unknown.scan(layer, DEFAULTS))
    end)

    it("ignores a non-table layer and a table where a scalar is expected", function()
      assert.are.same({}, unknown.scan(nil, DEFAULTS))
      assert.are.same({}, unknown.scan({ rename = "native" }, DEFAULTS))
    end)

    it("does not throw on odd keys", function()
      local layer = { [1] = "x", [true] = 1, ["a\nb"] = 2, [""] = 3, mason = { [2.5] = 1 } }
      assert.has_no.errors(function()
        unknown.scan(layer, DEFAULTS)
      end)
    end)
  end)

  describe("every option a consumer reads is known", function()
    --- Top-level keys of the `Defaults` table in `lsp/lspdoctor/init.lua`,
    --- read from the source: the table is file-local, and a spelled-out copy
    --- here would drift exactly like the hand-written list this guards against.
    ---@return string[]
    local function lspdoctor_option_names()
      local path = vim.api.nvim_get_runtime_file("lua/lsp/lspdoctor/init.lua", false)[1]
      assert.is_truthy(path)
      local names, inside = {}, false
      for line in io.lines(path) do
        if line:match("^local Defaults = {") then
          inside = true
        elseif inside and line:match("^}") then
          break
        elseif inside then
          local name = line:match("^  ([%a_][%w_]*) =")
          if name then
            names[#names + 1] = name
          end
        end
      end
      return names
    end

    it("lists every key lsp.lspdoctor accepts in DEFAULTS.lspdoctor", function()
      local names = lspdoctor_option_names()
      assert.is_true(#names >= 8)
      for _, name in ipairs(names) do
        assert.is_not_nil(DEFAULTS.lspdoctor[name], "DEFAULTS.lspdoctor." .. name)
      end
    end)

    it("is silent for the lspdoctor report switches", function()
      local config = reload()
      config.setup({
        lspdoctor = {
          show_capabilities = false,
          show_workspace = false,
          show_tools = false,
          show_conflicts = false,
        },
      })
      assert.is_false(has(config.warnings(), "unknown option"))
    end)

    it("is silent for ordinary diagnostics overrides", function()
      local config = reload()
      config.setup({ diagnostics = { virtual_text = false, severity_sort = true } })
      assert.is_false(has(config.warnings(), "unknown option"))
    end)

    it("is silent for every shipped preset", function()
      for name, preset in pairs(PRESETS) do
        assert.are.same({}, unknown.scan(preset, DEFAULTS), name)
      end
    end)
  end)

  describe("message text", function()
    it("escapes control characters and cuts long paths", function()
      local text = unknown.message({ path = "a\nb\27[31m" .. string.rep("x", 500) }, "setup()")
      assert.is_nil(text:find("%c"))
      assert.is_truthy(text:find("\\x0a", 1, true))
      assert.is_true(#text < 200)
    end)

    it("caps the warnings of one layer and says how many were left out", function()
      local findings = {}
      for i = 1, 50 do
        findings[i] = { path = "k" .. i }
      end
      local out = unknown.messages(findings, "setup()")
      assert.are.equal(21, #out)
      assert.is_truthy(out[21]:find("and 30 more", 1, true))
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

    it("really skips the preset layer (a key planted in a preset stays silent)", function()
      -- Without a planted key the case above also passes when the skip is gone,
      -- as soon as every shipped preset scans clean.
      local lean = PRESETS.lean
      lean.bogus_preset_key = 1
      local ok, err = pcall(function()
        local config = reload()
        config.setup({ preset = "lean" })
        assert.is_false(has(config.warnings(), "bogus_preset_key"))

        config = reload()
        config.setup({ preset = "lean", bogus_preset_key = 1 })
        assert.is_true(has(config.warnings(), "bogus_preset_key"))
      end)
      lean.bogus_preset_key = nil
      assert(ok, err)
    end)
  end)

  describe("hostile .nvim-lsp.json", function()
    local original_cwd
    local dir

    before_each(function()
      original_cwd = vim.fn.getcwd()
    end)

    after_each(function()
      vim.fn.chdir(original_cwd)
      if dir then
        vim.fn.delete(dir, "rf")
        dir = nil
      end
    end)

    it("cannot put control characters or an unbounded flood into the warnings", function()
      dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      local keys = { '"evil\\nINJECTED\\u001b[31m": 1' }
      for i = 1, 200 do
        keys[#keys + 1] = ('"junk%d": 1'):format(i)
      end
      -- `formatter` is on the project allowlist, so its keys are scanned.
      local body = '{ "formatter": { ' .. table.concat(keys, ", ") .. " } }"
      vim.fn.writefile({ body }, dir .. "/.nvim-lsp.json")

      -- Loaded before the chdir: afterwards the runtimepath no longer resolves
      -- `lsp.config` (see config_layers_spec.lua).
      local config = reload()
      vim.fn.chdir(dir)
      assert.has_no.errors(function()
        config.setup({})
      end)

      local warnings = config.warnings()
      assert.is_true(#warnings <= 25)
      for _, w in ipairs(warnings) do
        assert.is_nil(w:find("%c"), w)
      end
      assert.is_true(has(warnings, "more unknown options"))
    end)
  end)
end)
