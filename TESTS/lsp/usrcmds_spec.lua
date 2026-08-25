--- Covers the `:Lsp` verb: that the route tree is what the design says, that
--- every closed argument set completes, and that server names complete from
--- live state rather than a list frozen at setup.
---
--- The completion assertions are the point. A route whose enum silently stops
--- matching still runs -- it just stops being discoverable, which is the kind
--- of regression nobody notices until they need the command they forgot.

local usrcmds = require("lsp.bindings.usrcmds")

---@param prefix string
---@return string[]
local function complete(prefix)
  return vim.fn.getcompletion(prefix, "cmdline")
end

---@param list string[]
---@param value string
---@return boolean
local function has(list, value)
  return vim.tbl_contains(list, value)
end

-- Registered once, at load time: plenary's busted has no `setup()` block, and
-- the verb has to exist before any completion assertion below runs.
local registered = usrcmds.setup()

describe("lsp.bindings.usrcmds", function()
  it("registers the verb", function()
    assert.is_true(registered, "the composer accepted the route spec")
    assert.are.equal(2, vim.fn.exists(":Lsp"))
  end)

  describe("route tree", function()
    it("has every subcommand roadmap section 8.2 designs", function()
      local subs = complete("Lsp ")
      for _, route in ipairs({
        "status",
        "servers",
        "info",
        "health",
        "doctor",
        "start",
        "stop",
        "restart",
        "force-restart",
        "recover",
        "format",
        "diag",
        "workspace",
        "root",
        "log",
      }) do
        assert.is_true(has(subs, route), ":Lsp " .. route .. " exists")
      end
    end)

    it("completes the nested log routes", function()
      local subs = complete("Lsp log ")
      assert.is_true(has(subs, "open"))
      assert.is_true(has(subs, "level"))
    end)
  end)

  describe("argument completion", function()
    ---@param prefix string
    ---@param expected string[]
    local function completes(prefix, expected)
      local got = complete(prefix)
      for _, value in ipairs(expected) do
        assert.is_true(has(got, value), prefix .. " completes " .. value)
      end
    end

    it("format", function()
      completes("Lsp format ", { "once", "on", "off", "toggle", "status", "which" })
    end)

    it("workspace", function()
      completes("Lsp workspace ", { "on", "off", "toggle", "status", "now" })
    end)

    it("diag", function()
      completes("Lsp diag ", { "qf", "loc", "next", "prev" })
    end)

    it("root", function()
      completes("Lsp root ", { "pick", "show" })
    end)

    it("doctor", function()
      completes("Lsp doctor ", { "health", "debug", "quick", "deep", "all" })
    end)

    it("log level", function()
      completes("Lsp log level ", { "trace", "debug", "info", "warn", "error", "off" })
    end)
  end)

  describe("server-name completion", function()
    it("offers the configured servers", function()
      package.loaded["lsp.config"] = nil
      require("lsp.config").setup({ servers = { "lua_ls", "gopls" } })

      local got = complete("Lsp restart ")
      assert.is_true(has(got, "lua_ls"))
      assert.is_true(has(got, "gopls"))
    end)

    it("is computed live, not frozen at setup", function()
      -- The whole reason for a custom argument type: an enum captured when the
      -- verb was registered would still be offering the old list here.
      package.loaded["lsp.config"] = nil
      require("lsp.config").setup({ servers = { "zls" } })

      local got = complete("Lsp restart ")
      assert.is_true(has(got, "zls"), "the new list is offered")
      assert.is_false(has(got, "gopls"), "the previous list is gone")
    end)

    it("filters by what has been typed", function()
      package.loaded["lsp.config"] = nil
      require("lsp.config").setup({ servers = { "lua_ls", "gopls" } })

      local got = complete("Lsp restart lu")
      assert.is_true(has(got, "lua_ls"))
      assert.is_false(has(got, "gopls"))
    end)
  end)
end)

describe("usrcmds.legacy_aliases", function()
  ---@return table
  local function reload()
    package.loaded["lsp.config"] = nil
    return require("lsp.config")
  end

  it("defaults to on", function()
    assert.is_true(reload().setup().usrcmds.legacy_aliases)
  end)

  it("can be switched off", function()
    assert.is_false(reload().setup({ usrcmds = { legacy_aliases = false } }).usrcmds.legacy_aliases)
  end)

  it("falls back to the default on a non-boolean", function()
    assert.is_true(reload().setup({ usrcmds = { legacy_aliases = "yes" } }).usrcmds.legacy_aliases)
  end)

  it("survives usrcmds being replaced by a non-table", function()
    local cfg = reload().setup({ usrcmds = false })
    assert.is_true(cfg.usrcmds.enable)
    assert.is_true(cfg.usrcmds.legacy_aliases)
  end)
end)
