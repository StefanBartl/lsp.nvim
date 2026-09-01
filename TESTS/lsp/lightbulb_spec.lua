--- Covers `lsp.core.lightbulb`: the kind allowlist that the whole feature
--- rests on, the per-filetype resolution it shares with `lsp.core.inlay_hints`,
--- and the config normalization that feeds both.
---
--- The allowlist is the part worth pinning down. An unfiltered code-action
--- indicator is lit permanently under the servers this plugin configures --
--- `ts_ls` offers "Move to a new file" nearly everywhere -- so "does
--- `refactor.move` count" is not a detail, it is the difference between an
--- indicator and a decoration. Every case below fixes one answer.
---
--- The request path is not exercised: there is no language server in the
--- harness, so `refresh()` finds no client with `codeActionProvider` and
--- returns before it asks anything. That is the point -- what decides whether
--- a response lights the bulb has to be correct without a server, because it
--- is what the server's answer is then measured against.

describe("lsp.core.lightbulb", function()
  --- Fresh module state per case: the toggle and the allowlist are
  --- file-locals, so a previous `setup()` would leak into the next assertion.
  ---@return table
  local function reload()
    local mod = package.loaded["lsp.core.lightbulb"]
    if mod then
      pcall(mod.detach)
    end
    package.loaded["lsp.core.lightbulb"] = nil
    return require("lsp.core.lightbulb")
  end

  after_each(function()
    local mod = package.loaded["lsp.core.lightbulb"]
    if mod then
      pcall(mod.detach)
    end
  end)

  describe("the kind allowlist", function()
    it("counts the kinds it was given and drops the rest", function()
      local lb = reload()
      lb.setup({ enable = true, kinds = { "quickfix", "source" } })

      assert.are.equal(
        2,
        lb._countable({
          { title = "Fix spelling", kind = "quickfix" },
          { title = "Organize imports", kind = "source.organizeImports" },
          { title = "Move to a new file", kind = "refactor.move" },
          { title = "Extract function", kind = "refactor.extract" },
        })
      )
    end)

    -- The prefix rule from |lsp-code-action-kind|: a kind matches exactly or
    -- as a dotted child. Plain string prefixing would let `quickfixed` in.
    it("matches a dotted child but not a longer word", function()
      local lb = reload()
      lb.setup({ enable = true, kinds = { "quickfix" } })

      assert.are.equal(1, lb._countable({ { kind = "quickfix.import" } }))
      assert.are.equal(0, lb._countable({ { kind = "quickfixed" } }))
    end)

    -- `kind` is optional in the protocol and a plain `Command` never carries
    -- one. Dropping those would hide every action from a server that does not
    -- classify -- an empty bulb that looks like a working one.
    it("counts an action that carries no kind at all", function()
      local lb = reload()
      lb.setup({ enable = true, kinds = { "quickfix" } })

      assert.are.equal(1, lb._countable({ { title = "Run me", command = "do.it" } }))
      assert.are.equal(1, lb._countable({ { title = "Empty kind", kind = "" } }))
    end)

    it("counts everything when the allowlist is empty", function()
      local lb = reload()
      lb.setup({ enable = true, kinds = {} })

      assert.are.equal(
        2,
        lb._countable({ { kind = "refactor.move" }, { kind = "refactor.extract" } })
      )
    end)

    -- A disabled action comes back with a reason string precisely so the
    -- client does not offer it. Counting it would light the bulb for something
    -- `lsa` then refuses to run.
    it("skips a disabled action", function()
      local lb = reload()
      lb.setup({ enable = true, kinds = {} })

      assert.are.equal(
        1,
        lb._countable({
          { kind = "quickfix", disabled = { reason = "not applicable here" } },
          { kind = "quickfix" },
        })
      )
    end)

    it("survives an empty or absent result", function()
      local lb = reload()
      lb.setup({ enable = true })

      assert.are.equal(0, lb._countable({}))
      assert.are.equal(0, lb._countable(nil))
    end)

    it("keeps the default allowlist when setup names none", function()
      local lb = reload()
      lb.setup({ enable = true })

      assert.are.equal(1, lb._countable({ { kind = "quickfix" } }))
      assert.are.equal(0, lb._countable({ { kind = "refactor.move" } }))
    end)

    it("ignores non-string entries in the allowlist", function()
      local lb = reload()
      ---@diagnostic disable-next-line: assign-type-mismatch
      lb.setup({ enable = true, kinds = { "quickfix", 7, "", false } })

      assert.are.equal(1, lb._countable({ { kind = "quickfix" } }))
      assert.are.equal(0, lb._countable({ { kind = "refactor" } }))
    end)
  end)

  describe("resolution", function()
    it("falls back to the global default for a filetype with no override", function()
      local lb = reload()
      lb.setup({ enable = true })

      assert.is_true(lb.enabled(nil))
      assert.is_true(lb.enabled("lua"))
      assert.is_true(lb.enabled("anything-at-all"))
    end)

    it("lets an override say 'off here' against a global on", function()
      local lb = reload()
      lb.setup({ enable = true, filetypes = { typescript = false } })

      assert.is_true(lb.enabled(nil))
      assert.is_false(lb.enabled("typescript"))
      assert.is_true(lb.enabled("lua"))
    end)

    it("distinguishes an explicit false from an absent key", function()
      local lb = reload()
      lb.setup({ enable = true, filetypes = { typescript = false } })

      assert.is_false(lb.enabled("typescript"))
      assert.is_true(lb.enabled("markdown"))
      assert.are.same({ "typescript" }, lb.overridden())
    end)

    it("drops override entries that are not filetype -> boolean", function()
      local lb = reload()
      ---@diagnostic disable-next-line: assign-type-mismatch
      lb.setup({ enable = false, filetypes = { lua = "yes", [1] = true, go = true } })

      assert.are.same({ "go" }, lb.overridden())
    end)

    it("replaces the previous state rather than merging into it", function()
      local lb = reload()
      lb.setup({ enable = true, filetypes = { lua = false } })
      lb.setup({ enable = false })

      assert.are.same({}, lb.overridden())
      assert.is_false(lb.enabled("lua"))
    end)
  end)

  describe("toggle", function()
    it("flips the global default", function()
      local lb = reload()
      lb.setup({ enable = false })

      lb.toggle(nil)
      assert.is_true(lb.enabled(nil))
      lb.toggle(nil)
      assert.is_false(lb.enabled(nil))
    end)

    -- Without the explicit write, a later global change would silently undo
    -- the filetype toggle the user just made.
    it("writes an override even when it equals the global", function()
      local lb = reload()
      lb.setup({ enable = true, filetypes = { lua = false } })

      lb.toggle("lua")
      assert.is_true(lb.enabled("lua"))
      assert.are.same({ "lua" }, lb.overridden())
    end)

    it("clear() drops an override back to the global default", function()
      local lb = reload()
      lb.setup({ enable = false, filetypes = { lua = true } })

      assert.is_true(lb.enabled("lua"))
      lb.clear("lua")
      assert.is_false(lb.enabled("lua"))
      assert.are.same({}, lb.overridden())
    end)
  end)

  describe("status", function()
    it("reports the resolved state without a server attached", function()
      local lb = reload()
      lb.setup({ enable = true, kinds = { "quickfix" }, render = "virtual_text" })

      local text = table.concat(lb.status(), "\n")
      assert.is_truthy(text:find("global:%s+on"))
      assert.is_truthy(text:find("virtual_text", 1, true))
      assert.is_truthy(text:find("quickfix", 1, true))
      assert.is_truthy(text:find("no client advertising codeActionProvider", 1, true))
    end)

    it("says so when the allowlist is empty rather than printing nothing", function()
      local lb = reload()
      lb.setup({ enable = true, kinds = {} })

      assert.is_truthy(table.concat(lb.status(), "\n"):find("(unfiltered)", 1, true))
    end)
  end)

  -- The half the allowlist cases cannot reach: a response arriving and turning
  -- into an extmark, or deliberately not turning into one. Driven through a
  -- stubbed client rather than a real server, because what is under test is
  -- this module's reaction to an answer, not the answer.
  describe("drawing", function()
    ---@return table[]
    local function marks()
      local ns = vim.api.nvim_get_namespaces()["lsp_nvim_lightbulb"]
      if ns == nil then
        return {}
      end
      return vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
    end

    --- Run `fn` with one stub client attached that answers every
    --- `textDocument/codeAction` with `result`.
    ---@param result table[]
    ---@param fn fun()
    ---@return nil
    local function with_client(result, fn)
      local real_clients = vim.lsp.get_clients
      local real_range = vim.lsp.util.make_range_params

      local client = {
        id = 1,
        name = "stub",
        offset_encoding = "utf-16",
        server_capabilities = { codeActionProvider = true },
        request = function(_, _, _, handler)
          handler(nil, result)
          return true, 1
        end,
        cancel_request = function()
          return true
        end,
      }

      vim.lsp.get_clients = function()
        return { client }
      end
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.lsp.util.make_range_params = function()
        return {
          textDocument = { uri = "file:///stub.lua" },
          range = {
            start = { line = 0, character = 0 },
            ["end"] = { line = 0, character = 0 },
          },
        }
      end

      local ok, err = pcall(fn)

      vim.lsp.get_clients = real_clients
      vim.lsp.util.make_range_params = real_range
      assert(ok, err)
    end

    --- Fire the trigger the module listens on and let the (zero-length)
    --- debounce window elapse.
    ---@return nil
    local function tick()
      vim.api.nvim_exec_autocmds("CursorMoved", {})
      vim.wait(500, function()
        return false
      end, 20)
    end

    before_each(function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local x = 1" })
      vim.bo.filetype = "lua"
    end)

    it("places a sign when an allowed action comes back", function()
      local lb = reload()
      lb.setup({ enable = true, kinds = { "quickfix" }, debounce_ms = 0 })

      with_client({ { title = "Fix it", kind = "quickfix" } }, tick)

      local found = marks()
      assert.are.equal(1, #found)
      assert.are.equal("󰌵 ", found[1][4].sign_text)
    end)

    it("places nothing when only filtered-out kinds come back", function()
      local lb = reload()
      lb.setup({ enable = true, kinds = { "quickfix" }, debounce_ms = 0 })

      with_client({ { title = "Move to a new file", kind = "refactor.move" } }, tick)

      assert.are.equal(0, #marks())
    end)

    it("places nothing while the filetype override says off", function()
      local lb = reload()
      lb.setup({ enable = true, filetypes = { lua = false }, kinds = {}, debounce_ms = 0 })

      with_client({ { title = "Fix it", kind = "quickfix" } }, tick)

      assert.are.equal(0, #marks())
    end)

    -- The alternative render mode exists because the sign column and the
    -- end-of-line virtual text are both already occupied; if it silently fell
    -- back to a sign it would collide with exactly what it was chosen to avoid.
    it("uses virtual text at the window edge when asked to", function()
      local lb = reload()
      lb.setup({ enable = true, render = "virtual_text", kinds = {}, debounce_ms = 0 })

      with_client({ { title = "Fix it", kind = "quickfix" } }, tick)

      local found = marks()
      assert.are.equal(1, #found)
      assert.is_nil(found[1][4].sign_text)
      assert.are.equal("right_align", found[1][4].virt_text_pos)
    end)

    it("takes the indicator away once the actions are gone", function()
      local lb = reload()
      lb.setup({ enable = true, kinds = {}, debounce_ms = 0 })

      with_client({ { title = "Fix it", kind = "quickfix" } }, tick)
      assert.are.equal(1, #marks())

      with_client({}, tick)
      assert.are.equal(0, #marks())
    end)
  end)

  describe("config normalization", function()
    ---@return table
    local function resolve(opts)
      local config = package.loaded["lsp.config"]
      package.loaded["lsp.config"] = nil
      local fresh = require("lsp.config")
      fresh.setup(vim.tbl_deep_extend("force", { project = { enable = false } }, opts or {}))
      local cfg = fresh.get()
      package.loaded["lsp.config"] = config
      return cfg
    end

    it("defaults to on with the narrow allowlist", function()
      local cfg = resolve({})

      assert.is_true(cfg.lightbulb.enable)
      assert.are.same({ "quickfix", "source" }, cfg.lightbulb.kinds)
      assert.are.equal("sign", cfg.lightbulb.render)
    end)

    -- A list here would leave `kinds` iterating nothing, which the module
    -- reads as "unfiltered" -- the exact opposite of what someone writing an
    -- allowlist means.
    it("restores the default allowlist when kinds is not a list", function()
      local cfg = resolve({ lightbulb = { kinds = { quickfix = true } } })

      assert.are.same({ "quickfix", "source" }, cfg.lightbulb.kinds)
    end)

    it("falls back to sign rendering for an unknown render mode", function()
      local cfg = resolve({ lightbulb = { render = "hologram" } })

      assert.are.equal("sign", cfg.lightbulb.render)
    end)

    it("pulls a negative debounce back to the default", function()
      local cfg = resolve({ lightbulb = { debounce_ms = -5 } })

      assert.are.equal(150, cfg.lightbulb.debounce_ms)
    end)

    it("drops a filetype map that is a list", function()
      local cfg = resolve({ lightbulb = { filetypes = { "lua" } } })

      assert.are.same({}, cfg.lightbulb.filetypes)
    end)

    it("keeps normalizing inlay_hints.filetypes through the shared helper", function()
      local cfg = resolve({ inlay_hints = { filetypes = { lua = true, [1] = "go" } } })

      assert.are.same({ lua = true }, cfg.inlay_hints.filetypes)
    end)
  end)
end)
