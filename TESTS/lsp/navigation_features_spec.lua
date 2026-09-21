--- Covers the seams that replaced lspsaga: the keymap entries, the actions
--- behind them, the `:Lsp` routes, and the config that feeds them.
---
--- What lspsaga offered and lsp.nvim now does itself arrives as five kinds of
--- thing, and each has one way of failing silently: a key that is in the
--- catalogue but bound to nothing real, an action that falls back to the wrong
--- picker, a route that exists but is not reachable, a config value that is
--- accepted and ignored, and -- the one that motivated this file -- a
--- `ls*` key added to the catalogue that quietly extends the wait every
--- Normal-mode `l` pays. Each case below fixes one of those.

local KEYMAPS = require("lsp.config.KEYMAPS")

--- Collect what the actions notify, without touching the real notifier.
---@return string[] said
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

describe("the lspsaga replacement: keymap catalogue", function()
  local entries = KEYMAPS.entries

  it("has every entry the gap report named, on the key it proposed", function()
    local want = {
      peek_definition = "lsp",
      peek_type_definition = "lsT",
      picker_finder = "lsf",
      picker_type_super = "lsh",
      picker_type_sub = "lsH",
      trouble_outline = "<leader>xo",
      diag_code_action = "<leader>xa",
      winbar_toggle = "<leader>tW",
    }
    for name, lhs in pairs(want) do
      assert.is_not_nil(entries[name], name .. " is missing")
      assert.are.equal(lhs, entries[name].lhs, name)
    end
  end)

  -- `{ "n", "x" }` for one commit. `lsa` starts with `l`, and a Visual-mode
  -- mapping that starts with `l` makes every `l` there wait out 'timeoutlen'
  -- for an `s` -- measured, `mapcheck("l", "x")` answered with this mapping --
  -- and `vl` / `vjl` are how a selection gets extended.
  it("keeps `lsa` on the code-action entry, in Normal mode only", function()
    assert.are.equal("lsa", entries.code_action.lhs)
    assert.are.equal("n", entries.code_action.mode)
    assert.are.equal("function", type(entries.code_action.rhs))
  end)

  it(
    "gives a selection its code actions on `gra`, which is already a prefix in Visual mode",
    function()
      local range = entries.code_action_range
      assert.is_not_nil(range, "the range entry is missing")
      assert.are.equal("gra", range.lhs)
      assert.are.equal("x", range.mode)
      assert.are.equal(entries.code_action.rhs, range.rhs, "a different action than `lsa`")
      assert.is_true(vim.tbl_contains(KEYMAPS.presets.default, "code_action_range"))
      assert.is_false(vim.tbl_contains(KEYMAPS.presets.minimal, "code_action_range"))
    end
  )

  it("names the plugin an entry needs, and only where it needs one", function()
    assert.are.equal("fzf-lua", entries.picker_finder.requires)
    assert.are.equal("trouble", entries.trouble_outline.requires)
    -- The type hierarchy has a native fallback, and peek needs no plugin.
    assert.is_nil(entries.picker_type_super.requires)
    assert.is_nil(entries.picker_type_sub.requires)
    assert.is_nil(entries.peek_definition.requires)
    assert.is_nil(entries.peek_type_definition.requires)
  end)

  it("puts every new entry in `default` and none of them in `minimal`", function()
    local added = {
      "peek_definition",
      "peek_type_definition",
      "picker_finder",
      "picker_type_super",
      "picker_type_sub",
      "trouble_outline",
      "diag_code_action",
      "winbar_toggle",
    }
    for _, name in ipairs(added) do
      assert.is_true(vim.tbl_contains(KEYMAPS.presets.default, name), name .. " not in default")
      assert.is_false(
        vim.tbl_contains(KEYMAPS.presets.minimal, name),
        name .. " leaked into minimal"
      )
    end
  end)

  it("has a description for each, because the menu and which-key print it", function()
    for _, name in ipairs({
      "peek_definition",
      "picker_finder",
      "diag_code_action",
      "winbar_toggle",
    }) do
      assert.is_true(#entries[name].desc > 10, name)
    end
  end)

  it("puts the toggles and the peeks in the right menu groups", function()
    local menu_src = table.concat(
      vim.fn.readfile(vim.api.nvim_get_runtime_file("lua/lsp/integrations/menu.lua", false)[1]),
      "\n"
    )
    assert.is_truthy(menu_src:find('name:match("^winbar_")', 1, true))
  end)
end)

describe("the lspsaga replacement: actions", function()
  local actions
  local said, restore
  local real_fzf, real_native, real_clients, real_diagnostic_get

  before_each(function()
    said, restore = capture_notify()
    require("lsp.config").setup({})
    package.loaded["lsp.bindings.actions"] = nil
    actions = require("lsp.bindings.actions")
    real_fzf = package.loaded["fzf-lua"]
    real_native = vim.lsp.buf.code_action
    real_clients = vim.lsp.get_clients
    real_diagnostic_get = vim.diagnostic.get
    -- No real fzf-lua in the harness: `pcall(require, "fzf-lua")` must fail
    -- unless a case installs one.
    package.loaded["fzf-lua"] = nil
    package.preload["fzf-lua"] = nil
  end)

  after_each(function()
    restore()
    package.loaded["fzf-lua"] = real_fzf
    package.preload["fzf-lua"] = nil
    vim.lsp.buf.code_action = real_native
    vim.lsp.get_clients = real_clients
    vim.diagnostic.get = real_diagnostic_get
  end)

  describe("code_action", function()
    it("opens fzf-lua's picker, silently, when fzf-lua is installed", function()
      local got
      package.loaded["fzf-lua"] = {
        lsp_code_actions = function(o)
          got = o
        end,
      }
      local native = false
      vim.lsp.buf.code_action = function()
        native = true
      end

      actions.code_action()
      assert.is_table(got)
      assert.is_true(got.silent, "fzf-lua would warn that it is not the ui.select backend")
      assert.is_false(native)
    end)

    it("falls back to the native list when fzf-lua is missing", function()
      local native = false
      vim.lsp.buf.code_action = function()
        native = true
      end
      actions.code_action()
      assert.is_true(native)
      assert.are.same({}, said, "auto must fall back without a word")
    end)

    it('uses the native list when the picker is "native", fzf-lua or not', function()
      require("lsp.config").setup({ code_actions = { picker = "native" } })
      local fzf = false
      package.loaded["fzf-lua"] = {
        lsp_code_actions = function()
          fzf = true
        end,
      }
      local native = false
      vim.lsp.buf.code_action = function()
        native = true
      end
      actions.code_action()
      assert.is_true(native)
      assert.is_false(fzf)
    end)

    it('says so when the picker is pinned to "fzf-lua" and it is missing', function()
      require("lsp.config").setup({ code_actions = { picker = "fzf-lua" } })
      local native = false
      vim.lsp.buf.code_action = function()
        native = true
      end
      actions.code_action()
      assert.is_true(native, "the key must still do something")
      assert.is_truthy(said[1] and said[1]:find("not installed", 1, true))
    end)

    it("hands a context through to whichever picker it uses", function()
      local context = { only = { "quickfix" } }
      local got
      vim.lsp.buf.code_action = function(o)
        got = o
      end
      actions.code_action({ context = context })
      assert.are.same(context, got.context)
    end)
  end)

  describe("diag_code_action", function()
    it("asks for quickfixes for the diagnostics on the line, in their LSP shape", function()
      local lsp_shape = { message = "unused", range = {} }
      vim.diagnostic.get = function()
        return { { lnum = 0, user_data = { lsp = lsp_shape } }, { lnum = 0 } }
      end
      local got
      vim.lsp.buf.code_action = function(o)
        got = o
      end
      actions.diag_code_action()
      assert.are.same({ lsp_shape }, got.context.diagnostics)
      assert.are.same({ "quickfix" }, got.context.only)
    end)

    it("says so, and asks nobody, when the line has no LSP diagnostic", function()
      vim.diagnostic.get = function()
        return { { lnum = 0, message = "from a linter" } }
      end
      local asked = false
      vim.lsp.buf.code_action = function()
        asked = true
      end
      actions.diag_code_action()
      assert.is_false(asked)
      assert.is_truthy(said[1] and said[1]:find("no LSP diagnostic", 1, true))
    end)
  end)

  describe("finder", function()
    it("needs fzf-lua and says so", function()
      actions.finder()
      assert.is_truthy(said[1] and said[1]:find("needs fzf-lua", 1, true))
    end)

    it("merges references, implementations and definitions by default, in that order", function()
      local got
      package.loaded["fzf-lua"] = {
        lsp_finder = function(o)
          got = o
        end,
      }
      actions.finder()
      assert.are.same(
        { "references", "implementations", "definitions" },
        vim.tbl_map(function(p)
          return p[1]
        end, got.providers)
      )
    end)

    it("follows finder.* for what goes into the list", function()
      require("lsp.config").setup({
        finder = { references = false, declarations = true, typedefs = true },
      })
      local got
      package.loaded["fzf-lua"] = {
        lsp_finder = function(o)
          got = o
        end,
      }
      actions.finder()
      assert.are.same(
        { "implementations", "definitions", "declarations", "typedefs" },
        vim.tbl_map(function(p)
          return p[1]
        end, got.providers)
      )
    end)

    it("refuses to open an empty list when every source is off", function()
      require("lsp.config").setup({
        finder = {
          references = false,
          implementations = false,
          definitions = false,
        },
      })
      local opened = false
      package.loaded["fzf-lua"] = {
        lsp_finder = function()
          opened = true
        end,
      }
      actions.finder()
      assert.is_false(opened)
      assert.is_truthy(said[1] and said[1]:find("switched off", 1, true))
    end)

    it("labels the sources with colour when fzf-lua offers it, and plain text otherwise", function()
      local got
      package.loaded["fzf-lua"] = {
        utils = {
          ansi_codes = {
            blue = function(s)
              return "<blue>" .. s
            end,
          },
        },
        lsp_finder = function(o)
          got = o
        end,
      }
      actions.finder()
      assert.are.equal("<blue>ref ", got.providers[1].prefix)
      assert.are.equal("impl", got.providers[2].prefix)
    end)
  end)

  describe("type hierarchy", function()
    it("says which servers can answer it when none attached does", function()
      vim.lsp.get_clients = function()
        return {}
      end
      actions.type_super()
      actions.type_sub()
      assert.are.equal(2, #said)
      assert.is_truthy(said[1]:find("clangd", 1, true))
      assert.is_truthy(said[1]:find("gopls", 1, true))
    end)

    it("asks for the capability, not for any client", function()
      local asked
      vim.lsp.get_clients = function(filter)
        asked = filter
        return {}
      end
      actions.type_super()
      assert.are.equal("textDocument/prepareTypeHierarchy", asked.method)
    end)

    it("uses fzf-lua's picker per direction when it is there", function()
      vim.lsp.get_clients = function()
        return { {} }
      end
      local called = {}
      package.loaded["fzf-lua"] = {
        lsp_type_super = function()
          called[#called + 1] = "super"
        end,
        lsp_type_sub = function()
          called[#called + 1] = "sub"
        end,
      }
      actions.type_super()
      actions.type_sub()
      assert.are.same({ "super", "sub" }, called)
    end)

    it("falls back to Neovim's own request without fzf-lua", function()
      vim.lsp.get_clients = function()
        return { {} }
      end
      local real = vim.lsp.buf.typehierarchy
      local got = {}
      vim.lsp.buf.typehierarchy = function(kind)
        got[#got + 1] = kind
      end
      actions.type_super()
      actions.type_sub()
      vim.lsp.buf.typehierarchy = real
      assert.are.same({ "supertypes", "subtypes" }, got)
    end)
  end)

  describe("peek", function()
    it("asks the peek module for the right kind", function()
      local real = package.loaded["lsp.core.peek"]
      local kinds = {}
      package.loaded["lsp.core.peek"] = {
        peek = function(kind)
          kinds[#kinds + 1] = kind
        end,
      }
      actions.peek_definition()
      actions.peek_type_definition()
      package.loaded["lsp.core.peek"] = real
      assert.are.same({ "definition", "type_definition" }, kinds)
    end)
  end)

  describe("winbar toggles", function()
    it("toggle globally, and per filetype only for a buffer that has one", function()
      local calls = {}
      local real = package.loaded["lsp.core.winbar"]
      package.loaded["lsp.core.winbar"] = {
        toggle = function(ft)
          calls[#calls + 1] = ft or "global"
        end,
      }
      vim.cmd("enew!")
      vim.bo.filetype = ""
      actions.winbar_toggle()
      actions.winbar_toggle_filetype()
      assert.are.same({ "global" }, calls)
      assert.is_truthy(said[1] and said[1]:find("no filetype", 1, true))

      vim.bo.filetype = "lua"
      actions.winbar_toggle_filetype()
      package.loaded["lsp.core.winbar"] = real
      assert.are.same({ "global", "lua" }, calls)
    end)
  end)
end)

describe("the lspsaga replacement: :Lsp routes", function()
  ---@return string[]
  local function completions(cmdline)
    return vim.fn.getcompletion(cmdline, "cmdline")
  end

  before_each(function()
    require("lsp.config").setup({})
    require("lsp.bindings.usrcmds").setup()
  end)

  it("registers winbar, implement and peek under :Lsp", function()
    local subs = completions("Lsp ")
    for _, route in ipairs({ "winbar", "implement", "peek" }) do
      assert.is_true(vim.tbl_contains(subs, route), route .. " is not a route")
    end
  end)

  it("completes the switch actions the other indicators have", function()
    for _, route in ipairs({ "winbar", "implement" }) do
      local offered = completions("Lsp " .. route .. " ")
      table.sort(offered)
      assert.are.same({ "clear", "off", "on", "status", "toggle" }, offered)
    end
  end)

  it("completes the four peek kinds", function()
    local kinds = completions("Lsp peek ")
    for _, kind in ipairs({ "definition", "type_definition", "implementation", "declaration" }) do
      assert.is_true(vim.tbl_contains(kinds, kind), kind)
    end
  end)

  it("drives the winbar module through `:Lsp winbar`", function()
    local winbar = require("lsp.core.winbar")
    winbar.setup({ enable = true })
    vim.cmd("Lsp winbar off")
    assert.is_false(winbar.enabled(nil))
    vim.cmd("Lsp winbar on")
    assert.is_true(winbar.enabled(nil))
    vim.cmd("Lsp winbar off lua")
    assert.is_false(winbar.enabled("lua"))
    vim.cmd("Lsp winbar clear lua")
    assert.is_true(winbar.enabled("lua"))
    winbar.detach()
  end)

  it("needs a filetype for `clear`, like hints and lightbulb", function()
    local said, restore = capture_notify()
    package.loaded["lsp.bindings.usrcmds"] = nil
    require("lsp.bindings.usrcmds").setup()
    vim.cmd("Lsp implement clear")
    restore()
    assert.is_truthy(said[1] and said[1]:find("needs a filetype", 1, true))
  end)

  it("completes filetypes that carry a winbar or implement override", function()
    local winbar = require("lsp.core.winbar")
    winbar.setup({ filetypes = { zzoverridden = false } })
    assert.is_true(vim.tbl_contains(completions("Lsp winbar off "), "zzoverridden"))
    winbar.detach()
  end)
end)

describe("the lspsaga replacement: config", function()
  ---@param opts table
  ---@return LspNvim.Config cfg, string[] warnings
  local function setup(opts)
    package.loaded["lsp.config"] = nil
    local config = require("lsp.config")
    local cfg = config.setup(opts)
    return cfg, config.warnings()
  end

  it("has the documented defaults, and nothing to warn about", function()
    local cfg, warnings = setup({})
    assert.are.same({}, warnings)
    assert.is_true(cfg.winbar.enable)
    assert.are.same({ markdown = 1 }, cfg.winbar.max_symbols)
    assert.is_false(cfg.implement.enable)
    assert.are.equal("auto", cfg.code_actions.picker)
    assert.is_false(cfg.code_actions.gitsigns)
    assert.is_true(cfg.finder.references)
    assert.are.equal("q", cfg.peek.keys.close)
  end)

  it("merges a partial max_symbols over the default instead of replacing it", function()
    local cfg = setup({ winbar = { max_symbols = { lua = 2 } } })
    assert.are.same({ markdown = 1, lua = 2 }, cfg.winbar.max_symbols)
  end)

  it("lets `markdown = false` lift the default cap", function()
    local cfg, warnings = setup({ winbar = { max_symbols = { markdown = false } } })
    assert.are.same({}, warnings)
    assert.are.equal(false, cfg.winbar.max_symbols.markdown)
  end)

  it("drops a malformed max_symbols entry and says which", function()
    local cfg, warnings = setup({ winbar = { max_symbols = { lua = "deep", go = -1, ok = 2 } } })
    assert.are.equal(2, cfg.winbar.max_symbols.ok)
    assert.is_nil(cfg.winbar.max_symbols.lua)
    assert.is_nil(cfg.winbar.max_symbols.go)
    assert.are.equal(2, #warnings)
    assert.is_truthy(warnings[1]:find("winbar.max_symbols", 1, true))
  end)

  it("pulls every malformed winbar value back to its default, with a warning each", function()
    local cfg, warnings = setup({
      winbar = {
        enable = "yes",
        show_file = 1,
        chips = "no",
        separator = 5,
        folder_level = -1,
        debounce_ms = "fast",
        refresh_ms = {},
        filetypes = { "lua" },
      },
    })
    assert.is_true(cfg.winbar.enable)
    assert.is_true(cfg.winbar.show_file)
    assert.is_true(cfg.winbar.chips)
    assert.are.equal(" › ", cfg.winbar.separator)
    assert.are.equal(1, cfg.winbar.folder_level)
    assert.are.equal(60, cfg.winbar.debounce_ms)
    assert.are.equal(300, cfg.winbar.refresh_ms)
    assert.are.equal(8, #warnings)
  end)

  it("takes peek sizes as fractions or cells, and refuses zero and negatives", function()
    local cfg = setup({ peek = { width = 0.4, height = 12 } })
    assert.are.equal(0.4, cfg.peek.width)
    assert.are.equal(12, cfg.peek.height)

    local bad, warnings = setup({ peek = { width = 0, height = -3, border = 5, beacon = "yes" } })
    assert.are.equal(0.7, bad.peek.width)
    assert.are.equal(0.5, bad.peek.height)
    assert.are.equal("rounded", bad.peek.border)
    assert.is_true(bad.peek.beacon)
    assert.are.equal(4, #warnings)
  end)

  it("merges peek.keys per action, and drops a key for an action that does not exist", function()
    local cfg, warnings = setup({ peek = { keys = { close = "<Esc>", zap = "z", edit = false } } })
    assert.are.equal("<Esc>", cfg.peek.keys.close)
    assert.are.equal(false, cfg.peek.keys.edit)
    assert.are.equal("<C-v>", cfg.peek.keys.vsplit)
    assert.is_nil(cfg.peek.keys.zap)
    assert.are.equal(1, #warnings)
  end)

  it("validates the implement options", function()
    local cfg, warnings = setup({
      implement = {
        enable = "on",
        text = 3,
        debounce_ms = -1,
        max_requests = 0,
        kinds = { Interface = true, Class = "yes", [1] = true },
        filetypes = { typescript = true, lua = "no" },
      },
    })
    assert.is_false(cfg.implement.enable)
    assert.are.equal(" %d impl", cfg.implement.text)
    assert.are.equal(600, cfg.implement.debounce_ms)
    assert.are.equal(20, cfg.implement.max_requests)
    assert.are.same({ Interface = true }, cfg.implement.kinds)
    assert.are.same({ typescript = true }, cfg.implement.filetypes)
    assert.are.equal(7, #warnings)
  end)

  -- `implement.text` goes through `string.format` on every answer. A string that
  -- cannot print a number would fail there each time, so it is refused up front
  -- and named, instead of being accepted and never drawing a marker.
  it("refuses an implement.text that cannot print a count, and takes %% for a percent", function()
    for _, text in ipairs({ "impl", " %d% impl", "%d %d" }) do
      local cfg, warnings = setup({ implement = { text = text } })
      assert.are.equal(" %d impl", cfg.implement.text, text)
      assert.are.equal(1, #warnings, text)
      assert.is_truthy(warnings[1]:find("implement.text", 1, true), text)
    end

    local cfg, warnings = setup({ implement = { text = " %d%% impl" } })
    assert.are.equal(" %d%% impl", cfg.implement.text)
    assert.are.same({}, warnings)
  end)

  it("accepts each code-action picker and refuses the rest", function()
    for _, picker in ipairs({ "auto", "fzf-lua", "native" }) do
      local cfg, warnings = setup({ code_actions = { picker = picker } })
      assert.are.equal(picker, cfg.code_actions.picker)
      assert.are.same({}, warnings)
    end
    local cfg, warnings = setup({ code_actions = { picker = "telescope", gitsigns = "yes" } })
    assert.are.equal("auto", cfg.code_actions.picker)
    assert.is_false(cfg.code_actions.gitsigns)
    assert.are.equal(2, #warnings)
  end)

  it("validates the finder switches", function()
    local cfg, warnings = setup({ finder = { references = "yes", declarations = true } })
    assert.is_true(cfg.finder.references)
    assert.is_true(cfg.finder.declarations)
    assert.are.equal(1, #warnings)
  end)

  it("names the layer a bad value came from", function()
    local _, warnings = setup({ winbar = { chips = "no" } })
    assert.is_truthy(warnings[1]:find("from setup()", 1, true))
  end)

  it("lean turns the breadcrumb off, full turns the extras on", function()
    local lean = setup({ preset = "lean" })
    assert.is_false(lean.winbar.enable)
    assert.is_false(lean.implement.enable)

    local full = setup({ preset = "full" })
    assert.is_true(full.winbar.enable)
    assert.is_true(full.implement.enable)
    assert.is_true(full.code_actions.gitsigns)
  end)

  it("still lets an explicit option beat a preset", function()
    local cfg = setup({ preset = "lean", winbar = { enable = true } })
    assert.is_true(cfg.winbar.enable)
  end)

  it("lets a project file change none of them", function()
    local project = require("lsp.config.project")
    for _, key in ipairs({ "winbar", "peek", "implement", "code_actions", "finder" }) do
      assert.is_nil(project.ALLOWED[key], key .. " must not be steerable from a checkout")
    end
  end)
end)
