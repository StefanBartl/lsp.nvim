--- Covers `lsp.bindings.actions` and the two binders around it,
--- `lsp.bindings.keymaps` and `lsp.bindings.which_key`.
---
--- The shape of every bug pinned here is the same one this plugin keeps
--- producing: the action runs, nobody sees an error, and the thing it claimed
--- to do did not happen. `:Lsp`'s own `pcall` and which-key's `pcall` both
--- swallow the evidence, so the assertions have to be about observable
--- behaviour -- what was fed to the command line, what the user was told, what
--- is actually mapped in the buffer -- rather than about a return code.
---
--- Four measurements, each reproduced headless before it was written down:
---
--- 1. `actions.rename()` raised `E348: No string under cursor` whenever the
---    cursor was not on a word. `vim.fn.expand("<cword>")` is not total.
--- 2. `format_status`/`workspace_status` reported `off`/`OFF` when the module
---    behind them could not be loaded at all -- a state nobody had read.
--- 3. `keymaps.rebind_buffer_local` refused an entry outside the preset even
---    when the user's `keymaps.map` had re-enabled it with an explicit lhs, so
---    Neovim's own buffer-local `grn` beat the one `setup()` had just bound.
--- 4. `which_key.setup` returned "2 groups registered" after the registration
---    call raised and registered nothing.

local KEYMAPS = require("lsp.config.KEYMAPS")

--- Collect what the actions notify, without touching the real notifier.
---@return string[] said # "<level>: <message>", in order.
---@return function restore
local function capture_notify()
  ---@type string[]
  local said = {}
  local real = package.loaded["lib.nvim.notify"]
  package.loaded["lib.nvim.notify"] = {
    create = function()
      return setmetatable({}, {
        __index = function(_, level)
          return function(msg)
            said[#said + 1] = level .. ": " .. tostring(msg)
          end
        end,
      })
    end,
  }
  return said, function()
    package.loaded["lib.nvim.notify"] = real
  end
end

--- A scratch buffer holding `lines`, with the cursor at `pos`.
---@param lines string[]
---@param pos integer[]
---@return integer bufnr
local function scratch(lines, pos)
  vim.cmd("enew!")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, pos)
  return vim.api.nvim_get_current_buf()
end

describe("lsp.bindings.actions", function()
  local actions

  before_each(function()
    require("lsp.config").setup({})
    actions = require("lsp.bindings.actions")
  end)

  describe("rename", function()
    local feedkeys

    before_each(function()
      feedkeys = vim.api.nvim_feedkeys
      package.loaded["inc_rename"] = {}
    end)

    after_each(function()
      vim.api.nvim_feedkeys = feedkeys
      package.loaded["inc_rename"] = nil
    end)

    it("hands inc-rename the word under the cursor", function()
      local fed
      vim.api.nvim_feedkeys = function(keys)
        fed = keys
      end
      scratch({ "local myvar = 1" }, { 1, 6 })

      actions.rename()
      assert.are.equal(":IncRename myvar", fed)
    end)

    it("does not raise on a line with no word under the cursor", function()
      -- `vim.fn.expand("<cword>")` raises E348 there rather than returning "".
      -- Unguarded, pressing `grn` on a blank line inside an ordinary file threw
      -- that error out of the keymap callback.
      vim.api.nvim_feedkeys = function() end
      local said, restore = capture_notify()

      for _, case in ipairs({
        { name = "blank line", lines = { "", "local myvar = 1" }, pos = { 1, 0 } },
        { name = "whitespace only", lines = { "    ", "local myvar = 1" }, pos = { 1, 2 } },
      }) do
        scratch(case.lines, case.pos)
        local ok, err = pcall(actions.rename)
        assert.is_true(ok, case.name .. ": " .. tostring(err))
      end

      restore()
      assert.are.same({
        "warn: no symbol under the cursor",
        "warn: no symbol under the cursor",
      }, said)
    end)

    it("never reaches inc-rename with an empty name", function()
      local fed = "untouched"
      vim.api.nvim_feedkeys = function(keys)
        fed = keys
      end
      local _, restore = capture_notify()
      scratch({ "", "x" }, { 1, 0 })

      actions.rename()
      restore()
      assert.are.equal("untouched", fed)
    end)
  end)

  describe("status actions", function()
    --- Run `fn` with `mod` unloadable, so the action has to cope with the
    --- module behind it being absent.
    ---@param mod string
    ---@param fn fun(said: string[])
    local function without(mod, fn)
      local loaded, preload = package.loaded[mod], package.preload[mod]
      package.loaded[mod] = nil
      package.preload[mod] = function()
        error(mod .. " is not installed")
      end

      local said, restore = capture_notify()
      local ok, err = pcall(fn, said)

      restore()
      package.preload[mod] = preload
      package.loaded[mod] = loaded
      assert.is_true(ok, tostring(err))
    end

    it("format_status does not report `off` when there is no engine", function()
      without("lsp.formatter", function(said)
        actions.format_status()
        assert.are.equal(1, #said)
        assert.is_nil(
          said[1]:match("format%-on%-save: off"),
          "reported a state it could not read: " .. said[1]
        )
        assert.is_not_nil(said[1]:match("^warn:"), said[1])
      end)
    end)

    it("workspace_status does not report `OFF` when the module is absent", function()
      without("lsp.core.workspace_diagnostics", function(said)
        actions.workspace_status()
        assert.are.equal(1, #said)
        assert.is_nil(
          said[1]:match("attach: OFF"),
          "reported a state it could not read: " .. said[1]
        )
        assert.is_not_nil(said[1]:match("^warn:"), said[1])
      end)
    end)
  end)

  describe("the whole exported surface", function()
    it("every action is callable", function()
      -- The check this plugin's history asks for: a rename once left an
      -- exported action calling a function that no longer existed, and the
      -- command's own `pcall` swallowed it for a whole release.
      scratch({ "local myvar = 1" }, { 1, 6 })
      vim.bo.filetype = "lua"

      ---@type string[]
      local names = {}
      for name, value in pairs(actions) do
        if type(value) == "function" then
          names[#names + 1] = name
        end
      end
      table.sort(names)
      assert.is_true(#names > 30, "expected the full action surface, got " .. #names)

      ---@type string[]
      local raised = {}
      local _, restore = capture_notify()
      for _, name in ipairs(names) do
        local ok, err = pcall(actions[name])
        if not ok then
          raised[#raised + 1] = name .. ": " .. tostring(err)
        end
      end
      restore()

      vim.cmd("silent! only")
      assert.are.same({}, raised)
    end)
  end)
end)

describe("lsp.bindings.keymaps.rebind_buffer_local", function()
  --- An entry `default` has and `minimal` does not: the case where "is it in
  --- the preset" and "did `setup()` bind it" give different answers. `rename`
  --- by preference, because that is the pairing the LspAttach defender exists
  --- for (Neovim's own buffer-local `grn`), but any such entry proves it.
  ---@return string name
  ---@return string lhs
  local function out_of_preset()
    ---@type table<string, boolean>
    local in_minimal = {}
    for _, name in ipairs(KEYMAPS.presets.minimal) do
      in_minimal[name] = true
    end
    if not in_minimal.rename then
      return "rename", KEYMAPS.entries.rename.lhs
    end
    for _, name in ipairs(KEYMAPS.presets.default) do
      if not in_minimal[name] then
        return name, KEYMAPS.entries[name].lhs
      end
    end
    error("this test needs an entry `default` has and `minimal` does not")
  end

  it("defends an out-of-preset entry the user re-enabled by lhs", function()
    -- `setup()` binds it -- an explicit lhs beats "not in the preset", because
    -- out-of-preset entries are forced off there only when the user said
    -- nothing. So the LspAttach defender has to agree that it is bound, or the
    -- two disagree about which keys exist and `rename.provider` stops reaching
    -- the key in any buffer that does shadow it.
    --
    -- The shadow has to be staged, which it did not used to be: the defender
    -- re-bound unconditionally, so this passed without one. Neovim does not
    -- install a buffer-local `gr*` mapping on attach -- measured global before
    -- and after on 0.12.2 -- so the only way to exercise the defender is to put
    -- a Neovim-shaped default there by hand.
    local name, lhs = out_of_preset()
    local cfg = require("lsp.config").setup({
      keymaps = { preset = "minimal", map = { [name] = lhs } },
    })
    local keymaps = require("lsp.bindings.keymaps")

    local bound = {}
    for _, e in ipairs(keymaps.setup(cfg)) do
      bound[e.name] = e.lhs
    end
    assert.are.equal(lhs, bound[name], "setup() did not bind it; the premise is gone")

    vim.cmd("enew!")
    local bufnr = vim.api.nvim_get_current_buf()
    vim.keymap.set("n", lhs, function() end, {
      buffer = bufnr,
      desc = "vim.lsp.buf.rename()",
    })
    assert.is_true(keymaps.rebind_buffer_local(cfg, name, bufnr))

    local found
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
      if m.lhs == lhs then
        found = m.desc
      end
    end
    assert.are.equal("LSP: " .. KEYMAPS.entries[name].desc, found)
  end)

  it("still refuses an entry the user said nothing about", function()
    local name = out_of_preset()
    local cfg = require("lsp.config").setup({ keymaps = { preset = "minimal" } })
    local keymaps = require("lsp.bindings.keymaps")
    keymaps.setup(cfg)

    vim.cmd("enew!")
    assert.is_false(keymaps.rebind_buffer_local(cfg, name, vim.api.nvim_get_current_buf()))
  end)

  it("still refuses an entry the user switched off", function()
    local name = out_of_preset()
    local cfg = require("lsp.config").setup({
      keymaps = { preset = "default", map = { [name] = false } },
    })
    local keymaps = require("lsp.bindings.keymaps")
    keymaps.setup(cfg)

    vim.cmd("enew!")
    assert.is_false(keymaps.rebind_buffer_local(cfg, name, vim.api.nvim_get_current_buf()))
  end)
end)

describe("lsp.bindings.which_key", function()
  local which_key, cfg, registered
  local saved

  before_each(function()
    cfg = require("lsp.config").setup({})
    which_key = require("lsp.bindings.which_key")
    registered = require("lsp.bindings.keymaps").setup(cfg)
    saved = package.loaded["which-key"]
  end)

  after_each(function()
    package.loaded["which-key"] = saved
  end)

  it("counts nothing when the registration call raised", function()
    package.loaded["which-key"] = {
      add = function()
        error("which-key rejected the spec")
      end,
    }
    assert.are.equal(0, which_key.setup(cfg, registered))
  end)

  it("counts what it registered when the call went through", function()
    local got
    package.loaded["which-key"] = {
      add = function(groups)
        got = groups
      end,
    }
    local count = which_key.setup(cfg, registered)
    assert.is_true(count > 0)
    assert.are.equal(count, #got)
  end)

  it("hands which-key the prefixes in the one order a second run repeats", function()
    -- The groups were collected with `pairs` over `KEYMAPS.groups`, which put
    -- `<leader>xl` ahead of `<leader>x` -- an order no second run has to
    -- repeat.
    --
    -- Asserted as *sorted*, not as "the same twice", and the difference is the
    -- whole case: `pairs` is stable for one table's contents within a process,
    -- so comparing two runs here passes on the broken code. It did, on the
    -- first machine this was checked on; the defect only shows between
    -- sessions, where LuaJIT reseeds its string hashes. Sorted order is the
    -- claim a suite can actually hold.
    local got
    package.loaded["which-key"] = {
      add = function(groups)
        got = groups
      end,
    }
    which_key.setup(cfg, registered)

    ---@type string[]
    local prefixes = {}
    for _, g in ipairs(got) do
      prefixes[#prefixes + 1] = g[1]
    end
    local sorted = vim.deepcopy(prefixes)
    table.sort(sorted)
    assert.are.same(sorted, prefixes)
  end)

  it("uses which-key v2's `register` when `add` is absent", function()
    local got
    package.loaded["which-key"] = {
      register = function(mappings)
        got = mappings
      end,
    }
    local count = which_key.setup(cfg, registered)
    assert.is_true(count > 0)
    assert.are.equal(count, vim.tbl_count(got))
  end)
end)
