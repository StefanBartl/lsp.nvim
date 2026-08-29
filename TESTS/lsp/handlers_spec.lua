--- Covers `lsp.core.handlers`: the throttle around
--- `textDocument/publishDiagnostics`, and the dedup it sits on top of.
---
--- Both halves have the same failure mode, and it is the expensive one: a
--- diagnostic that never reaches the screen. A dedup that compares the wrong
--- fields drops a real entry; a throttle that coalesces the wrong way drops a
--- whole push. Neither raises, neither logs, and both look exactly like "the
--- server did not send it".
---
--- Neovim's own handler is replaced by a recorder here rather than stubbed
--- away, so what these cases assert is the payload that would have been
--- rendered -- not that some function was called.

describe("lsp.core.handlers", function()
  local KEY = "textDocument/publishDiagnostics"

  ---@type table[]
  local received = {}

  --- Client ids the throttle should consider alive. The trailing flush checks
  --- that the client still exists before handing its payload on -- otherwise a
  --- push arriving after a server exits would re-render diagnostics Neovim has
  --- already cleared, and they would never go away. There is no real client in
  --- this harness, so the lookup is stubbed and `alive` is what these cases
  --- steer.
  ---@type table<integer, boolean>
  local alive = {}

  ---@type function|nil
  local real_get_client_by_id = nil

  --- Fresh module state per case: `installed` and the open windows are
  --- file-locals, so one case's wrapper and timers would serve the next.
  ---@return table
  local function reload()
    local prev = package.loaded["lsp.core.handlers"]
    if prev ~= nil and type(prev.flush) == "function" then
      prev.flush()
    end
    package.loaded["lsp.core.handlers"] = nil
    return require("lsp.core.handlers")
  end

  --- Install a recorder as the handler being wrapped, then wrap it.
  ---@param debounce_ms integer
  ---@return function publish # Calls the wrapper the way a server would.
  local function install(debounce_ms)
    received = {}
    ---@diagnostic disable-next-line: assign-type-mismatch
    vim.lsp.handlers[KEY] = function(_, result, _, _)
      received[#received + 1] = result
    end
    reload().setup({ debounce_ms = debounce_ms })

    local wrapper = vim.lsp.handlers[KEY]
    return function(uri, diagnostics, client_id)
      wrapper(nil, { uri = uri, diagnostics = diagnostics }, { client_id = client_id or 1 }, nil)
    end
  end

  --- One LSP-shaped diagnostic.
  ---@param line integer
  ---@param message string
  ---@return table
  local function diag(line, message)
    return {
      range = { start = { line = line, character = 0 }, ["end"] = { line = line, character = 4 } },
      severity = 2,
      source = "test_ls",
      message = message,
    }
  end

  --- Wait for the throttle window to elapse and its scheduled flush to run.
  ---@param ms integer
  ---@return nil
  local function wait(ms)
    vim.wait(ms, function()
      return false
    end)
    vim.wait(50, function()
      return false
    end)
  end

  before_each(function()
    alive = setmetatable({}, {
      __index = function()
        return true
      end,
    })
    real_get_client_by_id = vim.lsp.get_client_by_id
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.get_client_by_id = function(id)
      return alive[id] and { id = id, name = "test_ls" } or nil
    end
  end)

  after_each(function()
    local mod = package.loaded["lsp.core.handlers"]
    if mod ~= nil and type(mod.flush) == "function" then
      mod.flush()
    end
    if real_get_client_by_id ~= nil then
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.lsp.get_client_by_id = real_get_client_by_id
    end
  end)

  describe("dedup", function()
    it("collapses an entry the server sent twice", function()
      local publish = install(0)
      publish("file:///a.lua", { diag(3, "unused"), diag(3, "unused") })

      assert.are.equal(1, #received)
      assert.are.equal(1, #received[1].diagnostics)
    end)

    -- The bug this pins down: the raw LSP payload has `range`, not `lnum`, so
    -- a dedup reading only `lnum` compared every entry at position (0,0) and
    -- threw away the second of two real diagnostics with the same text.
    it("keeps the same message at two different lines", function()
      local publish = install(0)
      publish("file:///a.lua", { diag(3, "unused"), diag(42, "unused") })

      assert.are.equal(1, #received)
      assert.are.equal(2, #received[1].diagnostics)
    end)

    it("does not mutate the payload the server sent", function()
      local publish = install(0)
      local sent = { diag(3, "unused"), diag(3, "unused") }
      publish("file:///a.lua", sent)

      assert.are.equal(2, #sent)
    end)
  end)

  describe("throttle", function()
    it("passes everything through when the window is 0", function()
      local publish = install(0)
      for i = 1, 4 do
        publish("file:///a.lua", { diag(i, "e" .. i) })
      end

      assert.are.equal(4, #received)
    end)

    -- Leading edge: the push a user is waiting for must not be the one that
    -- gets delayed.
    it("renders the first push of a burst immediately", function()
      local publish = install(80)
      publish("file:///a.lua", { diag(1, "first") })

      assert.are.equal(1, #received)
      assert.are.equal("first", received[1].diagnostics[1].message)
    end)

    it("coalesces a burst down to the newest payload", function()
      local publish = install(80)
      publish("file:///a.lua", { diag(1, "first") })
      publish("file:///a.lua", { diag(2, "second") })
      publish("file:///a.lua", { diag(3, "third") })
      assert.are.equal(1, #received) -- only the leading edge so far

      wait(80)
      assert.are.equal(2, #received)
      -- The newest wins, not a merge: a diagnostics list replaces a file's
      -- diagnostics wholesale, so merging would resurrect cleared entries.
      assert.are.equal(1, #received[2].diagnostics)
      assert.are.equal("third", received[2].diagnostics[1].message)
    end)

    it("does not emit a trailing push when nothing followed the first", function()
      local publish = install(80)
      publish("file:///a.lua", { diag(1, "only") })

      wait(80)
      assert.are.equal(1, #received)
    end)

    it("delivers a burst that clears diagnostics, not just one that adds", function()
      local publish = install(80)
      publish("file:///a.lua", { diag(1, "error") })
      publish("file:///a.lua", {})

      wait(80)
      assert.are.equal(2, #received)
      assert.are.equal(0, #received[2].diagnostics)
    end)

    -- Per (client, file). A shared window would let a noisy buffer throttle a
    -- quiet one, which is the opposite of what the throttle is for.
    it("gives each file its own window", function()
      local publish = install(80)
      publish("file:///a.lua", { diag(1, "a") })
      publish("file:///b.lua", { diag(1, "b") })

      assert.are.equal(2, #received)
    end)

    it("gives each client its own window on the same file", function()
      local publish = install(80)
      publish("file:///a.lua", { diag(1, "from 1") }, 1)
      publish("file:///a.lua", { diag(1, "from 2") }, 2)

      assert.are.equal(2, #received)
    end)

    -- Without this the throttle would resurrect a dead server's diagnostics:
    -- Neovim clears them on exit, and a push arriving after that clear puts
    -- them back with nothing left to remove them.
    it("drops the trailing push of a client that has gone away", function()
      local publish = install(80)
      publish("file:///a.lua", { diag(1, "first") })
      publish("file:///a.lua", { diag(2, "second") })

      alive[1] = false
      wait(80)
      assert.are.equal(1, #received)
    end)

    it("opens a fresh window once the previous one has elapsed", function()
      local publish = install(80)
      publish("file:///a.lua", { diag(1, "burst one") })
      wait(80)

      publish("file:///a.lua", { diag(2, "burst two") })
      assert.are.equal(2, #received)
      assert.are.equal("burst two", received[2].diagnostics[1].message)
    end)
  end)

  describe("setup", function()
    it("refuses to wrap the handler twice", function()
      local publish = install(0)
      -- A second setup() on the already-wrapped handler would wrap the
      -- wrapper, and every push would be recorded twice.
      require("lsp.core.handlers").setup({ debounce_ms = 0 })

      publish("file:///a.lua", { diag(1, "once") })
      assert.are.equal(1, #received)
    end)

    it("falls back to the default window on a nonsense value", function()
      received = {}
      ---@diagnostic disable-next-line: assign-type-mismatch
      vim.lsp.handlers[KEY] = function(_, result, _, _)
        received[#received + 1] = result
      end
      local handlers = reload()
      ---@diagnostic disable-next-line: assign-type-mismatch
      handlers.setup({ debounce_ms = "soon" })

      local wrapper = vim.lsp.handlers[KEY]
      wrapper(
        nil,
        { uri = "file:///a.lua", diagnostics = { diag(1, "x") } },
        { client_id = 1 },
        nil
      )
      wrapper(
        nil,
        { uri = "file:///a.lua", diagnostics = { diag(2, "y") } },
        { client_id = 1 },
        nil
      )

      -- Throttling at all is the assertion: a string must not become 0.
      assert.are.equal(1, #received)
    end)
  end)

  describe("config", function()
    ---@return table
    local function reload_config()
      package.loaded["lsp.config"] = nil
      return require("lsp.config")
    end

    it("defaults to the documented window", function()
      local DEFAULTS = require("lsp.config.DEFAULTS")
      local cfg = reload_config().setup()

      assert.are.equal(DEFAULTS.diagnostics.debounce_ms, cfg.diagnostics.debounce_ms)
    end)

    it("accepts 0 as 'no throttling' rather than treating it as unset", function()
      local cfg = reload_config().setup({ diagnostics = { debounce_ms = 0 } })

      assert.are.equal(0, cfg.diagnostics.debounce_ms)
    end)

    -- A negative or non-numeric window would reach uv.timer:start() and raise
    -- there, inside a handler, on every push.
    it("warns and falls back on a negative window", function()
      local config = reload_config()
      local cfg = config.setup({ diagnostics = { debounce_ms = -1 } })

      assert.are.equal(
        require("lsp.config.DEFAULTS").diagnostics.debounce_ms,
        cfg.diagnostics.debounce_ms
      )
      local warned = false
      for _, w in ipairs(config.warnings()) do
        if w:find("debounce_ms", 1, true) then
          warned = true
        end
      end
      assert.is_true(warned)
    end)

    it("warns and falls back on a non-number", function()
      local config = reload_config()
      ---@diagnostic disable-next-line: assign-type-mismatch
      local cfg = config.setup({ diagnostics = { debounce_ms = "150ms" } })

      assert.are.equal(
        require("lsp.config.DEFAULTS").diagnostics.debounce_ms,
        cfg.diagnostics.debounce_ms
      )
    end)
  end)
end)
