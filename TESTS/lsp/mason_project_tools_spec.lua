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
          if type(project.FILETYPES[name]) ~= "table" or #project.FILETYPES[name] == 0 then
            missing[#missing + 1] = list .. ":" .. name
          end
        end
      end
      table.sort(missing)
      assert.are.same({}, missing)
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
    it("registers with deps.project, also with ensure_install off", function()
      local stub, calls = lib_stub()
      package.loaded[LIB] = stub
      require("lsp").setup({})
      local owners = {}
      for _, call in ipairs(calls) do
        owners[#owners + 1] = call.owner
      end
      assert.are.same({ "lsp.nvim" }, owners)
    end)
  end)

  describe(":checkhealth lsp", function()
    ---@type { level: string, msg: string }[]
    local emitted
    local saved_health

    before_each(function()
      emitted = {}
      saved_health = vim.health
      local function rec(level)
        return function(msg)
          emitted[#emitted + 1] = { level = level, msg = msg }
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

    it("says ok once lsp.nvim is registered", function()
      local stub = lib_stub()
      package.loaded[LIB] = stub
      require(MOD).register(nil)
      require("lsp.health").check()
      local entry = find("registered with lib.nvim.deps.project")
      assert.is_not_nil(entry)
      assert.are.equal("ok", entry.level)
    end)

    it("says not registered before setup()", function()
      package.loaded[LIB] = lib_stub()
      require("lsp.health").check()
      local entry = find("not registered with lib.nvim.deps.project")
      assert.is_not_nil(entry)
      assert.are.equal("info", entry.level)
    end)
  end)
end)
