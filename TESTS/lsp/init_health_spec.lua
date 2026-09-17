-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
--- Defects found by provoking `lsp.init` and `lsp.health` rather than by
--- reading them. Every case here was first run against the version in HEAD and
--- watched to fail; the comment on each says what the old code did, with the
--- number that was measured.
---
--- The two files are tested together because the interesting failures cross
--- between them: what `setup()` records is what `:checkhealth lsp` reads, so a
--- bootstrap that aborts halfway is a report that lies.
---
--- Everything is stubbed at the `package.loaded` boundary. A real `setup()`
--- registers ~50 keymaps, ~40 commands and a handful of autocommands into the
--- test session and starts language servers; none of that is what these cases
--- are about.

describe("lsp.init / lsp.health defects", function()
  ---@type { level: string, msg: string, advice: string[]|nil }[]
  local emitted = {}

  ---@type table<string, any>
  local saved_loaded = {}

  ---@type table<string, any>
  local saved = {}

  --- Remember a module's current `package.loaded` entry once, then replace it.
  ---@param modname string
  ---@param value any
  ---@return nil
  local function stub(modname, value)
    if saved_loaded[modname] == nil then
      saved_loaded[modname] = { package.loaded[modname] }
    end
    package.loaded[modname] = value
  end

  --- Find the first emitted line containing `needle`.
  ---@param needle string
  ---@return { level: string, msg: string, advice: string[]|nil }|nil
  local function find(needle)
    for _, entry in ipairs(emitted) do
      if entry.msg:find(needle, 1, true) then
        return entry
      end
    end
    return nil
  end

  --- A `vim.health` that records instead of writing into a report buffer.
  ---@return nil
  local function record_health()
    emitted = {}
    vim.health = {
      start = function(msg)
        emitted[#emitted + 1] = { level = "start", msg = tostring(msg) }
      end,
      ok = function(msg)
        emitted[#emitted + 1] = { level = "ok", msg = tostring(msg) }
      end,
      info = function(msg)
        emitted[#emitted + 1] = { level = "info", msg = tostring(msg) }
      end,
      warn = function(msg, advice)
        emitted[#emitted + 1] = { level = "warn", msg = tostring(msg), advice = advice }
      end,
      error = function(msg, advice)
        emitted[#emitted + 1] = { level = "error", msg = tostring(msg), advice = advice }
      end,
    }
  end

  --- A no-op stand-in for every bootstrap step `lsp.init` only calls into.
  --- Each step is already wrapped, so a stub that answers nothing would only
  --- fill `status().warnings` with noise these cases are not about.
  ---@return table
  local function inert()
    return setmetatable({}, {
      __index = function()
        return function() end
      end,
    })
  end

  --- Stub the whole bootstrap so `setup()` is cheap and touches nothing
  --- global, then override the one module a case is about.
  ---@param overrides table<string, any>
  ---@return nil
  local function stub_bootstrap(overrides)
    for _, modname in ipairs({
      "lsp.core.handlers",
      "lsp.core.inlay_hints",
      "lsp.core.lightbulb",
      "lsp.core.supervisor",
      "lsp.formatter.conform",
      "lsp.usercmds",
      "lsp.usercmds.formatter",
      "lsp.usercmds.workspace_diagnostics",
      "lsp.completion.personal_names",
      "lsp.languages",
      "lsp.lspdoctor",
      "lsp.diagnostics",
      "lsp.tools.eslint_prettier",
      "lsp.tools.lsp_signature",
      "lsp.tools.ts_type_lookup",
      "lsp.tools.deprecated_help",
    }) do
      stub(modname, inert())
    end

    stub("lsp.integrations", {
      setup = function()
        return {}
      end,
      capability_contributors = function()
        return {}
      end,
      attach_hooks = function()
        return {}
      end,
      report = function()
        return {}
      end,
    })
    stub("lsp.bindings", {
      setup = function()
        return {}, false
      end,
    })
    stub("lsp.core.capabilities", {
      get = function()
        return { stubbed = true }, {}
      end,
    })
    stub("lsp.core.attach", {
      build = function()
        return {
          on_attach = function() end,
          on_init = function()
            return true
          end,
        }
      end,
    })
    stub("lsp.formatter", {
      build = function()
        return {
          format = function() end,
          enable = function() end,
          disable = function() end,
          toggle = function() end,
          is_enabled = function()
            return false
          end,
        }
      end,
    })
    -- Not inert: the Diagnostics section iterates `sources()`, so a stub that
    -- answers nil would make that section fail for a reason no case is about.
    stub("lsp.core.diagnostics", {
      apply = function() end,
      applied = function()
        return { virtual_text = true }
      end,
      sources = function()
        return { { name = "spec", spec = { virtual_text = true } } }
      end,
    })
    stub("lsp.core.registry", {
      setup_all = function()
        -- A name no `vim.lsp.config` entry answers to, so `vim.lsp.enable` on
        -- it cannot start anything in the test session.
        return { "spec_stub_server" }, {}
      end,
    })

    for modname, value in pairs(overrides) do
      stub(modname, value)
    end

    -- `lsp` itself last, and unloaded rather than replaced: its `_initialized`
    -- and `_warnings` are module locals, so a fresh copy is the only way to run
    -- `setup()` twice in one session.
    stub("lsp", nil)
  end

  before_each(function()
    saved.health = vim.health
    saved.get_clients = vim.lsp.get_clients
    saved_loaded = {}
    record_health()
  end)

  after_each(function()
    vim.health = saved.health
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.get_clients = saved.get_clients
    for modname, boxed in pairs(saved_loaded) do
      package.loaded[modname] = boxed[1]
    end
    package.loaded["lsp"] = nil
    package.loaded["lsp.health"] = nil
    package.loaded["lsp.config"] = nil
  end)

  describe("a bootstrap module that loads and then raises", function()
    -- Measured against HEAD, with `lsp.core.capabilities.get` replaced by a
    -- bare `error("boom")`: `require("lsp").setup({})` raised `boom` out to the
    -- caller, `status().initialized` stayed false and no server was set up --
    -- while the nine autocommands registered by the steps before it stayed
    -- registered. The fallback right below the call, written for exactly this,
    -- was unreachable: `pcall(require, …)` only covers the module that will not
    -- load, not the one that loads and then throws.
    it("falls back instead of aborting setup() when capabilities raise", function()
      stub_bootstrap({
        ["lsp.core.capabilities"] = {
          get = function()
            error("capabilities: boom", 0)
          end,
        },
      })

      local lsp = require("lsp")
      local ok = pcall(lsp.setup, {})

      assert.is_true(ok)
      local status = lsp.status()
      assert.is_true(status.initialized)

      local said = false
      for _, w in ipairs(status.warnings) do
        if w:find("capabilities: boom", 1, true) then
          said = true
        end
      end
      assert.is_true(said)
    end)

    -- Same shape, other end of the bootstrap: the registry is the step that
    -- decides whether `setup()` reports success at all.
    it("records the registry's own error instead of propagating it", function()
      stub_bootstrap({
        ["lsp.core.registry"] = {
          setup_all = function()
            error("registry: boom", 0)
          end,
        },
      })

      local lsp = require("lsp")
      local ok, result = pcall(lsp.setup, {})

      assert.is_true(ok)
      assert.is_false(result)
      assert.is_true(lsp.status().initialized)

      local said = false
      for _, w in ipairs(lsp.status().warnings) do
        if w:find("setup_all() failed: registry: boom", 1, true) then
          said = true
        end
      end
      assert.is_true(said)
    end)

    -- The half of the defect that only shows up in the report: a setup that
    -- aborts leaves `_initialized` false, so `:checkhealth lsp` tells you to
    -- run the setup that already ran and half-took effect.
    it("does not make :checkhealth claim setup() never ran", function()
      stub_bootstrap({
        ["lsp.core.attach"] = {
          build = function()
            error("attach: boom", 0)
          end,
        },
      })

      pcall(require("lsp").setup, {})

      package.loaded["lsp.health"] = nil
      require("lsp.health").check()

      assert.is_nil(find("setup() has not run"))
      assert.is_not_nil(find("setup() has run"))
    end)
  end)

  describe("the report's own blast radius", function()
    -- Measured against HEAD with one integration adapter whose `report()`
    -- throws: `check()` emitted 18 lines and stopped, and through
    -- `:checkhealth lsp` the Ecosystem section read "Failed to run healthcheck"
    -- with the Diagnostics and Per-buffer sections simply absent. 27 lines and
    -- every section now.
    it("keeps reporting after a section raises", function()
      stub_bootstrap({
        ["lsp.integrations"] = {
          setup = function()
            return {}
          end,
          capability_contributors = function()
            return {}
          end,
          attach_hooks = function()
            return {}
          end,
          report = function()
            error("adapter blew up", 0)
          end,
        },
      })
      require("lsp").setup({})

      package.loaded["lsp.health"] = nil
      local ok = pcall(require("lsp.health").check)

      assert.is_true(ok)
      local failed = find("this section failed")
      assert.is_not_nil(failed)
      assert.are.equal("error", failed.level)
      assert.is_truthy(failed.msg:find("adapter blew up", 1, true))

      -- The two sections that used to be lost.
      assert.is_not_nil(find("applied once, from lsp.core.diagnostics"))
      assert.is_not_nil(find(":LspDoctor covers the current buffer"))
    end)
  end)

  describe("a plugin that is installed but broken", function()
    ---@type string|nil
    local plugin_dir = nil

    after_each(function()
      if plugin_dir ~= nil then
        vim.opt.rtp:remove(plugin_dir)
        vim.fn.delete(plugin_dir, "rf")
        plugin_dir = nil
      end
    end)

    --- A module that is findable on the runtimepath and raises on load.
    ---@param modname string
    ---@return nil
    local function install_broken(modname)
      plugin_dir = vim.fn.tempname()
      vim.fn.mkdir(plugin_dir .. "/lua", "p")
      local path = ("%s/lua/%s.lua"):format(plugin_dir, modname)
      local fd = assert(io.open(path, "w"))
      fd:write(('error("%s: installed, but its own setup raised")\n'):format(modname))
      fd:close()
      vim.opt.rtp:prepend(plugin_dir)
    end

    -- `pcall(require, …)` answers false for "absent" and for "present and
    -- raised" alike, so the report told you to install something that was
    -- already installed. Measured: for a `lua/<name>.lua` that is a bare
    -- `error(…)`, `pcall(require, …)` is false while `vim.loader.find` returns
    -- one path against zero for a name that is nowhere.
    it("is not reported as not installed", function()
      install_broken("spec_broken_plugin")
      stub_bootstrap({
        ["lsp.bindings"] = {
          setup = function()
            return {
              { lhs = "<leader>xx", requires = "spec_broken_plugin" },
            },
              false
          end,
        },
      })
      require("lsp").setup({})

      package.loaded["lsp.health"] = nil
      require("lsp.health").check()

      assert.is_nil(find("which is not installed"))
      local entry = find("which is installed but failed to load")
      assert.is_not_nil(entry)
      assert.are.equal("warn", entry.level)
      assert.is_truthy(entry.advice[1]:find("Do not reinstall", 1, true))
    end)
  end)

  describe("the order of the keymap warnings", function()
    -- LuaJIT seeds its string hashes per process, so `pairs` over the
    -- plugin -> keys map handed the warnings out in a different order run to
    -- run. Measured on HEAD over three headless runs of the default preset,
    -- which is short exactly two plugins: "trouble, fzf-lua", then "fzf-lua,
    -- trouble", then "trouble, fzf-lua". Six names here rather than two: one
    -- run in 720 would come out sorted by luck, and a case that passes on
    -- broken code one time in 720 is not a case.
    it("is the same on every run, whatever pairs() feels like", function()
      ---@type string[]
      local wanted = {
        "spec_absent_alpha",
        "spec_absent_bravo",
        "spec_absent_charlie",
        "spec_absent_delta",
        "spec_absent_echo",
        "spec_absent_foxtrot",
      }
      ---@type LspNvim.KeymapSpec[]
      local keymaps = {}
      -- Bound in reverse, so insertion order cannot be mistaken for sorting.
      for i = #wanted, 1, -1 do
        keymaps[#keymaps + 1] = { lhs = "<leader>" .. i, requires = wanted[i] }
      end

      stub_bootstrap({
        ["lsp.bindings"] = {
          setup = function()
            return keymaps, false
          end,
        },
      })
      require("lsp").setup({})

      package.loaded["lsp.health"] = nil
      require("lsp.health").check()

      ---@type string[]
      local order = {}
      for _, entry in ipairs(emitted) do
        local plugin = entry.msg:match("keymap%(s%) bound for ([%w_%-%.]+),")
        if plugin then
          order[#order + 1] = plugin
        end
      end

      assert.are.same(wanted, order)
    end)
  end)

  describe("the buffer the report is about", function()
    --- A loaded, listed, named file buffer.
    ---@param name string
    ---@return integer
    local function file_buffer(name)
      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(bufnr, name)
      vim.fn.bufload(bufnr)
      return bufnr
    end

    -- The alternate buffer only survives the *first* `:checkhealth` of a
    -- session. Measured over three runs in one headless session with one file
    -- open: pass 1 read `bufnr("#") == 1` and reported "attached to real.lua:
    -- 1 of 1 running client(s) -- lua_ls"; passes 2 and 3 read `bufnr("#") ==
    -- -1`, because each run wipes the previous `health://` buffer, and reported
    -- "unknown -- no file buffer to report on" with the file still loaded and
    -- the client still on it. Reproduced here by an alternate that is not a
    -- file buffer, which is the same branch.
    it("survives a second :checkhealth in one session", function()
      local file = file_buffer("/repo/second_run.lua")
      local scratch = vim.api.nvim_create_buf(false, true)
      local report = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_name(report, "health://")

      -- Current is the report, alternate is the scratch: neither is a file.
      vim.api.nvim_set_current_buf(scratch)
      vim.api.nvim_set_current_buf(report)
      assert.are.equal(scratch, vim.fn.bufnr("#"))

      local client = { id = 7, name = "lua_ls", root_dir = "/repo", attached_buffers = {} }
      client.attached_buffers[file] = true

      stub_bootstrap({})
      require("lsp").setup({})
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.lsp.get_clients = function(filter)
        if filter ~= nil and filter.bufnr == file then
          return { client }
        elseif filter ~= nil and filter.bufnr ~= nil then
          return {}
        end
        return { client }
      end

      package.loaded["lsp.health"] = nil
      require("lsp.health").check()

      assert.is_nil(find("no file buffer to report on"))
      local entry = find("attached to second_run.lua")
      assert.is_not_nil(entry)
      -- Said out loud, because with two files opened a second apart `lastused`
      -- ties and the tie is broken by buffer number: it is a guess, deterministic
      -- or not.
      assert.is_truthy(entry.msg:find("last used file buffer", 1, true))
      assert.is_truthy(entry.msg:find("lua_ls", 1, true))
    end)
  end)
end)
