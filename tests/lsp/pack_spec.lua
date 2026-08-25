--- Covers the pack layer's gating.
---
--- Written because the first version of this layer got it wrong in a way that
--- installs software: `import` names a *directory*, so lazy requires every
--- module under `lua/lsp/pack/` regardless of what any of them returns.
--- Conditional imports gated nothing and blink.cmp was cloned into a config
--- that had asked for nvim-cmp. Selection lives in each spec's `enabled` now,
--- and that is what these cases pin down.

describe("lsp.config.pack", function()
  --- Set `vim.g.lsp_nvim` for one case and reload the readers, which cache
  --- nothing but are required by the spec modules at load time.
  ---@param pack table|nil
  ---@return table
  local function with(pack)
    vim.g.lsp_nvim = pack and { pack = pack } or nil
    package.loaded["lsp.config.pack"] = nil
    for _, m in ipairs({ "core", "ui", "completion", "completion_blink" }) do
      package.loaded["lsp.pack." .. m] = nil
    end
    return require("lsp.config.pack")
  end

  after_each(function()
    vim.g.lsp_nvim = nil
    package.loaded["lsp.config.pack"] = nil
  end)

  describe("defaults", function()
    it("installs blink.cmp when nothing is configured", function()
      assert.are.equal("blink", with(nil).completion())
    end)

    it("has both groups on", function()
      local pack = with(nil)
      assert.is_true(pack.group("core"))
      assert.is_true(pack.group("ui"))
    end)

    it("enables every plugin", function()
      assert.is_true(with(nil).enabled("trouble.nvim", "ui"))
    end)

    it("tolerates a malformed vim.g.lsp_nvim", function()
      vim.g.lsp_nvim = "nonsense"
      package.loaded["lsp.config.pack"] = nil
      local pack = require("lsp.config.pack")
      assert.are.same({}, pack.opts())
      assert.are.equal("blink", pack.completion())
    end)
  end)

  describe("groups", function()
    it("ui = false disables the whole ui group", function()
      local pack = with({ ui = false })
      assert.is_false(pack.group("ui"))
      assert.is_false(pack.enabled("trouble.nvim", "ui"))
      -- and leaves core alone
      assert.is_true(pack.enabled("conform.nvim", "core"))
    end)

    it("core = false disables the whole core group", function()
      local pack = with({ core = false })
      assert.is_false(pack.enabled("conform.nvim", "core"))
      assert.is_true(pack.enabled("trouble.nvim", "ui"))
    end)
  end)

  describe("disable", function()
    it("drops a single plugin, group untouched", function()
      local pack = with({ disable = { "lspsaga.nvim" } })
      assert.is_false(pack.enabled("lspsaga.nvim", "ui"))
      assert.is_true(pack.enabled("trouble.nvim", "ui"))
    end)

    it("ignores a malformed disable value", function()
      assert.is_true(with({ disable = "lspsaga.nvim" }).enabled("lspsaga.nvim", "ui"))
    end)
  end)

  describe("completion", function()
    it("accepts the two engines", function()
      assert.are.equal("cmp", with({ completion = "cmp" }).completion())
      assert.are.equal("blink", with({ completion = "blink" }).completion())
    end)

    it("false means no engine", function()
      assert.is_false(with({ completion = false }).completion())
    end)

    it("an unknown engine installs neither, rather than guessing", function()
      assert.is_false(with({ completion = "coq" }).completion())
    end)
  end)

  describe("completion_accept", function()
    it("defaults to <CR>", function()
      assert.are.equal("cr", with(nil).completion_accept())
    end)

    it("takes ctrl_y", function()
      assert.are.equal("ctrl_y", with({ completion_accept = "ctrl_y" }).completion_accept())
    end)

    it("falls back to the default on anything else", function()
      -- Unlike `completion`, there is no "no accept key" -- a typo must not
      -- leave the menu with nothing bound to take the selection.
      assert.are.equal("cr", with({ completion_accept = "enter" }).completion_accept())
      assert.are.equal("cr", with({ completion_accept = false }).completion_accept())
    end)

    it("selects the matching blink preset", function()
      -- The two are not just a different key: blink's `enter` binds `accept`
      -- and `default` binds `select_and_accept`, so only the former leaves
      -- Enter alone when nothing is selected.
      with(nil)
      assert.are.equal("enter", require("lsp.pack.completion_blink")[1].opts.keymap.preset)

      with({ completion_accept = "ctrl_y" })
      assert.are.equal("default", require("lsp.pack.completion_blink")[1].opts.keymap.preset)
    end)

    it("keeps completion out of nofile buffers", function()
      -- lib.nvim.ui.kit's floats are buftype=nofile, and blink's own guard
      -- only covers buftype=prompt. With <CR> bound to accept, a rename
      -- prompt would otherwise submit a completion instead of what was typed.
      with(nil)
      local enabled = require("lsp.pack.completion_blink")[1].opts.enabled

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].buftype = "nofile"
      assert.is_false(enabled())

      -- but not out of dap's panes, which blink re-enables only if we say yes
      vim.bo[buf].filetype = "dapui_watches"
      assert.is_true(enabled())

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("specs", function()
    ---@param module string
    ---@return table[]
    local function specs(module)
      return require("lsp.pack." .. module)
    end

    it("pack/init.lua returns nothing, because import reads the directory", function()
      package.loaded["lsp.pack"] = nil
      assert.are.same({}, require("lsp.pack"))
    end)

    it("every spec names a repository and a resolved enabled flag", function()
      with(nil)
      for _, module in ipairs({ "core", "ui", "completion", "completion_blink" }) do
        for _, spec in ipairs(specs(module)) do
          assert.are.equal("string", type(spec[1]), module .. ": repo name")
          assert.is_true(spec[1]:find("/", 1, true) ~= nil, module .. ": owner/repo")
          -- A value, not a closure: lazy reads `enabled` when it resolves the
          -- spec, and by then the answer is knowable.
          assert.are.equal("boolean", type(spec.enabled), module .. ": " .. spec[1])
        end
      end
    end)

    it("the two completion engines exclude each other", function()
      with({ completion = "cmp" })
      assert.is_true(specs("completion")[1].enabled)
      assert.is_false(specs("completion_blink")[1].enabled)

      with({ completion = "blink" })
      assert.is_false(specs("completion")[1].enabled)
      assert.is_true(specs("completion_blink")[1].enabled)

      with({ completion = false })
      assert.is_false(specs("completion")[1].enabled)
      assert.is_false(specs("completion_blink")[1].enabled)
    end)

    it("ui = false disables every ui spec", function()
      with({ ui = false })
      for _, spec in ipairs(specs("ui")) do
        assert.is_false(spec.enabled, spec[1])
      end
    end)

    it("a disabled plugin is off while its group stays on", function()
      with({ disable = { "folke/trouble.nvim" } })
      -- `disable` matches the short name the specs pass to enabled(), not the
      -- "owner/repo" of the spec itself.
      for _, spec in ipairs(specs("ui")) do
        if spec[1] == "folke/trouble.nvim" then
          assert.is_true(spec.enabled, "short names are what disable matches")
        end
      end

      with({ disable = { "trouble.nvim" } })
      for _, spec in ipairs(specs("ui")) do
        if spec[1] == "folke/trouble.nvim" then
          assert.is_false(spec.enabled)
        end
      end
    end)

    it("every ui spec configures through an adapter, not inline", function()
      -- The layer rule: pack holds specs, integrations holds logic.
      with(nil)
      for _, spec in ipairs(specs("ui")) do
        if spec.config ~= nil then
          assert.are.equal("function", type(spec.config), spec[1])
        end
      end
    end)
  end)
end)
