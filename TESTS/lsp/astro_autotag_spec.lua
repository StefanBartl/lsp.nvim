--- Covers the one promise `lsp.servers.webdev.astro.autotag` makes: it reports
--- whether nvim-ts-autotag can do the work, and it never configures it.
---
--- The "never configures it" half is the whole point. nvim-ts-autotag has a
--- single global `setup()`, so a call from here decides `enable_close`,
--- `enable_rename` and `enable_close_on_slash` for every filetype in the
--- editor. It used to make that call; under lazy.nvim it was a no-op behind
--- upstream's `did_setup()` guard, and under a host that installs the plugin
--- without configuring it, it silently became the global configuration. Both
--- outcomes were accidents of load order, which is exactly what a test is for.

describe("lsp.servers.webdev.astro.autotag", function()
  ---@return table
  local function autotag()
    package.loaded["lsp.servers.webdev.astro.autotag"] = nil
    return require("lsp.servers.webdev.astro.autotag")
  end

  --- Install stand-ins for the plugin and its internal config module.
  ---@param plugin table|nil # nil = not installed
  ---@param did_setup boolean|nil # nil = internal module absent
  ---@return fun(): nil restore
  local function stub(plugin, did_setup)
    local keys = { "nvim-ts-autotag", "nvim-ts-autotag.config.plugin" }
    local saved = { package.loaded[keys[1]], package.loaded[keys[2]] }
    package.loaded[keys[1]] = plugin
    package.loaded[keys[2]] = did_setup ~= nil
        and {
          did_setup = function()
            return did_setup
          end,
        }
      or nil
    return function()
      package.loaded[keys[1]] = saved[1]
      package.loaded[keys[2]] = saved[2]
    end
  end

  it("says no when nvim-ts-autotag is not installed", function()
    local restore = stub(nil, nil)
    assert.is_false(autotag().available())
    restore()
  end)

  it("says yes when the plugin is installed and the host set it up", function()
    local restore = stub({ setup = function() end }, true)
    assert.is_true(autotag().available())
    restore()
  end)

  it("says no when the plugin is installed but nobody set it up", function()
    -- Not pedantry: without setup() the plugin registers no autocommands and
    -- attaches to no buffer, so "installed" would be a false yes and the
    -- caller would skip the fallback for nothing.
    local restore = stub({ setup = function() end }, false)
    assert.is_false(autotag().available())
    restore()
  end)

  it("assumes yes when the internal config module is not where it was", function()
    -- A renamed upstream internal is not evidence that the plugin is
    -- unconfigured, and dropping to the hand-rolled fallback on a guess is the
    -- worse failure.
    local restore = stub({ setup = function() end }, nil)
    assert.is_true(autotag().available())
    restore()
  end)

  it("never calls the plugin's global setup()", function()
    local calls = 0
    local restore = stub({
      setup = function()
        calls = calls + 1
      end,
    }, true)

    autotag().available()
    assert.are.equal(0, calls, "astro must not configure a plugin it does not own")

    restore()
  end)

  it("still offers the hand-rolled fallback", function()
    assert.are.equal("function", type(autotag().setup_manual_autoclose))
  end)

  it("no longer exposes the old setup() name", function()
    assert.is_nil(autotag().setup)
  end)
end)
