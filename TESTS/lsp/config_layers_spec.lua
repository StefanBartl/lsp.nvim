--- Covers the three layers `lsp.config` resolves above `DEFAULTS`: the preset,
--- the `setup()` options, and the per-project `.nvim-lsp.json`.
---
--- The precedence is the feature, so it is what gets tested hardest. A preset
--- that overruled an explicit option, or a project file that did not, would
--- both look like "the config just does not apply" from the outside -- the
--- failure mode with the longest debugging time.

describe("lsp.config layers", function()
  --- Fresh module state per case: `_active`, `_warnings` and `_layers` are
  --- file-locals, so a previous setup() would leak into the next assertion.
  ---@return table
  local function reload()
    package.loaded["lsp.config"] = nil
    return require("lsp.config")
  end

  local DEFAULTS = require("lsp.config.DEFAULTS")
  local PRESETS = require("lsp.config.PRESETS")

  --- Does any warning mention this substring?
  ---@param warnings string[]
  ---@param needle string
  ---@return boolean
  local function mentions(warnings, needle)
    for _, w in ipairs(warnings) do
      if w:find(needle, 1, true) then
        return true
      end
    end
    return false
  end

  -- ###################################################################
  -- M6 -- profile presets

  describe("preset", function()
    it("default changes nothing", function()
      local plain = reload().setup()
      local named = reload().setup({ preset = "default" })
      assert.are.same(plain.tools, named.tools)
      assert.are.equal(plain.diagnostics.debounce_ms, named.diagnostics.debounce_ms)
    end)

    it("lean turns the continuous work down", function()
      local cfg = reload().setup({ preset = "lean" })

      assert.is_false(cfg.diagnostics.virtual_text)
      assert.is_false(cfg.attach.use_workspace_diagnostics)
      assert.is_false(cfg.tools.lsp_signature.enable)
      assert.is_false(cfg.usrcmds.legacy_aliases)
      assert.are.equal("minimal", cfg.keymaps.preset)
      assert.is_true(cfg.diagnostics.debounce_ms > DEFAULTS.diagnostics.debounce_ms)
    end)

    it("full turns the feedback up", function()
      local cfg = reload().setup({ preset = "full" })

      assert.is_true(cfg.inlay_hints.enable)
      assert.is_true(cfg.diagnostics.update_in_insert)
      assert.is_true(cfg.tools.lsp_signature.enable)
      assert.is_true(cfg.diagnostics.debounce_ms < DEFAULTS.diagnostics.debounce_ms)
    end)

    it("no preset installs software or starts writing files", function()
      -- The two side effects that reach outside the editor. "Everything on"
      -- must stay safe to pick without reading PRESETS.lua first.
      for _, name in ipairs({ "lean", "full" }) do
        local cfg = reload().setup({ preset = name })
        assert.is_false(cfg.mason.ensure_install)
        assert.is_false(cfg.formatter.on_save)
      end
    end)

    it("an explicit option wins over the preset", function()
      -- The preset moves the floor; it does not overrule what you wrote.
      local cfg = reload().setup({
        preset = "lean",
        inlay_hints = { enable = true },
        tools = { lsp_signature = { enable = true } },
      })

      assert.is_true(cfg.inlay_hints.enable)
      assert.is_true(cfg.tools.lsp_signature.enable)
      -- ... and the rest of the preset still applies.
      assert.is_false(cfg.attach.use_workspace_diagnostics)
    end)

    it("an unknown name degrades to default and says so", function()
      local config = reload()
      local cfg = config.setup({ preset = "fast" })

      assert.are.equal("default", cfg.preset)
      assert.is_true(mentions(config.warnings(), "preset"))
      -- Degrading to "no options at all" would be the worse failure: a typo in
      -- a profile name must not strip the plugin down.
      assert.is_true(cfg.tools.lsp_signature.enable)
    end)

    it("setup() does not mutate the preset tables", function()
      local before = vim.deepcopy(PRESETS.lean)
      reload().setup({ preset = "lean", servers = { "only_one" } })
      assert.are.same(before, PRESETS.lean)
    end)

    it("layers() reports which profile was applied", function()
      local config = reload()
      config.setup({ preset = "full" })
      assert.are.equal("full", config.layers().preset)
    end)
  end)

  -- ###################################################################
  -- M7 -- per-project override

  describe("project file", function()
    ---@type string[]
    local created = {}

    --- A throwaway directory with a project file in it, made current for the
    --- duration of the case. The lookup walks up from the working directory,
    --- so this is the only way to exercise the real path rather than a stub.
    ---
    --- Every case reloads `lsp.config` *before* calling this. Requiring a
    --- module while the working directory is a temp dir depends on how the
    --- runner set the runtimepath up, which is not what any of these cases is
    --- about -- only `setup()` needs to run from inside the project.
    ---@param content string|nil # File body; nil writes no file at all.
    ---@param name string|nil # File name, default `.nvim-lsp.json`.
    ---@return string dir
    local function project_dir(content, name)
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      created[#created + 1] = dir
      if content ~= nil then
        vim.fn.writefile(vim.split(content, "\n"), dir .. "/" .. (name or ".nvim-lsp.json"))
      end
      vim.fn.chdir(dir)
      return dir
    end

    local original_cwd

    before_each(function()
      original_cwd = vim.fn.getcwd()
    end)

    after_each(function()
      vim.fn.chdir(original_cwd)
      for _, dir in ipairs(created) do
        vim.fn.delete(dir, "rf")
      end
      created = {}
    end)

    it("switches a server off in this checkout only", function()
      -- The point of the whole layer: the global config is untouched.
      local config = reload()
      project_dir('{ "servers": ["lua_ls"] }')
      local cfg = config.setup({ servers = { "lua_ls", "ts_ls", "gopls" } })

      assert.are.same({ "lua_ls" }, cfg.servers)
    end)

    it("replaces a list instead of merging into it", function()
      -- Same reason as `servers` in setup(): index-wise array merging would
      -- leave every entry from index two on in place.
      local config = reload()
      project_dir('{ "workspace": { "markers": ["go.mod"] } }')
      local cfg = config.setup()

      assert.are.same({ "go.mod" }, cfg.workspace.markers)
    end)

    it("wins over the setup() options", function()
      local config = reload()
      project_dir('{ "formatter": { "on_save": true } }')
      local cfg = config.setup({ formatter = { on_save = false } })

      assert.is_true(cfg.formatter.on_save)
    end)

    it("is found by walking upward from the working directory", function()
      local config = reload()
      local root = project_dir('{ "languages": { "enable": false } }')
      local nested = root .. "/a/b"
      vim.fn.mkdir(nested, "p")
      vim.fn.chdir(nested)

      local cfg = config.setup()
      assert.is_false(cfg.languages.enable)
    end)

    it("layers() names the file that was merged", function()
      local config = reload()
      local dir = project_dir('{ "languages": { "enable": false } }')
      config.setup()

      local found = config.layers().project
      assert.is_not_nil(found)
      assert.is_true(vim.fs.normalize(found):find(vim.fs.normalize(dir), 1, true) == 1)
    end)

    it("refuses keys that are not the repository's to set", function()
      -- A checkout may describe the code. It may not move your keys or install
      -- software.
      local config = reload()
      project_dir([[{
        "servers": ["lua_ls"],
        "keymaps": { "enable": false },
        "mason": { "ensure_install": true }
      }]])
      local cfg = config.setup()

      assert.are.same({ "lua_ls" }, cfg.servers)
      assert.is_true(cfg.keymaps.enable)
      assert.is_false(cfg.mason.ensure_install)
      assert.is_true(mentions(config.warnings(), "keymaps"))
      assert.is_true(mentions(config.warnings(), "mason"))
    end)

    it("survives invalid JSON and says so", function()
      local config = reload()
      project_dir("{ not json")
      local cfg = config.setup({ servers = { "lua_ls" } })

      assert.are.same({ "lua_ls" }, cfg.servers)
      assert.is_true(mentions(config.warnings(), "JSON"))
    end)

    it("ignores an empty file without complaining", function()
      -- A placeholder someone has not filled in yet is not a mistake.
      local config = reload()
      project_dir("")
      config.setup()
      assert.are.same({}, config.warnings())
    end)

    it("reads JSON null as no opinion", function()
      local config = reload()
      project_dir('{ "servers": null }')
      local cfg = config.setup({ servers = { "lua_ls" } })
      assert.are.same({ "lua_ls" }, cfg.servers)
    end)

    it("is skipped entirely when project.enable is false", function()
      local config = reload()
      project_dir('{ "servers": ["lua_ls"] }')
      local cfg = config.setup({ project = { enable = false }, servers = { "gopls" } })

      assert.are.same({ "gopls" }, cfg.servers)
      assert.is_nil(config.layers().project)
    end)

    it("honours a different file name", function()
      local config = reload()
      project_dir('{ "servers": ["lua_ls"] }', ".lsp.json")
      local cfg = config.setup({ project = { file = ".lsp.json" }, servers = { "gopls" } })

      assert.are.same({ "lua_ls" }, cfg.servers)
    end)

    it("cannot decide whether project files are read", function()
      -- `project` is resolved from the layers below it, so the file cannot
      -- keep itself alive -- or, here, rename its own successor.
      local config = reload()
      project_dir('{ "project": { "enable": false }, "servers": ["lua_ls"] }')
      local cfg = config.setup({ servers = { "gopls" } })

      assert.are.same({ "lua_ls" }, cfg.servers)
      assert.is_true(mentions(config.warnings(), "project"))
    end)

    it("a malformed value degrades rather than raising", function()
      local config = reload()
      project_dir('{ "servers": "lua_ls" }')
      local cfg = config.setup({ servers = { "gopls" } })

      assert.is_true(#cfg.servers > 0)
      assert.is_true(mentions(config.warnings(), "servers"))
    end)
  end)

  -- ###################################################################
  -- Attribution -- the reason M6 and M7 were built together

  describe("warning attribution", function()
    it("names setup() for a value the user supplied", function()
      local config = reload()
      config.setup({ servers = { "lua_ls", 42 } })
      assert.is_true(mentions(config.warnings(), "(from setup())"))
    end)

    it("names the preset for a value the preset supplied", function()
      -- No shipped preset carries a bad value -- that is the point of shipping
      -- them -- so the case is constructed. Restored afterwards because the
      -- table is module state shared with every other spec.
      local saved = PRESETS.lean
      PRESETS.lean = { servers = { "lua_ls", 42 } }
      local config = reload()
      config.setup({ preset = "lean" })
      PRESETS.lean = saved

      assert.is_true(mentions(config.warnings(), 'preset "lean"'))
    end)

    it("names the project file for a value the project file supplied", function()
      local config = reload()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      vim.fn.writefile({ '{ "servers": ["lua_ls", 42] }' }, dir .. "/.nvim-lsp.json")
      local cwd = vim.fn.getcwd()
      vim.fn.chdir(dir)

      config.setup()
      vim.fn.chdir(cwd)
      vim.fn.delete(dir, "rf")

      assert.is_true(mentions(config.warnings(), ".nvim-lsp.json"))
    end)

    it("leaves a defaults-only warning unattributed", function()
      -- Nothing supplied the value, so there is no layer to name and no
      -- suffix to add.
      local config = reload()
      config.setup("not a table")
      assert.are.same({ "setup(): expected a table of options, ignoring" }, config.warnings())
    end)
  end)
end)
