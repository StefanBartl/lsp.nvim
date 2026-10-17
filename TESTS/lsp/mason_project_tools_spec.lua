-- Test code: when something here comes back nil, this file must crash and
-- name it; nil guards would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
--- Covers `lsp.integrations.mason.ensure_install.project`: the table lsp.nvim
--- hands `lib.nvim.deps.project` so `:Lib deps project` lists the missing
--- Mason packages of the `ensure_install` lists, keyed by filetype.
---
--- `lib.nvim.deps.project` and `mason-registry` are replaced through
--- `package.loaded` / `package.preload` for every case: CI pins lib.nvim at
--- `ci-verified`, which may or may not carry `deps.project`, and Mason is not
--- installed in this harness. Both states are what the cases want to choose,
--- not inherit.

local MOD = "lsp.integrations.mason.ensure_install.project"
local ENSURE = "lsp.integrations.mason.ensure_install"
local LIB = "lib.nvim.deps.project"
local MASON = "mason-registry"

---@type table<string, any>
local saved_loaded = {}
---@type table<string, any>
local saved_preload = {}

local NAMES = { MOD, ENSURE, LIB, MASON, "lsp.health" }

--- A `lib.nvim.deps.project` stand-in that records `register_tools` calls.
---@return table stub
---@return { owner: string, tools: any }[] calls
local function lib_stub()
  local calls = {}
  local stub = {
    register_tools = function(owner, tools)
      calls[#calls + 1] = { owner = owner, tools = tools }
      return function() end
    end,
    registered = function()
      local out = {}
      for _, call in ipairs(calls) do
        out[#out + 1] = call.owner
      end
      return out
    end,
  }
  return stub, calls
end

--- Make `require(name)` fail the way an absent module does.
---@param name string
local function absent(name)
  package.loaded[name] = nil
  package.preload[name] = function()
    error(("module '%s' not found (spec stub)"):format(name), 0)
  end
end

---@param list { mason: string }[]|nil
---@return string[]
local function names(list)
  local out = {}
  for _, entry in ipairs(list or {}) do
    out[#out + 1] = entry.mason
  end
  return out
end

describe("lsp.integrations.mason.ensure_install.project", function()
  before_each(function()
    for _, name in ipairs(NAMES) do
      saved_loaded[name] = package.loaded[name]
      saved_preload[name] = package.preload[name]
      package.loaded[name] = nil
    end
    absent(MASON)
  end)

  after_each(function()
    for _, name in ipairs(NAMES) do
      package.loaded[name] = saved_loaded[name]
      package.preload[name] = saved_preload[name]
    end
  end)

  describe("FILETYPES", function()
    -- A package switched on without an entry is silently not registered; the
    -- default lists are the ones that must never fall through.
    it("covers every package of the four default lists", function()
      local project = require(MOD)
      local missing = {}
      for _, list in ipairs({ "lsp", "dap", "linter", "formatter" }) do
        local defaults = require(ENSURE .. ".defaults." .. list)
        for name in pairs(defaults) do
          local fts = project.FILETYPES[name]
          local listed = type(fts) == "table" and #fts > 0
          if not listed and not project.UNSCANNED[name] then
            missing[#missing + 1] = list .. ":" .. name
          end
        end
      end
      table.sort(missing)
      assert.are.same({}, missing)
    end)

    -- UNSCANNED is "left out on purpose": a name there must be a default
    -- package and must not also carry FILETYPES (it would then be reported).
    it("UNSCANNED names are default packages without a FILETYPES entry", function()
      local project = require(MOD)
      local defaults = {}
      for _, list in ipairs({ "lsp", "dap", "linter", "formatter" }) do
        for name in pairs(require(ENSURE .. ".defaults." .. list)) do
          defaults[name] = true
        end
      end
      local wrong = {}
      for name in pairs(project.UNSCANNED) do
        if not defaults[name] or project.FILETYPES[name] ~= nil then
          wrong[#wrong + 1] = name
        end
      end
      table.sort(wrong)
      assert.are.same({}, wrong)
      assert.is_not_nil(project.UNSCANNED["asmfmt"])
      assert.is_not_nil(project.UNSCANNED["jsonld-lsp"])
    end)

    -- lib.nvim's scan maps a file by its name alone
    -- (`vim.filetype.match({ filename = ... })`). A filetype no filename maps
    -- to is never reported, so every one used here needs a sample that this
    -- Neovim maps to it. Adding `asm` (`.asm`/`.s` need the buffer), `jsonld`
    -- (unknown) or `bash` (`.bash` gives `sh`) fails here.
    it("uses only filetypes a filename maps to", function()
      local SAMPLES = {
        astro = "a.astro",
        c = "a.c",
        cmake = "CMakeLists.txt",
        cpp = "a.cpp",
        cs = "a.cs",
        css = "a.css",
        go = "a.go",
        html = "a.html",
        java = "a.java",
        javascript = "a.js",
        javascriptreact = "a.jsx",
        json = "a.json",
        jsonc = "a.jsonc",
        less = "a.less",
        lua = "a.lua",
        markdown = "a.md",
        mysql = "a.mysql",
        nasm = "a.nasm",
        python = "a.py",
        query = "queries/lua/highlights.scm",
        rust = "a.rs",
        scss = "a.scss",
        sh = "a.sh",
        sql = "a.sql",
        svelte = "a.svelte",
        typescript = "a.ts",
        typescriptreact = "a.tsx",
        vim = "a.vim",
        vue = "a.vue",
        xml = "a.xml",
        yaml = "a.yaml",
        zig = "a.zig",
      }
      local dead = {}
      for name, fts in pairs(require(MOD).FILETYPES) do
        for _, ft in ipairs(fts) do
          local sample = SAMPLES[ft]
          if not sample or vim.filetype.match({ filename = sample }) ~= ft then
            dead[#dead + 1] = name .. ":" .. ft
          end
        end
      end
      table.sort(dead)
      assert.are.same({}, dead)
    end)
  end)

  describe("tools()", function()
    it("keys each package under the filetypes it serves, as { mason = name }", function()
      local tools = require(MOD).tools({ "lua-language-server", "luacheck", "marksman" })
      assert.are.same({ "lua-language-server", "luacheck" }, names(tools.lua))
      assert.are.same({ "marksman" }, names(tools.markdown))
      assert.are.same({ mason = "luacheck" }, tools.lua[2])
    end)

    it("leaves out a package it has no filetypes for", function()
      local tools = require(MOD).tools({ "no-such-package", "yamllint" })
      assert.are.same({ yaml = { { mason = "yamllint" } } }, tools)
    end)
  end)

  describe("ensure_install.wanted()", function()
    it("lists only what is switched on, overrides applied", function()
      local wanted = require(ENSURE).wanted({
        lsp = { ["lua-language-server"] = false },
        formatters = { ["luaformatter"] = true },
      })
      assert.is_false(vim.list_contains(wanted, "lua-language-server"))
      assert.is_true(vim.list_contains(wanted, "luacheck"))
      -- off by default in `defaults/lsp.lua`
      assert.is_false(vim.list_contains(wanted, "csharp-language-server"))
    end)

    it("drops what gate_by_system_deps refuses on this machine", function()
      local ensure = require(ENSURE)
      local orig = ensure.has_dotnet
      ensure.has_dotnet = function()
        return false
      end
      local without = ensure.wanted(nil)
      ensure.has_dotnet = function()
        return true
      end
      local with = ensure.wanted(nil)
      ensure.has_dotnet = orig
      assert.is_false(vim.list_contains(without, "omnisharp"))
      assert.is_true(vim.list_contains(with, "omnisharp"))
    end)

    -- Mason's luaformatter has no Windows build (`bin/lua-format.bat`
    -- missing): reported, it would be "missing" in every Lua root forever.
    it("drops luaformatter on Windows, for the report and the install path", function()
      local ensure = require(ENSURE)
      local orig = ensure.is_windows
      ensure.is_windows = function()
        return true
      end
      local on_windows = ensure.wanted(nil)
      local gate_windows = ensure.gate_by_system_deps("luaformatter")
      ensure.is_windows = function()
        return false
      end
      local elsewhere = ensure.wanted(nil)
      local gate_elsewhere = ensure.gate_by_system_deps("luaformatter")
      ensure.is_windows = orig
      assert.is_false(vim.list_contains(on_windows, "luaformatter"))
      assert.is_false(gate_windows)
      assert.is_true(vim.list_contains(elsewhere, "luaformatter"))
      assert.is_true(gate_elsewhere)
    end)

    -- Every report runs wanted(); on Windows a negative executable() walks
    -- PATH x PATHEXT. Asked once per PATH value, again when PATH changes.
    it("asks executable() once per binary and PATH value", function()
      local ensure = require(ENSURE)
      local orig_exec, orig_path = vim.fn.executable, vim.env.PATH
      local asked = {}
      vim.fn.executable = function(bin)
        asked[bin] = (asked[bin] or 0) + 1
        return 0
      end
      local ok, err = pcall(function()
        ensure.wanted(nil)
        ensure.wanted(nil)
        assert.are.equal(1, asked.dotnet)
        vim.env.PATH = (orig_path or "") .. (vim.fn.has("win32") == 1 and ";" or ":") .. "spec-dir"
        ensure.wanted(nil)
        assert.are.equal(2, asked.dotnet)
      end)
      vim.fn.executable = orig_exec
      vim.env.PATH = orig_path
      assert(ok, err)
    end)
  end)

  describe("register()", function()
    it("registers a report-time function under lsp.nvim", function()
      local stub, calls = lib_stub()
      package.loaded[LIB] = stub
      local ok, reason = require(MOD).register(nil)
      assert.is_true(ok)
      assert.is_nil(reason)
      assert.are.equal(1, #calls)
      assert.are.equal("lsp.nvim", calls[1].owner)
      assert.are.equal("function", type(calls[1].tools))
      assert.are.equal("registered", require(MOD).state())
    end)

    it("the function reports the wanted packages when Mason is loadable", function()
      local stub, calls = lib_stub()
      package.loaded[LIB] = stub
      package.preload[MASON] = nil
      package.loaded[MASON] = {}
      require(MOD).register({ linters = { luacheck = false } })
      local tools = calls[1].tools()
      assert.is_true(vim.list_contains(names(tools.lua), "lua-language-server"))
      assert.is_false(vim.list_contains(names(tools.lua), "luacheck"))
    end)

    -- Without Mason every entry would read "Mason not loadable" and fill the
    -- report's "Could not be checked" with noise.
    it("the function reports nothing when Mason is not loadable", function()
      local stub, calls = lib_stub()
      package.loaded[LIB] = stub
      require(MOD).register(nil)
      assert.are.same({}, calls[1].tools())
    end)

    it("is a quiet false when lib.nvim has no deps.project", function()
      absent(LIB)
      local ok, reason = require(MOD).register(nil)
      assert.is_false(ok)
      assert.is_truthy(reason:find("too old", 1, true))
      assert.are.equal("unavailable", require(MOD).state())
    end)

    it("is a quiet false when deps.project has no register_tools", function()
      package.loaded[LIB] = {
        registered = function()
          return {}
        end,
      }
      local ok = require(MOD).register(nil)
      assert.is_false(ok)
      assert.are.equal("unavailable", require(MOD).state())
    end)
  end)

  describe("setup()", function()
    -- One setup() per process (a second one is refused), so one case checks
    -- both: it registers with ensure_install off, and it hands
    -- `mason.overrides` on -- `register(nil)` would report luacheck again.
    it("registers with deps.project (ensure_install off), mason.overrides applied", function()
      local stub, calls = lib_stub()
      package.loaded[LIB] = stub
      package.preload[MASON] = nil
      package.loaded[MASON] = {}
      require("lsp").setup({ mason = { overrides = { linters = { luacheck = false } } } })
      local owners = {}
      for _, call in ipairs(calls) do
        owners[#owners + 1] = call.owner
      end
      assert.are.same({ "lsp.nvim" }, owners)
      local lua = names(calls[1].tools().lua)
      assert.is_true(vim.list_contains(lua, "lua-language-server"))
      assert.is_false(vim.list_contains(lua, "luacheck"))
    end)
  end)

  describe(":checkhealth lsp", function()
    ---@type { level: string, msg: string, advice: string[]|nil }[]
    local emitted
    local saved_health

    before_each(function()
      emitted = {}
      saved_health = vim.health
      local function rec(level)
        return function(msg, advice)
          local list = type(advice) == "string" and { advice } or advice
          emitted[#emitted + 1] = { level = level, msg = msg, advice = list }
        end
      end
      vim.health = {
        start = function() end,
        ok = rec("ok"),
        info = rec("info"),
        warn = rec("warn"),
        error = rec("error"),
      }
    end)

    after_each(function()
      vim.health = saved_health
    end)

    ---@param needle string
    ---@return { level: string, msg: string }|nil
    local function find(needle)
      for _, entry in ipairs(emitted) do
        if entry.msg:find(needle, 1, true) then
          return entry
        end
      end
      return nil
    end

    it("warns to update an old lib.nvim", function()
      absent(LIB)
      require("lsp.health").check()
      local entry = find("lib.nvim.deps.project (lib.nvim too old)")
      assert.is_not_nil(entry)
      assert.are.equal("warn", entry.level)
    end)

    it("says ok once lsp.nvim is registered and Mason loads", function()
      local stub = lib_stub()
      package.loaded[LIB] = stub
      package.preload[MASON] = nil
      package.loaded[MASON] = {}
      require(MOD).register(nil)
      require("lsp.health").check()
      local entry = find("Mason packages registered with lib.nvim.deps.project")
      assert.is_not_nil(entry)
      assert.are.equal("ok", entry.level)
    end)

    -- Registered, but the table is empty without Mason: "ok" would claim the
    -- report lists packages it cannot.
    it("says Mason is not loadable instead of ok when it is missing", function()
      package.loaded[LIB] = lib_stub()
      require(MOD).register(nil)
      require("lsp.health").check()
      assert.is_nil(find("Mason packages registered with lib.nvim.deps.project"))
      local entry = find("Mason is not loadable")
      assert.is_not_nil(entry)
      assert.are.equal("info", entry.level)
    end)

    it("says not registered before setup()", function()
      package.loaded[LIB] = lib_stub()
      require("lsp.health").check()
      local entry = find("not registered with lib.nvim.deps.project (setup() has not run)")
      assert.is_not_nil(entry)
      assert.are.equal("info", entry.level)
    end)

    -- `:Lazy reload lib.nvim` after setup(): lib.nvim's list is empty again,
    -- but setup() ran and a second one is refused -- a restart is the fix.
    it("says restart, not 'setup() has not run', when lib.nvim lost the registration", function()
      package.loaded[LIB] = lib_stub()
      require(MOD).register(nil)
      package.loaded[LIB] = lib_stub() -- the reloaded lib.nvim: nothing registered
      require("lsp.health").check()
      assert.is_nil(find("setup() has not run"))
      local entry = find("although setup() ran")
      assert.is_not_nil(entry)
      assert.are.equal("warn", entry.level)
      local advice = table.concat(entry.advice, "\n")
      assert.is_truthy(advice:find("reloaded", 1, true))
      assert.is_truthy(advice:find("Restart Neovim", 1, true))
    end)

    it("says restart when lib.nvim gained deps.project after setup()", function()
      absent(LIB)
      require(MOD).register(nil)
      package.preload[LIB] = nil
      package.loaded[LIB] = lib_stub()
      require("lsp.health").check()
      local entry = find("although setup() ran")
      assert.is_not_nil(entry)
      assert.is_truthy(table.concat(entry.advice, "\n"):find("updated since", 1, true))
    end)
  end)
end)
