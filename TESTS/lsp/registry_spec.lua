--- Covers `lsp.core.registry`: turning configured server names into set-up
--- servers, and what it does with the ones that do not work out.
---
--- Every case runs against stub server modules rather than the real ones. A
--- real `lsp.servers.*` module calls `vim.lsp.config()` and would leave the
--- test process with servers registered; more importantly, the behaviour worth
--- pinning down here is the resolution and the failure handling, not what any
--- particular server config contains.

local registry = require("lsp.core.registry")

--- Register a fake server module for the duration of a case.
---@param name string # Module name under `lsp.servers.`.
---@param module table
---@return fun(): nil restore
local function stub_server(name, module)
  local key = "lsp.servers." .. name
  local original = package.loaded[key]
  package.loaded[key] = module
  return function()
    package.loaded[key] = original
  end
end

--- The shared table `setup_all` hands to each server module.
---@return table
local function shared()
  return {
    capabilities = {},
    on_attach = function() end,
    on_init = function()
      return true
    end,
    formatter = {},
  }
end

describe("lsp.core.registry", function()
  describe("arguments", function()
    it("returns nothing without a shared table", function()
      ---@diagnostic disable-next-line: param-type-mismatch
      assert.are.same({}, registry.setup_all(nil, { "lua_ls" }))
    end)

    it("returns nothing without a server list", function()
      ---@diagnostic disable-next-line: param-type-mismatch
      assert.are.same({}, registry.setup_all(shared(), nil))
    end)

    it("returns nothing for an empty server list", function()
      assert.are.same({}, registry.setup_all(shared(), {}))
    end)
  end)

  describe("resolution", function()
    it("sets up a server whose module resolves", function()
      local got
      local restore = stub_server("faketest", {
        setup = function(s)
          got = s
        end,
      })

      local enabled = registry.setup_all(shared(), { "faketest" })
      restore()

      assert.are.same({ "faketest" }, enabled)
      assert.is_not_nil(got, "the module received the shared table")
      assert.are.equal("function", type(got.on_attach))
    end)

    it("falls back to the webdev.* path for a dotless name", function()
      local restore = stub_server("webdev.faketest", {
        setup = function() end,
      })

      local enabled = registry.setup_all(shared(), { "faketest" })
      restore()

      assert.are.same({ "faketest" }, enabled)
    end)

    it("does not try the webdev fallback for a dotted name", function()
      local restore = stub_server("webdev.mobiledev.faketest", {
        setup = function() end,
      })

      local enabled = registry.setup_all(shared(), { "mobiledev.faketest" })
      restore()

      assert.are.same({}, enabled)
    end)

    it("skips a name with no module at all", function()
      assert.are.same({}, registry.setup_all(shared(), { "definitely_not_a_server" }))
    end)

    it("skips a module without a setup function", function()
      local restore = stub_server("faketest", { not_setup = true })
      local enabled = registry.setup_all(shared(), { "faketest" })
      restore()
      assert.are.same({}, enabled)
    end)
  end)

  describe("failure handling", function()
    it("a throwing server does not abort the others", function()
      local reached = false
      local restore_bad = stub_server("fakebad", {
        setup = function()
          error("server config exploded")
        end,
      })
      local restore_good = stub_server("fakegood", {
        setup = function()
          reached = true
        end,
      })

      local enabled = registry.setup_all(shared(), { "fakebad", "fakegood" })
      restore_good()
      restore_bad()

      assert.is_true(reached, "the server after the failing one was still set up")
      assert.are.same({ "fakegood" }, enabled)
    end)

    it("returns only the servers that actually set up", function()
      local restore_ok = stub_server("fakeok", { setup = function() end })
      local enabled = registry.setup_all(shared(), { "fakeok", "definitely_not_a_server" })
      restore_ok()
      assert.are.same({ "fakeok" }, enabled)
    end)
  end)

  describe("order", function()
    it("preserves the configured order", function()
      local restore_a = stub_server("fakea", { setup = function() end })
      local restore_b = stub_server("fakeb", { setup = function() end })

      local enabled = registry.setup_all(shared(), { "fakeb", "fakea" })
      restore_b()
      restore_a()

      assert.are.same({ "fakeb", "fakea" }, enabled)
    end)
  end)
end)
