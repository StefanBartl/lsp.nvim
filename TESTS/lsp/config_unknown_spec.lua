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

    it("cap boundary: 20 findings print in full, 21 add a summary of one", function()
      local findings = {}
      for i = 1, 20 do
        findings[i] = { path = "k" .. i }
      end
      assert.are.equal(20, #unknown.messages(findings, "setup()"))

      findings[21] = { path = "k21" }
      local out = unknown.messages(findings, "setup()")
      assert.are.equal(21, #out)
      assert.is_truthy(out[21]:find("and 1 more", 1, true))
      assert.are.same({}, unknown.messages({}, "setup()"))
    end)

    it("says what it means: unknown, not 'ignored by every consumer'", function()
      local text = unknown.message({ path = "mason.x" }, "setup()")
      assert.is_truthy(text:find("not in the documented option tree", 1, true))
      assert.is_nil(text:find("ignored by every consumer", 1, true))
    end)

    it("computes suggestions only for the findings that are printed", function()
      local mason = {}
      for i = 1, 100 do
        mason[("ensure_installing%03d"):format(i)] = true
      end
      local found = unknown.scan({ mason = mason }, DEFAULTS)
      assert.are.equal(100, #found)
      assert.are.equal("ensure_install", found[1].suggestion)
      assert.are.equal("ensure_install", found[unknown.MAX_PER_LAYER].suggestion)
      assert.is_nil(found[unknown.MAX_PER_LAYER + 1].suggestion)
    end)

    describe("sanitize()", function()
      it("cuts to exactly the limit, with an ellipsis", function()
        local out = unknown.sanitize(string.rep("x", 500), 80)
        assert.are.equal(80, #out)
        assert.are.equal("...", out:sub(-3))
      end)

      it("leaves text at the limit alone", function()
        local text = string.rep("x", 80)
        assert.are.equal(text, unknown.sanitize(text, 80))
      end)

      it("never cuts inside a multi-byte character", function()
        for max = 20, 24 do
          local out = unknown.sanitize(string.rep("\195\164", 100), max) -- 100 x "ä"
          local body = out:sub(1, -4)
          assert.are.equal(string.rep("\195\164", #body / 2), body, max)
        end
      end)

      it("escapes the control characters, including NUL and DEL", function()
        assert.are.equal("a\\x00b\\x7fc\\x0a", unknown.sanitize("a\0b\127c\n", 80))
      end)

      it("does not walk a huge input in full", function()
        local huge = string.rep("\n", 20 * 1000 * 1000)
        local start = vim.uv.hrtime()
        local out = unknown.sanitize(huge, 80)
        local elapsed_ms = (vim.uv.hrtime() - start) / 1e6
        assert.are.equal(80, #out)
        assert.is_true(elapsed_ms < 500, elapsed_ms)
      end)
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

    --- Write `body` as the project file, run `setup()` from inside that
    --- directory, and hand back the module and its warnings.
    ---@param body string
    ---@return table config, string[] warnings
    local function setup_in_project(body)
      dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      vim.fn.writefile({ body }, dir .. "/.nvim-lsp.json")

      -- Loaded before the chdir: afterwards the runtimepath no longer resolves
      -- `lsp.config` (see config_layers_spec.lua).
      local config = reload()
      vim.fn.chdir(dir)
      assert.has_no.errors(function()
        config.setup({})
      end)
      return config, config.warnings()
    end

    ---@param warnings string[]
    local function assert_safe(warnings)
      assert.is_true(#warnings > 0)
      for _, w in ipairs(warnings) do
        assert.is_nil(w:find("%c"), w)
        assert.is_true(#w <= unknown.MAX_WARNING, #w)
      end
    end

    it("cannot put control characters or an unbounded flood into the warnings", function()
      local keys = { '"evil\\nINJECTED\\u001b[31m": 1' }
      for i = 1, 200 do
        keys[#keys + 1] = ('"junk%d": 1'):format(i)
      end
      -- `formatter` is on the project allowlist, so its keys are scanned.
      local _, warnings =
        setup_in_project('{ "formatter": { ' .. table.concat(keys, ", ") .. " } }")

      assert.is_true(#warnings <= 25)
      assert_safe(warnings)
      assert.is_true(has(warnings, "more unknown options"))
    end)

    it("sanitizes the warning for a key the project file may not set", function()
      -- This warning is built in `project.lua`, not by `lsp.config.unknown`.
      local _, warnings = setup_in_project(
        '{ "evil\\nINJECTED\\u001b[31m": 1, "' .. string.rep("L", 3000) .. '": 2 }'
      )
      assert.is_true(has(warnings, "cannot be set from a project file"))
      assert_safe(warnings)
    end)

    it("lists at most a handful of refused keys, keeping the explanation", function()
      local keys = {}
      for i = 1, 30 do
        keys[i] = ('"refused%02d": 1'):format(i)
      end
      local _, warnings = setup_in_project("{ " .. table.concat(keys, ", ") .. " }")
      assert.is_true(has(warnings, "and 22 more"))
      -- The sentence after the key list is the part that tells the user what to do.
      assert.is_true(has(warnings, "(allowed: "))
      assert_safe(warnings)
    end)

    it("sanitizes warnings about VALUES the project file supplies", function()
      -- Built by `warn()` with `%q`/`vim.inspect`, i.e. from the value itself.
      local _, warnings = setup_in_project(
        '{ "lightbulb": { "render": "a\\nb\\u001b[31m' .. string.rep("x", 3000) .. '" } }'
      )
      assert.is_true(has(warnings, "lightbulb.render"))
      assert_safe(warnings)
    end)

    it("drops a server name with a control character", function()
      local config, warnings = setup_in_project('{ "servers": ["lua_ls", "evil\\nname"] }')
      assert_safe(warnings)
      assert.are.same({ "lua_ls" }, config.get().servers)
    end)
  end)
end)
