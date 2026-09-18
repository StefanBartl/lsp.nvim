--- Covers the nvim-cmp half of `lsp.completion.register`, which `completion_spec.lua`
--- leaves alone -- it exercises the blink adapter, and blink resolves its
--- providers lazily so there is nothing to register and nothing to stack.
---
--- The cmp path is where the state lives: cmp has no way to remove an event
--- listener, so anything hooked onto its bus is permanent for the session.

describe("lsp.completion.register (nvim-cmp)", function()
  local saved

  local saved_specs_table

  before_each(function()
    saved = {
      cmp = package.loaded["cmp"],
      pack = package.loaded["lsp.config.pack"],
      usage = package.loaded["lsp.completion.usage"],
      register = package.loaded["lsp.completion.register"],
    }
    -- The specs registry now lives on `_G` (see `register.lua`), on purpose --
    -- that survival is what the reload cases below exist to exercise. Which
    -- means it also survives *between test cases* unless something resets it,
    -- and every case here registers under names other tests reuse.
    saved_specs_table = rawget(_G, "__lsp_nvim_completion_specs")
    rawset(_G, "__lsp_nvim_completion_specs", nil)
  end)

  after_each(function()
    package.loaded["cmp"] = saved.cmp
    package.loaded["lsp.config.pack"] = saved.pack
    package.loaded["lsp.completion.usage"] = saved.usage
    package.loaded["lsp.completion.register"] = saved.register
    rawset(_G, "__lsp_nvim_completion_specs", saved_specs_table)
  end)

  --- A cmp stand-in that records what is hooked onto its event bus, plus the
  --- surrounding modules the registrar reaches for.
  ---
  --- `register_source` records every call rather than the most recent one,
  --- because real cmp keys its registry by a fresh id per call
  --- (`hrsh7th/nvim-cmp`'s `core.lua`: `self.sources[s.id] = s`) -- so calling
  --- it twice for one name does not replace the first Source object, it adds
  --- a second one alongside it. A stub that only remembers the last call would
  --- make it impossible to tell "replaced" from "never called again" apart,
  --- which is exactly the distinction the staleness case below turns on.
  ---@return table env
  local function stub_engine()
    local env = { listeners = {}, bumps = 0, sources = {} }

    package.loaded["cmp"] = {
      register_source = function(name, source_obj)
        env.sources[#env.sources + 1] = { name = name, obj = source_obj }
      end,
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

  -- A second, independent defect the same reload can trigger, found while
  -- re-checking the fix above: cmp's `Source:complete` closes over the
  -- `specs` table by reference, once, when it is first registered. A fresh
  -- `local specs = {}` per module load means that after a reload, cmp's
  -- *already-registered* Source object -- which nothing ever replaces, since
  -- the guard above now correctly stops a second `cmp.register_source` call
  -- for the same name -- keeps reading the *first* load's table forever. The
  -- second load's own `register.spec(name)` reports the fresh data
  -- correctly; nothing cmp will ever ask is listening to it.
  --
  -- blink has the same shape for its own reason: it resolves a provider's
  -- `module` and calls `.new()` on it exactly once per session
  -- (`Saghen/blink.cmp`'s `provider/init.lua`), and caches the result
  -- forever, so its Source object is exactly as pinned to whichever
  -- register.lua load was current when it was first created.
  it("keeps the already-registered source pointed at fresh data after a reload", function()
    local env = stub_engine()
    package.loaded["lsp.completion.register"] = nil
    require("lsp.completion.register").source({
      name = "spec_source",
      namespace = "spec_source",
      items = function()
        return { { label = "first_load" } }
      end,
    })

    assert.are.equal(1, #env.sources, "the source was not registered once")
    local live_source = env.sources[1].obj

    for key in pairs(package.loaded) do
      if type(key) == "string" and key:match("^lsp%.") then
        package.loaded[key] = nil
      end
    end
    package.loaded["lsp.config.pack"] = {
      completion = function()
        return "cmp"
      end,
    }
    package.loaded["lsp.completion.usage"] = { bump = function() end }
    require("lsp.completion.register").source({
      name = "spec_source",
      namespace = "spec_source",
      items = function()
        return { { label = "second_load_after_reload" } }
      end,
    })

    assert.are.equal(
      1,
      #env.sources,
      "a second reload re-registered a Source cmp will now show two of"
    )

    local response
    live_source:complete(nil, function(r)
      response = r
    end)
    assert.are.equal(
      "second_load_after_reload",
      response.items[1] and response.items[1].label,
      "the live source is still reading the pre-reload data"
    )
  end)
end)
