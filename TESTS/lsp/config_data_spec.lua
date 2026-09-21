--- Covers the configuration layer's *data* files -- `DEFAULTS`, `PRESETS`,
--- `KEYMAPS`, the project-file reader and the pack reader -- as opposed to
--- `config/init.lua`'s merge, which `config_spec.lua` owns.
---
--- Data files fail differently from code. Nothing throws: a preset sets a key
--- the merge drops, an allowlist grows a hole, a comment describes a table that
--- has since moved on. None of that shows up at runtime, which is why each case
--- below asserts against the table or the file itself rather than against
--- behaviour downstream of it.
---
--- Three of these are doc-drift cases: they read the module's own source and
--- check that a claim made in prose still matches the data next to it. That is
--- the same contract `scripts/gen_bindings.lua --check` enforces for
--- docs/BINDINGS.md, applied to the comments the tables carry.

local DEFAULTS = require("lsp.config.DEFAULTS")
local PRESETS = require("lsp.config.PRESETS")
local KEYMAPS = require("lsp.config.KEYMAPS")
local project = require("lsp.config.project")

--- Neovim's own mappings, captured before anything in this file binds a key,
--- so "is this an lhs Neovim already owns" stays answerable afterwards.
---@type table<string, table<string, string>>
local NATIVE = {}
for _, mode in ipairs({ "n", "i", "x", "o" }) do
  NATIVE[mode] = {}
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    NATIVE[mode][m.lhs] = m.desc or m.rhs or "<fn>"
  end
end

---@param relative string # Path under the plugin root, e.g. "lua/lsp/config/project.lua".
---@return string
local function source_of(relative)
  local path = vim.api.nvim_get_runtime_file(relative, false)[1]
  assert(path, relative .. " not found on the runtimepath")
  local fh = assert(io.open(path, "r"))
  local text = fh:read("*a")
  fh:close()
  return text
end

--- A throwaway directory holding one `.nvim-lsp.json`.
---@param content string|nil
---@return string dir
local function project_dir(content)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  if content ~= nil then
    local fh = assert(io.open(dir .. "/.nvim-lsp.json", "w"))
    fh:write(content)
    fh:close()
  end
  return dir
end

describe("lsp.config.DEFAULTS", function()
  it("names a server for every entry that actually resolves to a module", function()
    -- "Each name resolves to `lsp.servers.<name>`, with `lsp.servers.webdev.
    -- <name>` tried as a fallback for dotless names" -- the resolution
    -- `core/registry.lua` performs. A default that does not resolve costs a
    -- warning on every single startup.
    for _, name in ipairs(DEFAULTS.servers) do
      local paths = { "lsp.servers." .. name }
      if not name:match("%.") then
        paths[#paths + 1] = "lsp.servers.webdev." .. name
      end
      local resolved = false
      for _, path in ipairs(paths) do
        local ok, srv = pcall(require, path)
        if ok and type(srv) == "table" and type(srv.setup) == "function" then
          resolved = true
          break
        end
      end
      assert.is_true(resolved, ("servers[%q] resolves to no module"):format(name))
    end
  end)
end)

describe("lsp.config.PRESETS", function()
  --- Every dotted path a table sets, leaves and branches alike.
  ---@param t table
  ---@param prefix string
  ---@param acc table<string, any>
  ---@return table<string, any>
  local function paths(t, prefix, acc)
    for key, value in pairs(t) do
      local path = prefix == "" and tostring(key) or (prefix .. "." .. tostring(key))
      acc[path] = value
      if type(value) == "table" and not vim.islist(value) then
        paths(value, path, acc)
      end
    end
    return acc
  end

  it("sets nothing outside DEFAULTS but the two keys vim.diagnostic takes", function()
    -- `cfg.diagnostics` is handed to `vim.diagnostic.config()` verbatim, so a
    -- preset may name a key DEFAULTS does not carry -- but only there. Anywhere
    -- else a path DEFAULTS has never heard of is a preset setting something no
    -- consumer reads.
    local known = paths(DEFAULTS, "", {})
    ---@type string[]
    local extra = {}
    for name, preset in pairs(PRESETS) do
      for path in pairs(paths(preset, "", {})) do
        if known[path] == nil then
          extra[#extra + 1] = ("%s: %s"):format(name, path)
        end
      end
    end
    table.sort(extra)
    assert.are.same(
      { "full: diagnostics.update_in_insert", "lean: diagnostics.virtual_text" },
      extra
    )
  end)

  it("those two survive the merge and reach vim.diagnostic.config()", function()
    -- The other half of the case above: a key outside DEFAULTS is only
    -- acceptable if it still arrives. `tbl_deep_extend` drops nothing here, and
    -- `core.diagnostics` strips only `ui`/`debounce_ms`.
    package.loaded["lsp.config"] = nil
    local diagnostics = require("lsp.core.diagnostics")

    local lean = require("lsp.config").setup({ preset = "lean" })
    assert.are.equal(false, diagnostics.apply(lean.diagnostics).virtual_text)

    package.loaded["lsp.config"] = nil
    local full = require("lsp.config").setup({ preset = "full" })
    assert.are.equal(true, diagnostics.apply(full.diagnostics).update_in_insert)

    package.loaded["lsp.config"] = nil
  end)

  it("no preset touches mason.ensure_install or formatter.on_save", function()
    -- The module's headline promise, and the reason `full` is safe to pick
    -- without reading it: a profile is a performance dial, not consent to
    -- download packages or to start rewriting buffers on save.
    for name, preset in pairs(PRESETS) do
      assert.is_nil(preset.mason, name .. " sets mason")
      assert.is_nil(
        preset.formatter and preset.formatter.on_save,
        name .. " sets formatter.on_save"
      )
    end
  end)

  it("names a keymap preset the catalogue actually has", function()
    for name, preset in pairs(PRESETS) do
      local chosen = preset.keymaps and preset.keymaps.preset
      if chosen ~= nil then
        assert.is_table(KEYMAPS.presets[chosen], ("%s -> keymaps.preset %q"):format(name, chosen))
      end
    end
  end)
end)

describe("lsp.config.KEYMAPS", function()
  it("minimal's own comment names every native-equivalent key it keeps", function()
    -- Doc drift, and the kind that misleads: the comment above `presets` used
    -- to say `minimal` drops "everything Neovim 0.11 already provides" plus the
    -- prefixless `ls*` family. Measured against `nvim_get_keymap` it keeps four
    -- of the first (`]q`/`[q`/`]l`/`[l`) and two of the second (`lsc`/`lsC`),
    -- so a reader picking the preset to be rid of either got neither.
    local src = source_of("lua/lsp/config/KEYMAPS.lua")
    local block = src:match("(%-%-%-[^\n]*Which entries each preset binds.-)\nlocal presets")
    assert.is_string(block, "the comment above `presets` moved")

    ---@type string[]
    local unmentioned = {}
    for _, name in ipairs(KEYMAPS.presets.minimal) do
      local spec = KEYMAPS.entries[name]
      local modes = type(spec.mode) == "table" and spec.mode or { spec.mode }
      ---@cast modes string[]
      local native = false
      for _, mode in ipairs(modes) do
        native = native or (NATIVE[mode] ~= nil and NATIVE[mode][spec.lhs] ~= nil)
      end
      local prefixless_ls = spec.lhs:sub(1, 2) == "ls"
      if (native or prefixless_ls) and not block:find("`" .. spec.lhs .. "`", 1, true) then
        unmentioned[#unmentioned + 1] = ("%s (%s)"):format(name, spec.lhs)
      end
    end
    table.sort(unmentioned)
    assert.are.same({}, unmentioned)
  end)

  it("keeps exactly two of the prefixless ls* family under minimal", function()
    -- Pins the trade the comment now states: `minimal` does not buy back the
    -- 'timeoutlen' wait on Normal-mode `l`, because one live `ls*` map is
    -- enough to impose it.
    ---@type string[]
    local kept = {}
    for _, name in ipairs(KEYMAPS.presets.minimal) do
      local lhs = KEYMAPS.entries[name].lhs
      if lhs:sub(1, 2) == "ls" then
        kept[#kept + 1] = lhs
      end
    end
    table.sort(kept)
    assert.are.same({ "lsC", "lsc" }, kept)

    ---@type string[]
    local all = {}
    for _, spec in pairs(KEYMAPS.entries) do
      if spec.lhs:sub(1, 2) == "ls" then
        all[#all + 1] = spec.lhs
      end
    end
    -- Nine when this was written; five more arrived with the lspsaga
    -- replacement (`lsp`, `lsT` peek, `lsf` finder, `lsh`/`lsH` hierarchy) --
    -- none of them in `minimal`, which is what the assertion above pins.
    assert.are.equal(14, #all)
  end)

  it("Neovim's own gr* maps are global, so the catalogue replaces them", function()
    -- The premise this file's navigation comment rested on until now was that
    -- Neovim sets `gr*` buffer-locally on LspAttach. It does not:
    -- `$VIMRUNTIME/lua/vim/_core/defaults.lua` maps them unconditionally at
    -- startup. Asserted here because the difference decides whether the
    -- catalogue's `grn` runs at all -- a global mapping loses to a
    -- buffer-local one and wins against another global.
    for _, lhs in ipairs({ "grn", "grt", "grr", "gri", "gO" }) do
      local map = vim.fn.maparg(lhs, "n", false, true)
      assert.are.equal(lhs, map.lhs, lhs .. " is not mapped by Neovim in this version")
      assert.are.equal(0, map.buffer, lhs .. " is buffer-local, not global")
    end

    package.loaded["lsp.config"] = nil
    local cfg = require("lsp.config").setup({ keymaps = { enable = true, preset = "default" } })
    require("lsp.bindings.keymaps").setup(cfg)
    assert.are.equal("LSP: Rename symbol", vim.fn.maparg("grn", "n", false, true).desc)
    package.loaded["lsp.config"] = nil
  end)
end)

describe("lsp.config.project", function()
  it("names every option it refuses", function()
    -- "The omissions are the point, so they are named rather than left
    -- implicit." `auto_restart` was refused and named nowhere, which left the
    -- single option about relaunching processes as the one a reader had to
    -- infer. Nine allowed plus sixteen named omissions is all twenty-five
    -- top-level keys, and this case is what keeps it that way when the next one
    -- lands.
    local src = source_of("lua/lsp/config/project.lua")
    local header = src:match("^(.-)\nM%.ALLOWED")
    assert.is_string(header, "the ALLOWED block moved")

    ---@type string[]
    local unnamed = {}
    for key in pairs(DEFAULTS) do
      if not project.ALLOWED[key] and not header:find("`" .. key .. "`", 1, true) then
        unnamed[#unnamed + 1] = key
      end
    end
    table.sort(unnamed)
    assert.are.same({}, unnamed)
  end)

  it("allows nothing that is not an option", function()
    for key in pairs(project.ALLOWED) do
      assert.is_not_nil(
        DEFAULTS[key],
        ("ALLOWED names %q, which DEFAULTS does not have"):format(key)
      )
    end
  end)

  it("refuses a missing or malformed `file` instead of raising", function()
    -- `LspNvim.ProjectOpts.file` is optional, so this call is type-legal.
    -- Before the guard it died inside `vim.fs.find` with "names: expected
    -- string|table|function, got nil" and took the caller with it.
    local dir = project_dir('{"servers":["lua_ls"]}')

    for _, opts in ipairs({
      { enable = true },
      { enable = true, file = "" },
      { enable = true, file = 42 },
      { enable = true, file = false },
    }) do
      local ok, layer, warnings = pcall(project.read, opts, dir)
      assert.is_true(ok, ("read(%s) raised: %s"):format(vim.inspect(opts), tostring(layer)))
      assert.is_nil(layer)
      assert.are.equal(1, #warnings, "a refused option must still say so")
      assert.is_truthy(warnings[1]:find("project.file", 1, true))
    end

    vim.fn.delete(dir, "rf")
  end)

  it("degrades on every shape of broken file, and never raises", function()
    -- The security boundary's failure mode matters as much as its allowlist: a
    -- repository you cloned writes this file, so a parse error must cost the
    -- layer and nothing else.
    local cases = {
      ['{"servers":["lua_ls"'] = "truncated",
      ["not json at all"] = "prose",
      ['["servers"]'] = "a JSON array",
      ["42"] = "a bare number",
      ['"hello"'] = "a bare string",
      ["null"] = "JSON null",
      ["{}"] = "an empty object",
      [""] = "an empty file",
      ['{"servers":' .. string.rep("[", 400) .. string.rep("]", 400) .. "}"] = "400-deep nesting",
      ['{"servers":' .. string.rep("[", 2000) .. string.rep("]", 2000) .. "}"] = "2000-deep nesting",
    }

    for content, label in pairs(cases) do
      local dir = project_dir(content)
      local ok, layer = pcall(project.read, { enable = true, file = ".nvim-lsp.json" }, dir)
      assert.is_true(ok, label .. " raised: " .. tostring(layer))
      vim.fn.delete(dir, "rf")
    end
  end)

  it("lets no refused key through, whatever else the file contains", function()
    local dir = project_dir([[
      {
        "servers": ["lua_ls"],
        "mason": { "ensure_install": true },
        "keymaps": { "preset": "none" },
        "auto_restart": { "max_attempts": 9999 },
        "project": { "file": "../elsewhere.json" }
      }
    ]])

    local layer, warnings = project.read({ enable = true, file = ".nvim-lsp.json" }, dir)
    assert.is_table(layer)
    assert.are.same({ "lua_ls" }, layer.data.servers)
    for _, refused in ipairs({ "mason", "keymaps", "auto_restart", "project" }) do
      assert.is_nil(layer.data[refused], refused .. " came through the allowlist")
    end
    -- One line for all four: a file that sets four refused keys has one
    -- mistaken idea about the feature, not four separate problems.
    assert.are.equal(1, #warnings)
    for _, refused in ipairs({ "mason", "keymaps", "auto_restart", "project" }) do
      assert.is_truthy(warnings[1]:find(refused, 1, true), refused .. " unnamed in the warning")
    end

    vim.fn.delete(dir, "rf")
  end)

  it("a repository cannot steer `servers` at a module of its own", function()
    -- `servers` is allowlisted and each name is concatenated into a
    -- `require("lsp.servers." .. name)`. Neovim's loader turns every `.` into a
    -- `/`, which destroys the `..` a traversal needs -- asserted rather than
    -- reasoned, because this is the one allowlisted key that reaches `require`.
    local registry = require("lsp.core.registry")
    _G.__lsp_nvim_traversal_canary = nil

    for _, name in ipairs({ "../evil", "../../evil", "..\\..\\evil", "./../evil", "lsp.evil" }) do
      local ok, enabled = pcall(registry.setup_all, {}, { name })
      assert.is_true(ok, name .. " raised")
      assert.are.same({}, enabled, name .. " resolved to something")
    end

    assert.is_nil(_G.__lsp_nvim_traversal_canary)
  end)
end)

describe("lsp.config.pack", function()
  local saved = vim.g.lsp_nvim

  after_each(function()
    vim.g.lsp_nvim = saved
    package.loaded["lsp.config.pack"] = nil
  end)

  it("answers every reader for every malformed vim.g.lsp_nvim", function()
    -- This one is read while lazy.nvim is still collecting specs, before any
    -- of this plugin's normalization exists. There is no layer below it to
    -- degrade to, so each reader has to carry its own fallback.
    local shapes = {
      "nonsense",
      7,
      { other = 1 },
      { pack = "core" },
      { pack = true },
      { pack = {} },
      { pack = { core = 0 } },
      { pack = { completion = "blnik" } },
      { pack = { completion = true } },
      { pack = { completion_accept = "CTRL_Y" } },
      { pack = { disable = "lensline.nvim" } },
      { pack = { disable = { ["lensline.nvim"] = true } } },
    }

    for _, shape in ipairs(shapes) do
      vim.g.lsp_nvim = shape
      package.loaded["lsp.config.pack"] = nil
      local pack = require("lsp.config.pack")
      local label = vim.inspect(shape, { newline = " ", indent = "" })

      assert.is_table(pack.opts(), label)
      assert.is_boolean(pack.group("core"), label)
      assert.is_boolean(pack.group("ui"), label)
      assert.is_boolean(pack.enabled("lensline.nvim", "ui"), label)
      local choice = pack.completion()
      assert.is_true(choice == "cmp" or choice == "blink" or choice == false, label)
      local accept = pack.completion_accept()
      assert.is_true(accept == "cr" or accept == "ctrl_y", label)
    end
  end)
end)
