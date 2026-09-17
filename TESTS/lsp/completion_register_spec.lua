--- Covers the nvim-cmp half of `lsp.completion.register`, which `completion_spec.lua`
--- leaves alone -- it exercises the blink adapter, and blink resolves its
--- providers lazily so there is nothing to register and nothing to stack.
---
--- The cmp path is where the state lives: cmp has no way to remove an event
--- listener, so anything hooked onto its bus is permanent for the session.

describe("lsp.completion.register (nvim-cmp)", function()
  local saved

  before_each(function()
    saved = {
      cmp = package.loaded["cmp"],
      pack = package.loaded["lsp.config.pack"],
      usage = package.loaded["lsp.completion.usage"],
      register = package.loaded["lsp.completion.register"],
    }
  end)

  after_each(function()
    package.loaded["cmp"] = saved.cmp
    package.loaded["lsp.config.pack"] = saved.pack
    package.loaded["lsp.completion.usage"] = saved.usage
    package.loaded["lsp.completion.register"] = saved.register
  end)

  --- A cmp stand-in that records what is hooked onto its event bus, plus the
  --- surrounding modules the registrar reaches for.
  ---@return table env
  local function stub_engine()
    local env = { listeners = {}, bumps = 0 }

    package.loaded["cmp"] = {
      register_source = function() end,
      event = {
        on = function(_self, _name, fn)
          env.listeners[#env.listeners + 1] = fn
        end,
      },
    }
    package.loaded["lsp.config.pack"] = {
      completion = function()
        return "cmp"
      end,
    }
    package.loaded["lsp.completion.usage"] = {
      bump = function()
        env.bumps = env.bumps + 1
      end,
    }

    return env
  end

  ---@return table
  local function spec()
    return {
      name = "spec_source",
      namespace = "spec_source",
      items = function()
        return {}
      end,
    }
  end

  ---@param env table
  ---@return nil
  local function accept_one(env)
    local event = {
      entry = {
        source = { name = "spec_source" },
        completion_item = { label = "alpha" },
      },
    }
    for _, fn in ipairs(env.listeners) do
      fn(event)
    end
  end

  -- cmp has no per-source confirm hook, so the registrar puts one global
  -- listener on the bus per source and filters by name -- and cmp offers no way
  -- to take one off again. Registering the same source twice therefore stacked
  -- them, and one accepted word was counted once per registration.
  --
  -- Not a transient miscount: the counts live in `lsp_completion_usage.json`,
  -- they only ever go up, and `usage.lua` calls them the user's history
  -- "accumulated over months". Every reload skewed the ranking permanently.
  it("hooks cmp's confirm bus once, however often a source registers", function()
    local env = stub_engine()
    package.loaded["lsp.completion.register"] = nil
    local register = require("lsp.completion.register")

    register.source(spec())
    register.source(spec())
    register.source(spec())

    assert.are.equal(1, #env.listeners, "a listener was added per registration")

    accept_one(env)
    assert.are.equal(1, env.bumps, "one accepted word was counted more than once")
  end)

  -- The guard has to live on `cmp` rather than in a local, because the reload
  -- it must survive is the one that clears this module. `:Lazy reload lsp.nvim`
  -- drops every `lsp.*` module while cmp -- and the listeners already on its
  -- bus -- stay exactly where they were.
  it("still hooks once after every lsp.* module has been reloaded", function()
    local env = stub_engine()
    package.loaded["lsp.completion.register"] = nil
    require("lsp.completion.register").source(spec())

    for key in pairs(package.loaded) do
      if type(key) == "string" and key:match("^lsp%.") then
        package.loaded[key] = nil
      end
    end
    -- What a real session still has after such a reload: its own modules back.
    package.loaded["lsp.config.pack"] = {
      completion = function()
        return "cmp"
      end,
    }
    package.loaded["lsp.completion.usage"] = {
      bump = function()
        env.bumps = env.bumps + 1
      end,
    }
    require("lsp.completion.register").source(spec())

    assert.are.equal(1, #env.listeners, "the reload stacked a second listener")

    accept_one(env)
    assert.are.equal(1, env.bumps)
  end)
end)
