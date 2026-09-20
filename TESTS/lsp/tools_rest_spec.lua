--- The rest of `tools/`: the eslint/prettier pair and the deprecated-help
--- helper. Between them they own four user commands, a `BufWritePre` hook and
--- a diagnostics interceptor, and none of it had a spec.
---
--- Every case here is one that ran green in the shipped code by doing nothing
--- observable -- a toggle that toggled nothing, a config probe that answered
--- for the wrong tool, two formatters started in the same tick, a "set this
--- mapping once" guard that never matched. That is the shape a suite misses:
--- the failures are silent, and each needs a project on disk or a client
--- behaving a particular way before it says anything at all.

local uv = vim.uv or vim.loop

---@param files table<string, string>  # relative path -> contents
---@return string dir
local function project(files)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  for name, contents in pairs(files) do
    vim.fn.writefile(vim.split(contents, "\n", { plain = true }), dir .. "/" .. name)
  end
  return dir
end

describe("lsp.tools.eslint_prettier.core.check_config", function()
  local check

  before_each(function()
    package.loaded["lsp.tools.eslint_prettier.core.check_config"] = nil
    check = require("lsp.tools.eslint_prettier.core.check_config")
  end)

  -- `package.json` counted for *both* tools as soon as it held either key,
  -- because one substring search answered both questions. A project carrying
  -- nothing but `.prettierrc` and `{ "prettier": {} }` therefore ran
  -- `eslint_d` on every save; measured live, eslint_d's own answer was
  -- "Could not find config file."
  it("does not let one tool's package.json key answer for the other", function()
    local eslint_only = project({ ["package.json"] = '{ "name": "x", "eslintConfig": {} }' })
    assert.is_true(check.has_eslint(eslint_only))
    assert.is_false(check.has_prettier(eslint_only), "eslintConfig counted as a prettier config")

    local prettier_only = project({ ["package.json"] = '{ "name": "y", "prettier": {} }' })
    assert.is_true(check.has_prettier(prettier_only))
    assert.is_false(check.has_eslint(prettier_only), "a prettier key counted as an eslint config")
  end)

  -- The substring search could not tell a declaration from a dependency
  -- either: `"prettier": "^3.3.3"` under devDependencies is in almost every
  -- JS project, configured or not.
  it("does not count prettier appearing as a devDependency", function()
    local dir = project({
      ["package.json"] = '{ "name": "z", "devDependencies": { "prettier": "^3.3.3" } }',
    })
    assert.is_false(check.has_prettier(dir))
  end)

  -- Flat config has been ESLint's default since v9 and is all v10 reads. It
  -- was absent from the pattern list, so a project scaffolded any time in the
  -- last two years got "No eslint config found in project root; skipping".
  it("recognises flat eslint config", function()
    local dir = project({ ["eslint.config.js"] = "export default []" })
    assert.is_true(check.has_eslint(dir))
  end)

  it("answers false for an unnamed buffer's nil root", function()
    assert.is_false(check.has_eslint(nil))
    assert.is_false(check.has_prettier(nil))
  end)
end)

describe("lsp.tools.eslint_prettier", function()
  local dir, buf, spawned, pending

  ---@return table usercmds module, wired to a stubbed spawn
  local function reload_with_stubbed_spawn()
    spawned, pending = {}, {}
    package.loaded["lib.nvim.cross.uv.spawn_capture"] = function(argv, _opts, on_done)
      spawned[#spawned + 1] = argv[1]
      pending[#pending + 1] = on_done
    end
    for _, mod in ipairs({
      "lsp.tools.eslint_prettier.eslint.fix",
      "lsp.tools.eslint_prettier.prettier.format",
      "lsp.tools.eslint_prettier.usercmds",
      "lsp.tools.eslint_prettier.autocmds",
    }) do
      package.loaded[mod] = nil
    end
    require("lsp.tools.eslint_prettier.eslint").set_eslint_bin("ESLINT")
    require("lsp.tools.eslint_prettier.prettier").set_prettier_bin("PRETTIER")
    return require("lsp.tools.eslint_prettier.usercmds")
  end

  before_each(function()
    dir = project({
      ["package.json"] = '{ "name": "proj", "eslintConfig": {}, "prettier": {} }',
      ["a.ts"] = "const a = 1",
    })
    vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/a.ts"))
    buf = vim.api.nvim_get_current_buf()
  end)

  after_each(function()
    package.loaded["lib.nvim.cross.uv.spawn_capture"] = nil
    for _, mod in ipairs({
      "lsp.tools.eslint_prettier.eslint.fix",
      "lsp.tools.eslint_prettier.prettier.format",
      "lsp.tools.eslint_prettier.usercmds",
      "lsp.tools.eslint_prettier.autocmds",
    }) do
      package.loaded[mod] = nil
    end
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  -- Both tools rewrite the same path on disk. Started in one tick they race,
  -- and the slower one's write is the file's final state -- the other's work
  -- is simply gone. Measured with a 2 s eslint stub and an instant prettier
  -- one: prettier finished at ~0.1 s, eslint at ~2 s, and the file held
  -- `ESLINT_WROTE_THIS` alone. The command's own description says "then".
  it(":LintAndFormat starts prettier only after eslint has exited", function()
    local usercmds = reload_with_stubbed_spawn()
    usercmds.attach({})

    vim.cmd("LintAndFormat")
    assert.are.same({ "ESLINT" }, spawned, "prettier was started before eslint had exited")

    pending[1]({ code = 0, stdout = "", stderr = "" })
    assert.are.same({ "ESLINT", "PRETTIER" }, spawned, "prettier never ran after eslint")
  end)

  -- The same ordering on the save path, which is where it actually bites --
  -- and on `BufWritePost`, so the formatters never hold the file open while
  -- Neovim is still writing it. Measured on a 25.8 MB buffer against the
  -- `BufWritePre` version: `:w` took 233 ms, the formatter got to the path
  -- first and died with "Der Prozess kann nicht auf die Datei zugreifen, da
  -- sie von einem anderen Prozess verwendet wird", and the file was left
  -- unformatted.
  it("the save hook runs after the write, and prettier only after eslint", function()
    reload_with_stubbed_spawn()
    local autocmds = require("lsp.tools.eslint_prettier.autocmds")
    vim.bo[buf].filetype = "typescript"
    autocmds.attach({ _enabled = true, filetypes = { "typescript" } })

    vim.api.nvim_exec_autocmds("BufWritePre", { buffer = buf })
    assert.are.same({}, spawned, "a formatter was started while Neovim was still writing")

    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf })
    assert.are.same({ "ESLINT" }, spawned, "prettier was started before eslint had exited")

    pending[1]({ code = 0, stdout = "", stderr = "" })
    assert.are.same({ "ESLINT", "PRETTIER" }, spawned)
  end)

  -- `setup({ binaries = ... })` called `set_bins` on the fix/format modules.
  -- Neither has such a field, so the documented way to point the tool at a
  -- binary of your own raised "attempt to call field 'set_bins' (a nil value)"
  -- and took the rest of `setup` -- the user commands and the save hook --
  -- down with it.
  it("setup() accepts custom binary paths instead of raising", function()
    for _, mod in ipairs({
      "lsp.tools.eslint_prettier",
      "lsp.tools.eslint_prettier.eslint",
      "lsp.tools.eslint_prettier.prettier",
    }) do
      package.loaded[mod] = nil
    end
    local ep = require("lsp.tools.eslint_prettier")

    local ok, err = pcall(ep.setup, {
      binaries = { eslint = "C:/tools/eslint_d.cmd", prettier = "C:/tools/prettier.cmd" },
    })
    assert.is_true(ok, "setup raised: " .. tostring(err))
    assert.are.equal(
      "C:/tools/eslint_d.cmd",
      require("lsp.tools.eslint_prettier.eslint").get_eslint_bin()
    )
    assert.are.equal(
      "C:/tools/prettier.cmd",
      require("lsp.tools.eslint_prettier.prettier").get_prettier_bin()
    )
  end)

  -- `not not not not x` is `x`. The command reported a toggle and changed
  -- nothing: `_enabled` measured true before the call and true after two of
  -- them, while `doc/autorun.md` promises it flips the flag and then says
  -- which way it went.
  it(":ToggleLintFormatOnSave actually flips the flag", function()
    local usercmds = require("lsp.tools.eslint_prettier.usercmds")
    local ctx = { _enabled = true }
    usercmds.attach(ctx)

    vim.cmd("ToggleLintFormatOnSave")
    assert.is_false(ctx._enabled, "the toggle left autorun on")
    vim.cmd("ToggleLintFormatOnSave")
    assert.is_true(ctx._enabled)
  end)
end)

describe("lsp.tools.deprecated_help", function()
  local defaults

  before_each(function()
    for _, mod in ipairs({
      "lsp.tools.deprecated_help",
      "lsp.tools.deprecated_help.defaults",
      "lsp.tools.deprecated_help.helper",
      "lsp.tools.deprecated_help.lsp.lua_ls.lua_ls",
    }) do
      package.loaded[mod] = nil
    end
    defaults = require("lsp.tools.deprecated_help.defaults")
  end)

  -- `setup({ keymap = "<leader>lh" })` is the example in this module's own
  -- header and the only call the README shows. Nothing read it: the keymap
  -- reached `defaults` through `opts.lua_ls.keymap` and nowhere else, so the
  -- documented call measured `<leader>oh` afterwards, unchanged.
  it("honours the top-level `keymap` its own example passes", function()
    require("lsp.tools.deprecated_help").setup({ keymap = "<leader>lh" })
    assert.are.equal("<leader>lh", defaults.keymap)
  end)

  it("still lets an explicit lua_ls.keymap win", function()
    require("lsp.tools.deprecated_help").setup({
      keymap = "<leader>a",
      lua_ls = { keymap = "<leader>b" },
    })
    assert.are.equal("<leader>b", defaults.keymap)
  end)

  -- Neovim stores a mapping under the resolved key sequence: `<leader>oh`
  -- comes back out of `nvim_buf_get_keymap` as `\oh`. The guard compared
  -- against the notation it was handed, so it never matched and "once" was
  -- never once -- a user's own buffer-local `<leader>oh` was replaced without
  -- a word.
  it("set_buf_keymap_once leaves a mapping that is already there alone", function()
    local helper = require("lsp.tools.deprecated_help.helper")
    local b = vim.api.nvim_create_buf(false, true)
    vim.keymap.set("n", "<leader>oh", "<cmd>echo 1<cr>", { buffer = b, desc = "the user's own" })

    helper.set_buf_keymap_once(b, "<leader>oh", function() end, { desc = "deprecated_help's" })

    local maps = vim.api.nvim_buf_get_keymap(b, "n")
    assert.are.equal(1, #maps)
    assert.are.equal("the user's own", maps[1].desc, "the user's mapping was overwritten")
    vim.api.nvim_buf_delete(b, { force = true })
  end)

  -- `defaults.keymap` is documented as opening help for the *last* detected
  -- symbol. It used to get that only as a side effect of the broken guard
  -- re-setting the mapping on every diagnostic; with the guard fixed the
  -- mapping is installed once, so the symbol has to be looked up at press
  -- time rather than captured in the closure.
  it("the mapping opens the last deprecated symbol, not the first", function()
    local file = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "vim.tbl_add_reverse_lookup(t)", "vim.lsp.buf_get_clients()" }, file)
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    local buf = vim.api.nvim_get_current_buf()

    require("lsp.tools.deprecated_help").setup()
    local lua_ls = require("lsp.tools.deprecated_help.lsp.lua_ls.lua_ls")
    local opened = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    lua_ls.show_help = function(_, symbol)
      opened[#opened + 1] = symbol
    end

    local dispatch
    local client_id = vim.lsp.start({
      name = "lua_ls",
      cmd = function(dispatchers)
        dispatch = dispatchers
        return {
          request = function(method, _, cb)
            if cb then
              cb(nil, method == "initialize" and { capabilities = {} } or {})
            end
            return true, 1
          end,
          notify = function()
            return true
          end,
          is_closing = function()
            return false
          end,
          terminate = function() end,
        }
      end,
      -- A fresh client per case: `vim.lsp.start` reuses one whose config
      -- matches, and a reused client never calls `cmd` again -- the second
      -- case would get no `dispatchers` at all.
    }, {
      bufnr = buf,
      reuse_client = function()
        return false
      end,
    })

    ---@param line integer
    ---@param to integer
    ---@param msg string
    local function diag(line, to, msg)
      return {
        range = {
          start = { line = line, character = 4 },
          ["end"] = { line = line, character = to },
        },
        severity = vim.diagnostic.severity.WARN,
        message = msg,
      }
    end

    dispatch.notification("textDocument/publishDiagnostics", {
      uri = vim.uri_from_bufnr(buf),
      diagnostics = {
        diag(0, 26, "Field `tbl_add_reverse_lookup` is deprecated."),
        diag(1, 23, "Field `buf_get_clients` is deprecated."),
      },
    })
    vim.wait(200, function()
      return false
    end)

    local maps = vim.api.nvim_buf_get_keymap(buf, "n")
    local rhs
    for _, m in ipairs(maps) do
      if m.lhs == vim.api.nvim_replace_termcodes(defaults.keymap, true, true, true) then
        rhs = m.callback
      end
    end
    assert.is_function(rhs, "no mapping was installed for a deprecated symbol")
    rhs()
    -- `lsp.buf_get_clients`, not `buf_get_clients`: the symbol is the text the
    -- diagnostic range covers, minus the blacklisted `vim.api.`/`vim.fn.`/
    -- `vim.uv.` prefixes, and `vim.lsp.` is not one of them.
    assert.are.same({ "lsp.buf_get_clients" }, opened, "the mapping froze on the first symbol")

    local c = vim.lsp.get_client_by_id(client_id)
    if c then
      c:stop(true)
    end
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  -- The interceptor is two stacked wrappers around
  -- `textDocument/publishDiagnostics`, which is exactly the arrangement that
  -- fails silently when it is wrong. It is not: the diagnostic still reaches
  -- `vim.diagnostic`, unmodified.
  it("does not swallow the diagnostics it intercepts", function()
    local file = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "vim.tbl_add_reverse_lookup(t)" }, file)
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    local buf = vim.api.nvim_get_current_buf()

    require("lsp.tools.deprecated_help").setup()

    local dispatch
    local client_id = vim.lsp.start({
      name = "lua_ls",
      cmd = function(dispatchers)
        dispatch = dispatchers
        return {
          request = function(method, _, cb)
            if cb then
              cb(nil, method == "initialize" and { capabilities = {} } or {})
            end
            return true, 1
          end,
          notify = function()
            return true
          end,
          is_closing = function()
            return false
          end,
          terminate = function() end,
        }
      end,
      -- A fresh client per case: `vim.lsp.start` reuses one whose config
      -- matches, and a reused client never calls `cmd` again -- the second
      -- case would get no `dispatchers` at all.
    }, {
      bufnr = buf,
      reuse_client = function()
        return false
      end,
    })

    dispatch.notification("textDocument/publishDiagnostics", {
      uri = vim.uri_from_bufnr(buf),
      diagnostics = {
        {
          range = { start = { line = 0, character = 4 }, ["end"] = { line = 0, character = 26 } },
          severity = vim.diagnostic.severity.WARN,
          message = "Field `tbl_add_reverse_lookup` is deprecated.",
        },
      },
    })
    vim.wait(200, function()
      return false
    end)

    local got = vim.diagnostic.get(buf)
    assert.are.equal(1, #got)
    assert.are.equal("Field `tbl_add_reverse_lookup` is deprecated.", got[1].message)

    local c = vim.lsp.get_client_by_id(client_id)
    if c then
      c:stop(true)
    end
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  -- `buf_symbol_cache` was a plain per-bufnr table cleared by no event: a
  -- buffer's entry (and whatever `set_buf_keymap_once` had already keyed to
  -- it) stayed alive for the rest of the session even after the buffer was
  -- deleted, growing by one entry per buffer ever visited (PERF-53).
  it("drops a buffer's cached symbols once the buffer is deleted", function()
    local helper = require("lsp.tools.deprecated_help.helper")
    local b = vim.api.nvim_create_buf(false, true)

    helper.ensure_buf_cache(b)
    assert.is_not_nil(helper.buf_symbol_cache[b])

    vim.api.nvim_buf_delete(b, { force = true })

    assert.is_nil(helper.buf_symbol_cache[b])
  end)
end)

describe("lsp.tools -- the commands, run", function()
  -- Nothing here raises on an empty unnamed buffer with no client attached,
  -- which is the state every one of these commands is reachable in. Kept as a
  -- case because it is the shape of failure this plugin keeps producing, and
  -- because `uv` is referenced so the timing note above stays honest.
  it("every registered command survives an empty buffer and no client", function()
    require("lsp.tools.eslint_prettier").setup({})
    require("lsp.tools.ts_type_lookup.symbol_picker").attach()
    require("lsp.tools.ts_type_lookup.noice_integration")
    require("lsp.tools.deprecated_help").setup()

    vim.cmd("enew")
    local t0 = uv.hrtime()
    for _, name in ipairs({
      "EslintFix",
      "PrettierFormat",
      "LintAndFormat",
      "ToggleLintFormatOnSave",
      "TypeDefPick",
      "TypeDefAttachNoiceKeys",
    }) do
      local ok, err = pcall(vim.cmd, name)
      assert.is_true(ok, ":" .. name .. " raised: " .. tostring(err))
    end
    -- None of them may block: every one of these paths is either a guard that
    -- returns or an async spawn. Measured at well under 100 ms for all six.
    assert.is_true((uv.hrtime() - t0) / 1e6 < 2000, "a command blocked the editor")
  end)
end)
