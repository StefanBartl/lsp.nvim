--- Two things in `integrations/` that were fixed without changing behaviour a
--- user would notice, and were therefore the easiest to leave unpinned.
---
--- Both are about a boundary rather than a result: which namespace the plugin
--- is allowed to take behaviour from, and whether a report says the same thing
--- twice running.

describe("lsp.integrations.mason.ensure_install", function()
  local saved

  before_each(function()
    saved = {
      gate = package.loaded["config.mason.ensure_install"],
      registry = package.loaded["mason-registry"],
      mod = package.loaded["lsp.integrations.mason.ensure_install"],
    }
  end)

  after_each(function()
    package.loaded["config.mason.ensure_install"] = saved.gate
    package.loaded["mason-registry"] = saved.registry
    package.loaded["lsp.integrations.mason.ensure_install"] = saved.mod
  end)

  -- The dependency gate used to try `require("config.mason.ensure_install")`
  -- first and fall through when it did not resolve. `config.*` is the *user's*
  -- module namespace, not this plugin's: anyone who happened to create a module
  -- by that name would have silently taken over which packages get installed.
  --
  -- Pinned as a boundary rather than as a result. Nothing about the installed
  -- set changes here; what must stay true is that a module sitting in the
  -- user's namespace is never consulted.
  it("never takes its dependency gate from the user's module namespace", function()
    local consulted = false
    package.loaded["config.mason.ensure_install"] = {
      gate_by_system_deps = function()
        consulted = true
        return false, "hijacked"
      end,
    }

    local asked = {}
    package.loaded["mason-registry"] = {
      refresh = function(cb)
        if cb then
          cb()
        end
      end,
      get_package = function(name)
        asked[#asked + 1] = name
        return {
          is_installed = function()
            return true
          end,
        }
      end,
    }

    package.loaded["lsp.integrations.mason.ensure_install"] = nil
    local ensure = require("lsp.integrations.mason.ensure_install")
    ensure.enable_lsp({ ["spec-package"] = true })

    assert.is_false(consulted, "the gate was taken from `config.*`, the user's namespace")
    -- And the package still got through the plugin's own gate, so the
    -- assertion above is not passing because nothing ran.
    assert.is_true(
      vim.tbl_contains(asked, "spec-package"),
      "nothing was resolved at all, so the check above proves nothing"
    )
  end)
end)

describe("lsp.integrations", function()
  -- The load-failure warnings reach `:checkhealth lsp` and `:Lsp status`. They
  -- were built from `pairs(_failed)`, so two runs of an unchanged session
  -- printed the same warnings in a different order -- which makes two reports
  -- of the same broken state impossible to diff.
  it("reports load failures in the order the adapters are declared", function()
    local saved = {}
    for _, name in ipairs({ "trouble", "blink", "cmp", "lazydev", "menu", "nvchad" }) do
      local key = "lsp.integrations." .. name
      saved[key] = package.loaded[key]
      -- A module that raises on require is recorded as a load failure.
      package.loaded[key] = nil
      package.preload[key] = function()
        error("spec: refusing to load " .. name)
      end
    end

    --- The adapter names in the order their load failures were reported.
    ---
    --- Names, not whole messages: Lua remembers a failed `require` and answers
    --- the second one with "previous error loading module" instead of the
    --- original text, so comparing the strings would fail over something this
    --- case is not about.
    ---@return string[]
    local function failure_order()
      package.loaded["lsp.integrations"] = nil
      local integrations = require("lsp.integrations")

      ---@type string[]
      local names = {}
      for _, warning in ipairs(integrations.setup(require("lsp.config").get())) do
        local name = warning:match("^integration (%S+) failed to load:")
        if name then
          names[#names + 1] = name
        end
      end
      return names
    end

    local first = failure_order()
    local second = failure_order()

    for key, value in pairs(saved) do
      package.preload[key] = nil
      package.loaded[key] = value
    end
    package.loaded["lsp.integrations"] = nil

    assert.is_true(#first > 1, "the case needs more than one failure to say anything")
    assert.are.same(first, second, "two runs of the same state printed a different order")

    -- The load-bearing assertion, and the reason the one above is not enough:
    -- `pairs` is stable for the same table contents *within* one process, so
    -- running it twice here could never have caught the defect -- the order
    -- only drifts between sessions. What does catch it is the order itself.
    -- These are `ADAPTERS` order, which is the order the plugin declares its
    -- adapters in and the order the report has to follow.
    assert.are.same({ "nvchad", "cmp", "blink", "lazydev", "trouble" }, first)
  end)
end)
