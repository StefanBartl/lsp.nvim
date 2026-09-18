--- Covers `lsp.core.attach`: the `on_init`/`on_attach` pair every server is
--- built with, and specifically the guards around it -- a client that is not
--- a table, a buffer that is not really attachable, a server that has not
--- announced capabilities yet -- plus the fan-out to the adapter hooks
--- `lsp.integrations` hands in and the workspace-diagnostics wiring that used
--- to live inline here.
---
--- `lsp.core.workspace_diagnostics` is stubbed rather than loaded: it defers
--- through `vim.defer_fn` and walks the filesystem, neither of which this
--- file is about. What is under test is which of its functions `attach.lua`
--- calls, with what arguments, and whether it reads `enabled()` fresh on
--- every attach as the module header promises.

describe("lsp.core.attach", function()
  ---@type table
  local wd

  --- A fresh stub of `lsp.core.workspace_diagnostics`, installed before
  --- `attach.lua` is required so the module binds to it at load time.
  ---@return table attach
  local function reload()
    wd = {
      seeded_with = nil,
      schedule_calls = {},
      enabled_value = false,
    }
    function wd.seed(default)
      wd.seeded_with = default
    end
    function wd.enabled()
      return wd.enabled_value
    end
    function wd.schedule_populate(client, bufnr)
      wd.schedule_calls[#wd.schedule_calls + 1] = { client = client, bufnr = bufnr }
    end

    package.loaded["lsp.core.workspace_diagnostics"] = wd
    package.loaded["lsp.core.attach"] = nil
    return require("lsp.core.attach")
  end

  after_each(function()
    package.loaded["lsp.core.attach"] = nil
    package.loaded["lsp.core.workspace_diagnostics"] = nil
  end)

  --- A real, listed, loaded buffer with the given buftype (default: normal
  --- file buffer, `""`), deleted after `fn` runs.
  ---@param buftype string|nil
  ---@param fn fun(bufnr: integer): nil
  ---@return nil
  local function with_buf(buftype, fn)
    local bufnr = vim.api.nvim_create_buf(true, false)
    if buftype and buftype ~= "" then
      vim.bo[bufnr].buftype = buftype
    end
    local ok, err = pcall(fn, bufnr)
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    assert(ok, err)
  end

  --- A minimal client-shaped table that passes the `on_attach` guards.
  ---@param extra table|nil
  ---@return table
  local function client(extra)
    return vim.tbl_extend("force", { server_capabilities = { hoverProvider = true } }, extra or {})
  end

  describe("build().on_init", function()
    it("calls every on_init hook with the client", function()
      local seen = {}
      local attach = reload()
      local pair = attach.build({
        hooks = {
          on_init = {
            function(c)
              seen[#seen + 1] = { "a", c }
            end,
            function(c)
              seen[#seen + 1] = { "b", c }
            end,
          },
        },
      })

      local fake_client = { name = "test_ls" }
      local ok = pair.on_init(fake_client, {})

      assert.is_true(ok)
      assert.are.equal(2, #seen)
      assert.are.equal("a", seen[1][1])
      assert.are.same(fake_client, seen[1][2])
      assert.are.equal("b", seen[2][1])
    end)

    -- Blast-radius control, same as `lsp.integrations.setup`: one broken
    -- adapter must not take every other on_init hook down with it.
    it("keeps running the remaining hooks after one throws", function()
      local seen = {}
      local attach = reload()
      local pair = attach.build({
        hooks = {
          on_init = {
            function()
              error("boom")
            end,
            function()
              seen[#seen + 1] = true
            end,
          },
        },
      })

      local ok = pair.on_init({ name = "test_ls" }, {})

      assert.is_true(ok)
      assert.are.equal(1, #seen)
    end)

    it("returns true with no hooks at all", function()
      local attach = reload()
      local pair = attach.build(nil)

      assert.is_true(pair.on_init({ name = "test_ls" }, {}))
    end)
  end)

  describe("build() seeding workspace diagnostics", function()
    it("seeds true only when use_workspace_diagnostics is exactly true", function()
      local attach = reload()
      attach.build({ use_workspace_diagnostics = true })

      assert.is_true(wd.seeded_with)
    end)

    it("seeds false for a missing option", function()
      local attach = reload()
      attach.build(nil)

      assert.is_false(wd.seeded_with)
    end)

    it("seeds false for anything that is not the boolean true", function()
      local attach = reload()
      ---@diagnostic disable-next-line: assign-type-mismatch
      attach.build({ use_workspace_diagnostics = "yes" })

      assert.is_false(wd.seeded_with)
    end)
  end)

  describe("build().on_attach guards", function()
    it("does nothing for a nil client", function()
      local attach = reload()
      local pair = attach.build({})

      with_buf(nil, function(bufnr)
        pair.on_attach(nil, bufnr)
      end)

      assert.are.equal(0, #wd.schedule_calls)
    end)

    it("does nothing when the client is not a table", function()
      local attach = reload()
      local pair = attach.build({})

      with_buf(nil, function(bufnr)
        ---@diagnostic disable-next-line: param-type-mismatch
        pair.on_attach("not-a-client", bufnr)
      end)

      assert.are.equal(0, #wd.schedule_calls)
    end)

    it("does nothing for an unloaded/invalid buffer number", function()
      local attach = reload()
      local hooks_ran = {}
      local pair = attach.build({
        hooks = {
          on_attach = {
            function()
              hooks_ran[#hooks_ran + 1] = true
            end,
          },
        },
      })

      pair.on_attach(client(), 999999)

      assert.are.equal(0, #hooks_ran)
      assert.are.equal(0, #wd.schedule_calls)
    end)

    -- The buftypes `on_attach` must refuse: a client can attach to a
    -- `nofile`/`help`/`quickfix` buffer (netrw, `:checkhealth`, ...) and none
    -- of those should be handed to a populate walk or a formatter hook.
    -- (`terminal` is not in this list: Neovim raises `E474` on `vim.bo.
    -- buftype = "terminal"` outside of a real `:terminal`/`nvim_open_term`
    -- buffer, so it cannot be constructed this way.)
    for _, bt in ipairs({ "nofile", "help", "quickfix" }) do
      it(("refuses a %q buffer"):format(bt), function()
        local attach = reload()
        local hooks_ran = {}
        local pair = attach.build({
          hooks = {
            on_attach = {
              function()
                hooks_ran[#hooks_ran + 1] = true
              end,
            },
          },
        })

        with_buf(bt, function(bufnr)
          pair.on_attach(client(), bufnr)
        end)

        assert.are.equal(0, #hooks_ran)
      end)
    end

    -- `acwrite` is the one non-empty buftype the wrapper explicitly allows
    -- (e.g. a fugitive-style buffer that writes through a custom handler).
    it("accepts an acwrite buffer", function()
      local attach = reload()
      local hooks_ran = {}
      local pair = attach.build({
        hooks = {
          on_attach = {
            function()
              hooks_ran[#hooks_ran + 1] = true
            end,
          },
        },
      })

      with_buf("acwrite", function(bufnr)
        pair.on_attach(client(), bufnr)
      end)

      assert.are.equal(1, #hooks_ran)
    end)

    it("does nothing when the client has no server_capabilities", function()
      local attach = reload()
      local pair = attach.build({})

      with_buf(nil, function(bufnr)
        pair.on_attach({ name = "test_ls" }, bufnr)
      end)

      assert.are.equal(0, #wd.schedule_calls)
    end)
  end)

  describe("build().on_attach effects", function()
    it("schedules a populate when workspace diagnostics are enabled", function()
      local attach = reload()
      wd.enabled_value = true
      local pair = attach.build({})

      with_buf(nil, function(bufnr)
        local c = client()
        pair.on_attach(c, bufnr)

        assert.are.equal(1, #wd.schedule_calls)
        assert.are.same(c, wd.schedule_calls[1].client)
        assert.are.equal(bufnr, wd.schedule_calls[1].bufnr)
      end)
    end)

    -- `enabled()` is read fresh, not captured once at `build()` time -- the
    -- module header's whole point, and the one thing worth pinning here.
    it("does not schedule a populate when workspace diagnostics are disabled", function()
      local attach = reload()
      wd.enabled_value = false
      local pair = attach.build({})

      with_buf(nil, function(bufnr)
        pair.on_attach(client(), bufnr)
      end)

      assert.are.equal(0, #wd.schedule_calls)
    end)

    it("calls every on_attach hook with the client and bufnr", function()
      local attach = reload()
      local seen = {}
      local pair = attach.build({
        hooks = {
          on_attach = {
            function(c, b)
              seen[#seen + 1] = { "a", c, b }
            end,
            function(c, b)
              seen[#seen + 1] = { "b", c, b }
            end,
          },
        },
      })

      with_buf(nil, function(bufnr)
        local c = client()
        pair.on_attach(c, bufnr)

        assert.are.equal(2, #seen)
        assert.are.equal("a", seen[1][1])
        assert.are.same(c, seen[1][2])
        assert.are.equal(bufnr, seen[1][3])
        assert.are.equal("b", seen[2][1])
      end)
    end)

    it("keeps running the remaining on_attach hooks after one throws", function()
      local attach = reload()
      local ran = false
      local pair = attach.build({
        hooks = {
          on_attach = {
            function()
              error("boom")
            end,
            function()
              ran = true
            end,
          },
        },
      })

      with_buf(nil, function(bufnr)
        pair.on_attach(client(), bufnr)
      end)

      assert.is_true(ran)
    end)
  end)
end)
