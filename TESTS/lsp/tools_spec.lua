--- Covers the two `tools/` helpers that talk to more than one client at a
--- time, both of which used to treat "an answer" as "the answer".
---
--- Neither had a spec. They are the kind of code a suite skips because it
--- needs several clients behaving differently to say anything at all -- which
--- is exactly the condition under which both were wrong.

describe("lsp.tools.ts_type_lookup.cmds", function()
  local saved

  before_each(function()
    saved = {
      get_clients = vim.lsp.get_clients,
      cmd = vim.cmd,
    }
  end)

  after_each(function()
    vim.lsp.get_clients = saved.get_clients
    vim.cmd = saved.cmd
    package.loaded["lsp.tools.ts_type_lookup.cmds"] = nil
  end)

  --- A client answering `workspace/symbol` with `result`.
  ---@param id integer
  ---@param result table[]
  ---@return table
  local function client(id, result)
    return {
      id = id,
      name = "ls" .. id,
      supports_method = function()
        return true
      end,
      request = function(_self, _method, _params, handler)
        handler(nil, result)
        return true, id
      end,
    }
  end

  ---@return table[]
  local function one_symbol()
    return {
      {
        name = "Foo",
        location = {
          uri = "file:///x.ts",
          range = {
            start = { line = 0, character = 0 },
            ["end"] = { line = 0, character = 3 },
          },
        },
      },
    }
  end

  -- `lsp.buf_request` runs its handler once *per client*, and both callers
  -- here treat their callback as the single answer. On a TypeScript buffer
  -- that is the normal case rather than an edge one: `ts_ls` and `eslint` both
  -- attach. Measured with two clients where the first answered empty and the
  -- second had the symbol -- the callback fired twice, so the command ran its
  -- node_modules fallback *and* opened a split. The fallback is a blocking
  -- `rg` over the whole tree, so the spurious one is not free.
  it("answers once for two clients, and does not fall back when one of them found it", function()
    vim.lsp.get_clients = function()
      return { client(1, {}), client(2, one_symbol()) }
    end

    local splits = 0
    local real_cmd = saved.cmd
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.cmd = function(c)
      if type(c) == "string" and c:match("^vsplit") then
        splits = splits + 1
        return
      end
      return real_cmd(c)
    end

    local cmds = require("lsp.tools.ts_type_lookup.cmds")
    local fallbacks = 0
    cmds.find_in_node_modules = function()
      fallbacks = fallbacks + 1
    end

    cmds.go_to_type_definition_for("Foo")

    assert.are.equal(1, splits, "one jump, not one per answering client")
    assert.are.equal(0, fallbacks, "the node_modules grep ran although a client had the symbol")
  end)

  -- The other half `buf_request` got wrong: with no client supporting the
  -- method it never calls the handler at all, so `peek_type_definition_for`
  -- -- which has no client guard of its own -- simply did nothing. No preview,
  -- no message, no fallback.
  it("tells the caller when no attached client answers workspace/symbol", function()
    vim.lsp.get_clients = function()
      return {}
    end

    local cmds = require("lsp.tools.ts_type_lookup.cmds")
    local told = 0
    cmds.find_in_node_modules = function()
      told = told + 1
    end

    cmds.peek_type_definition_for("Foo")

    assert.are.equal(1, told, "the command returned in silence")
  end)
end)

describe("lsp.tools.lsp_signature.fallback_providers", function()
  ---@return table
  local function reload()
    package.loaded["lsp.tools.lsp_signature.fallback_providers"] = nil
    return require("lsp.tools.lsp_signature.fallback_providers")
  end

  ---@return integer
  local function live_timers()
    local n = 0
    vim.uv.walk(function(handle)
      if handle:get_type() == "timer" and not handle:is_closing() then
        n = n + 1
      end
    end)
    return n
  end

  ---@type table
  local PARAMS = {
    textDocument = { uri = "file:///x.lua" },
    position = { line = 0, character = 0 },
  }

  -- Each client gets an 800ms guard, and only the *answer* path closed it. A
  -- one-shot uv timer that has fired is still an open handle, so every client
  -- that timed out leaked its guard for the rest of the session -- and this
  -- runs off insert-mode cursor movement. Measured: three runs over three
  -- silent clients left nine timers behind.
  it("gives its timeout guard back when the guard is what fired", function()
    local fp = reload()

    ---@param id integer
    ---@return table
    local function mute(id)
      return {
        id = id,
        name = "mute" .. id,
        offset_encoding = "utf-16",
        server_capabilities = { definitionProvider = true, hoverProvider = true },
        supports_method = function()
          return true
        end,
        request = function()
          return true, id
        end, -- never calls back
        cancel_request = function()
          return true
        end,
      }
    end

    local before = live_timers()
    fp.try_providers({ mute(1), mute(2) }, PARAMS, {
      mode = "preview",
      callback = function() end,
    })
    -- Long enough for both guards to fire and the chain to run out.
    vim.wait(3000, function()
      return false
    end, 50)

    assert.are.equal(before, live_timers(), "a timed-out guard was left open")
  end)

  -- The guard moves on after 800ms, and the client it gave up on can still
  -- answer afterwards. That reached the caller a second time and put a second
  -- floating preview on top of the first.
  it("hands the caller one answer even when a client replies after its guard", function()
    local fp = reload()

    ---@type table[]
    local loc = {
      {
        uri = "file:///x.lua",
        range = {
          start = { line = 0, character = 0 },
          ["end"] = { line = 0, character = 1 },
        },
      },
    }

    local slow = {
      id = 1,
      name = "slow",
      offset_encoding = "utf-16",
      server_capabilities = { definitionProvider = true, hoverProvider = true },
      supports_method = function()
        return true
      end,
      request = function(_self, _method, _params, handler)
        vim.defer_fn(function()
          handler(nil, loc)
        end, 1200)
        return true, 1
      end,
      cancel_request = function()
        return true
      end,
    }
    local fast = {
      id = 2,
      name = "fast",
      offset_encoding = "utf-16",
      server_capabilities = { definitionProvider = true, hoverProvider = true },
      supports_method = function()
        return true
      end,
      request = function(_self, _method, _params, handler)
        handler(nil, loc)
        return true, 2
      end,
      cancel_request = function()
        return true
      end,
    }

    local calls = 0
    fp.try_providers({ slow, fast }, PARAMS, {
      mode = "preview",
      callback = function()
        calls = calls + 1
      end,
    })
    vim.wait(3000, function()
      return false
    end, 50)

    assert.are.equal(1, calls, "the late answer opened a second preview")
  end)
end)
