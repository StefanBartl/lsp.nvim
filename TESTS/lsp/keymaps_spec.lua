--- Covers the keymap catalogue and the binder that reads it.
---
--- The catalogue is data, so most of what can go wrong with it is structural:
--- a preset naming an entry that does not exist, two entries quietly claiming
--- the same key in the same mode, a `minimal` that drifted out of `default`.
--- None of that shows up when you press the key -- one mapping simply wins and
--- the other never fires -- which is why it is asserted here.

local KEYMAPS = require("lsp.config.KEYMAPS")

describe("lsp.config.KEYMAPS", function()
  describe("entries", function()
    it("every entry has the fields the binder reads", function()
      for name, spec in pairs(KEYMAPS.entries) do
        assert.are.equal("string", type(spec.lhs), name .. ".lhs")
        assert.is_true(
          type(spec.mode) == "string" or type(spec.mode) == "table",
          name .. ".mode is a string or a list"
        )
        assert.is_true(
          type(spec.rhs) == "string" or type(spec.rhs) == "function",
          name .. ".rhs is a command string or a function"
        )
        assert.are.equal("string", type(spec.desc), name .. ".desc")
        assert.is_true(#spec.desc > 0, name .. ".desc is not empty")
      end
    end)

    it("no two entries claim the same lhs in the same mode", function()
      ---@type table<string, string>
      local claimed = {}
      for name, spec in pairs(KEYMAPS.entries) do
        local modes = type(spec.mode) == "table" and spec.mode or { spec.mode }
        ---@cast modes string[]
        for _, mode in ipairs(modes) do
          local key = mode .. " " .. spec.lhs
          assert.is_nil(
            claimed[key],
            ("%s and %s both claim %q"):format(tostring(claimed[key]), name, key)
          )
          claimed[key] = name
        end
      end
    end)

    it("`requires` names a plugin, never an empty string", function()
      for name, spec in pairs(KEYMAPS.entries) do
        if spec.requires ~= nil then
          assert.are.equal("string", type(spec.requires), name .. ".requires")
          assert.is_true(#spec.requires > 0, name .. ".requires is not empty")
        end
      end
    end)
  end)

  describe("presets", function()
    it("every preset the config accepts exists here", function()
      for _, preset in ipairs({ "default", "minimal", "none" }) do
        assert.are.equal("table", type(KEYMAPS.presets[preset]), preset)
      end
    end)

    it("every named entry exists in the catalogue", function()
      for preset, names in pairs(KEYMAPS.presets) do
        for _, name in ipairs(names) do
          assert.is_not_nil(
            KEYMAPS.entries[name],
            ("preset %s names %q, which is not an entry"):format(preset, name)
          )
        end
      end
    end)

    it("default covers every entry", function()
      local named = {}
      for _, name in ipairs(KEYMAPS.presets.default) do
        named[name] = true
      end
      for name in pairs(KEYMAPS.entries) do
        assert.is_true(named[name] == true, ("entry %q is in no preset"):format(name))
      end
    end)

    it("minimal is a strict subset of default", function()
      local in_default = {}
      for _, name in ipairs(KEYMAPS.presets.default) do
        in_default[name] = true
      end
      for _, name in ipairs(KEYMAPS.presets.minimal) do
        assert.is_true(in_default[name] == true, name .. " is in minimal but not in default")
      end
      assert.is_true(#KEYMAPS.presets.minimal < #KEYMAPS.presets.default)
    end)

    it("none binds nothing", function()
      assert.are.same({}, KEYMAPS.presets.none)
    end)

    it("minimal drops what Neovim 0.11 already provides", function()
      -- The stated rule for `minimal`. `grn`/`grt` and `]d`/`[d` have native
      -- equivalents; the prefixless ls* family duplicates gr*.
      local in_minimal = {}
      for _, name in ipairs(KEYMAPS.presets.minimal) do
        in_minimal[name] = true
      end
      for _, name in ipairs({
        "rename",
        "goto_type_definition_gr",
        "diag_next",
        "diag_prev",
        "goto_definition",
        "goto_references",
      }) do
        assert.is_nil(in_minimal[name], name .. " should not be in minimal")
      end
    end)
  end)

  describe("which-key groups", function()
    it("every labelled prefix has at least one entry under it", function()
      for prefix, label in pairs(KEYMAPS.groups) do
        assert.are.equal("string", type(label), prefix .. " label")
        local used = false
        for _, spec in pairs(KEYMAPS.entries) do
          if spec.lhs:sub(1, #prefix) == prefix and #spec.lhs > #prefix then
            used = true
            break
          end
        end
        assert.is_true(used, ("group %q labels a prefix nothing binds under"):format(prefix))
      end
    end)
  end)
end)

describe("lsp.bindings.keymaps", function()
  local keymaps = require("lsp.bindings.keymaps")

  ---@param overrides table|nil
  ---@param preset string|nil
  ---@return LspNvim.Config
  local function cfg(overrides, preset)
    package.loaded["lsp.config"] = nil
    return require("lsp.config").setup({
      keymaps = { preset = preset or "default", map = overrides or {} },
    })
  end

  ---@param registered table[]
  ---@return table<string, string>
  local function by_name(registered)
    local out = {}
    for _, spec in ipairs(registered) do
      out[spec.name] = spec.lhs
    end
    return out
  end

  it("binds the whole default preset", function()
    local registered = keymaps.setup(cfg())
    assert.are.equal(#KEYMAPS.presets.default, #registered)
  end)

  it("returns entries in a stable order", function()
    local first = keymaps.setup(cfg())
    local second = keymaps.setup(cfg())
    for i = 1, #first do
      assert.are.equal(first[i].name, second[i].name)
    end
  end)

  it("tags each registered entry with its catalogue name", function()
    for _, spec in ipairs(keymaps.setup(cfg())) do
      assert.is_not_nil(KEYMAPS.entries[spec.name], spec.name)
    end
  end)

  it("a string override replaces the lhs", function()
    local bound = by_name(keymaps.setup(cfg({ qf_next = "<leader>zz" })))
    assert.are.equal("<leader>zz", bound.qf_next)
  end)

  it("false drops the mapping", function()
    local bound = by_name(keymaps.setup(cfg({ rename = false })))
    assert.is_nil(bound.rename)
  end)

  it("an override for an unknown action changes nothing", function()
    local registered = keymaps.setup(cfg({ not_an_action = "<leader>zz" }))
    assert.are.equal(#KEYMAPS.presets.default, #registered)
  end)

  it("binds nothing when disabled", function()
    package.loaded["lsp.config"] = nil
    local disabled = require("lsp.config").setup({ keymaps = { enable = false } })
    assert.are.same({}, keymaps.setup(disabled))
  end)

  it("binds nothing for the none preset", function()
    assert.are.same({}, keymaps.setup(cfg(nil, "none")))
  end)

  it("binds fewer keys for minimal than for default", function()
    assert.is_true(#keymaps.setup(cfg(nil, "minimal")) < #keymaps.setup(cfg()))
  end)

  describe("rebind_buffer_local", function()
    it("binds an entry of the active preset into the buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      assert.is_true(keymaps.rebind_buffer_local(cfg(), "rename", bufnr))

      local found = false
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
        if m.lhs == "grn" then
          found = true
        end
      end
      assert.is_true(found, "grn was bound buffer-locally")
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("refuses an entry the user switched off", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      assert.is_false(keymaps.rebind_buffer_local(cfg({ rename = false }), "rename", bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("refuses an entry outside the active preset", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      assert.is_false(keymaps.rebind_buffer_local(cfg(nil, "none"), "rename", bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("refuses an unknown entry name", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      assert.is_false(keymaps.rebind_buffer_local(cfg(), "not_an_action", bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)

describe("count support (NEW-25)", function()
  local actions = require("lsp.bindings.actions")

  after_each(function()
    vim.cmd("normal! \27")
  end)

  it("the navigation actions accept an explicit count", function()
    -- The `:Lsp diag next` route passes 1 rather than letting the action read
    -- `v:count1`, which holds whatever the last keypress left behind.
    for _, name in ipairs({
      "diag_next",
      "diag_prev",
      "qf_next",
      "qf_prev",
      "loc_next",
      "loc_prev",
      "trouble_diag_next",
      "trouble_diag_prev",
    }) do
      assert.are.equal("function", type(actions[name]), name)
      assert.has_no.errors(function()
        actions[name](1)
      end, name .. " tolerates an explicit count")
    end
  end)

  it("quickfix navigation asks Vim for the count rather than looping", function()
    -- `:{count}cnext` is native. A loop would fire the autocommands N times
    -- and stop at the first E553 instead of moving as far as it can.
    local seen
    local orig = vim.cmd
    vim.cmd = function(c)
      seen = c
    end
    require("lsp.diagnostics.quickfix").next_qf(3)
    vim.cmd = orig
    assert.are.equal("3cnext", seen)
  end)

  it("diagnostic navigation passes the count to vim.diagnostic.jump", function()
    local seen
    local orig = vim.diagnostic.jump
    -- Test double, restored below.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.diagnostic.jump = function(opts)
      seen = opts
    end
    require("lsp.diagnostics.loclist").next_loc(nil, 4)
    require("lsp.diagnostics.loclist").prev_loc(nil, 2)
    local backward = seen
    vim.diagnostic.jump = orig

    assert.are.equal(-2, backward.count, "prev negates the count")
  end)

  it("]w/[w move exactly the given count, not count squared", function()
    -- Worth stubbing rather than skipping: with trouble.nvim absent every
    -- assertion about it passes vacuously -- which is how a nil `steps` got
    -- past this file once already.
    --
    -- The stub matches trouble.nvim's real shape: `open()` returns a View
    -- with `:wait()`/`:move()`, not a `next()`/`prev()` pair. Calling the
    -- view's own `next`/`prev` actions was the bug -- they read `v:count1`
    -- themselves, so looping them by a count already resolved from
    -- `v:count1` moved `n * n` instead of `n`. See actions.lua's
    -- `trouble_view_move` doc comment for the full story.
    local moved = 0
    package.loaded["trouble"] = {
      is_open = function()
        return true
      end,
      open = function()
        return {
          wait = function(_, fn)
            fn()
          end,
          move = function(_, opts)
            moved = moved + (opts.down or 0) - (opts.up or 0)
          end,
        }
      end,
    }
    actions.trouble_diag_next(3)
    assert.are.equal(3, moved, "next moved exactly three, not nine")
    actions.trouble_diag_prev(2)
    assert.are.equal(1, moved, "prev moved exactly two back")
    package.loaded["trouble"] = nil
  end)

  it("only the ordered-motion keys are meant to take one", function()
    -- Leader-prefixed actions populate a list or toggle a setting; there is no
    -- ordered target for a count to index into.
    for _, name in ipairs({ "diag_to_qflist", "diag_to_loclist", "format_toggle" }) do
      assert.is_true(
        KEYMAPS.entries[name].lhs:sub(1, 8) == "<leader>",
        name .. " is leader-prefixed, so no count is expected"
      )
    end
  end)
end)

describe("diagnostics.ui: Trouble as the ]d/[d sink (roadmap 15.1)", function()
  local actions = require("lsp.bindings.actions")

  ---@param ui "auto"|"native"|"trouble"|nil
  local function with_ui(ui)
    package.loaded["lsp.config"] = nil
    require("lsp.config").setup({ diagnostics = { ui = ui } })
  end

  after_each(function()
    package.loaded["trouble"] = nil
    package.loaded["lsp.config"] = nil
    require("lsp.config").setup({})
  end)

  ---@return table opened # { mode = ..., focused = boolean }, moved (integer)
  local function stub_trouble()
    local state = { opened = nil, moved = 0 }
    package.loaded["trouble"] = {
      open = function(opts)
        state.opened = opts
        return {
          wait = function(_, fn)
            fn()
          end,
          move = function(_, mopts)
            state.moved = state.moved + (mopts.down or 0) - (mopts.up or 0)
          end,
        }
      end,
    }
    return state
  end

  it('ui = "native" never touches Trouble, even if it is installed', function()
    with_ui("native")
    local state = stub_trouble()
    actions.diag_next(1)
    assert.is_nil(state.opened, "native must not open Trouble")
  end)

  it('ui = "trouble" opens the diagnostics list and moves by the count', function()
    with_ui("trouble")
    local state = stub_trouble()
    actions.diag_next(3)
    assert.are.equal("diagnostics", state.opened.mode)
    assert.are.equal(3, state.moved)
  end)

  it('ui = "auto" behaves like "trouble" once Trouble is actually installed', function()
    with_ui("auto")
    local state = stub_trouble()
    actions.diag_prev(2)
    assert.are.equal(-2, state.moved)
  end)

  it('ui = "auto" without Trouble installed falls back to the native jump', function()
    with_ui("auto")
    package.loaded["trouble"] = nil -- `require("trouble")` genuinely fails here

    local seen
    local orig = vim.diagnostic.jump
    -- Test double, restored below.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.diagnostic.jump = function(opts)
      seen = opts
    end
    actions.diag_next(1)
    vim.diagnostic.jump = orig

    assert.is_not_nil(seen, "fell back to the native path")
  end)

  it("opens Trouble even when it was not already open -- that is the point", function()
    -- Distinct from ]w/[w (trouble_diag_next/prev), which refuse to act on a
    -- closed list. ]d/[d are meant to behave exactly like Trouble's own
    -- next/prev when Trouble is the sink: panel and all.
    with_ui("trouble")
    local state = stub_trouble()
    actions.diag_next(1)
    assert.is_not_nil(state.opened, "]d opened the list on its own")
  end)
end)
