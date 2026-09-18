--- Covers the per-language QoL layer, `lsp/languages/**`: the FileType
--- autocommands, the per-language keymaps and the Astro user commands.
---
--- Every case here is a defect that was measured on a real Neovim before it
--- was fixed, and the measurement is quoted at the case. The two that this
--- file does NOT cover are covered elsewhere on purpose:
--- `organize_imports_spec.lua` owns the "organize-imports on save must be
--- synchronous" contract, and `astro_autotag_spec.lua` owns the autotag
--- probe. This file is about the layer around them.

---@param names string[]
local function unload(names)
  for _, n in ipairs(names) do
    package.loaded[n] = nil
  end
end

--- A listed, loaded scratch buffer in the current window, wiped afterwards.
---@param fn fun(bufnr: integer): nil
---@param lines string[]|nil
local function with_window_buffer(lines, fn)
  local prev = vim.api.nvim_get_current_buf()
  local bufnr = vim.api.nvim_create_buf(true, false)
  if lines then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end
  vim.api.nvim_win_set_buf(0, bufnr)
  local ok, err = pcall(fn, bufnr)
  pcall(vim.api.nvim_win_set_buf, 0, prev)
  pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  assert(ok, err)
end

--- The `lhs` of the buffer-local mapping carrying `desc`, so a case never has
--- to guess what `<leader>` expands to in the host's config.
---@param bufnr integer
---@param mode string
---@param desc string
---@return string
local function lhs_by_desc(bufnr, mode, desc)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, mode)) do
    if m.desc == desc then
      return m.lhs
    end
  end
  error(("no %s-mode mapping described %q on buffer %d"):format(mode, desc, bufnr))
end

---@param keys string
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

-- ===========================================================================
-- Entry point
-- ===========================================================================

--- First in the file on purpose: `vim.filetype.add` is global and permanent
--- for the session, so the "before" half of the `wat` case only means anything
--- while nothing has called `enable_all()` yet.
describe("lsp.languages.enable_all", function()
  -- `vim.filetype.add({ extension = { wat = "wasm" } })` overrode Neovim's own
  -- detection. Neovim answers `wat` for `*.wat` and ships `syntax/wat.vim`,
  -- `ftplugin/wat.vim` and `indent/wat.vim` for it; it ships nothing for
  -- `wasm`. Measured on Neovim 0.12.2: `vim.filetype.match` answered "wat"
  -- before `enable_all()` and "wasm" after it -- this plugin moved the
  -- WebAssembly text format to a filetype with no syntax, no ftplugin and no
  -- indent, and gained nothing for it.
  it("leaves Neovim's own `wat` filetype alone", function()
    assert.are.equal("wat", vim.filetype.match({ filename = "/tmp/probe.wat" }))
    assert.is_truthy(vim.api.nvim_get_runtime_file("syntax/wat.vim", false)[1])
    assert.are.same({}, vim.api.nvim_get_runtime_file("syntax/wasm.vim", true))

    require("lsp.languages").enable_all()

    assert.are.equal("wat", vim.filetype.match({ filename = "/tmp/probe.wat" }))
    -- The binary form has no native detection, so that half of the table is
    -- still worth having.
    assert.are.equal("wasm", vim.filetype.match({ filename = "/tmp/probe.wasm" }))
  end)

  -- A standing guard rather than a fix: `enable_all()` was already idempotent
  -- when this was written (every module clears its own augroup), and it is
  -- cheap to keep it that way. A groupless FileType autocmd has nothing to
  -- overwrite, so N reloads would mean N handlers per event.
  it("registers the same autocommands however often it runs", function()
    ---@return table<string, integer>
    local function census()
      local out = {}
      for _, a in ipairs(vim.api.nvim_get_autocmds({ event = { "FileType", "BufWritePre" } })) do
        local group = a.group_name or ""
        if group:match("^Lang") or group:match("^Astro") then
          local key = ("%s/%s/%s"):format(group, a.event, tostring(a.pattern))
          out[key] = (out[key] or 0) + 1
        end
      end
      return out
    end

    local langs = require("lsp.languages")
    langs.enable_all()
    local first = census()
    langs.enable_all()
    langs.enable_all()

    assert.is_true(vim.tbl_count(first) > 0, "nothing registered at all")
    assert.are.same(first, census())
  end)
end)

-- ===========================================================================
-- app/java.lua
-- ===========================================================================

describe("lsp.languages.app.java", function()
  local saved_util

  before_each(function()
    saved_util = package.loaded["lsp.core.util"]
  end)

  after_each(function()
    package.loaded["lsp.core.util"] = saved_util
    unload({ "lsp.languages.app.java" })
    pcall(vim.api.nvim_del_augroup_by_name, "LangJava")
  end)

  --- Stub `lsp.core.util` and hand back a freshly required java module.
  ---
  --- The unload is load-bearing: the module captures `lsp.core.util` in an
  --- upvalue at require time, so a java module still cached from an earlier
  --- `enable_all()` keeps calling the real helper and the spy never sees a
  --- thing.
  ---@return table calls
  local function stub_util()
    unload({ "lsp.languages.app.java" })
    local calls = {}
    package.loaded["lsp.core.util"] = {
      organize_imports_sync = function(bufnr, kind)
        calls[#calls + 1] = { bufnr = bufnr, kind = kind }
        return true
      end,
    }
    return calls
  end

  --- How many buffer-local autocmds this buffer carries for `event`. Counted
  --- through `buflocal` rather than by group, because the handler under test
  --- used to have no group at all.
  ---@param bufnr integer
  ---@param event string
  ---@return integer
  local function buflocal_count(bufnr, event)
    local n = 0
    for _, a in ipairs(vim.api.nvim_get_autocmds({ event = event, buffer = bufnr })) do
      if a.buflocal then
        n = n + 1
      end
    end
    return n
  end

  -- The organize-on-save autocmd was created *inside* the FileType callback,
  -- buffer-local and in no group -- so it had nothing to overwrite, and
  -- FileType fires again on every re-read of the file. Measured on one
  -- Probe.java: the opening `:edit` plus two `:edit!` left 3 buffer-local
  -- BufWritePre handlers and a single `:w` made 3 organize-imports round
  -- trips, each a blocking `textDocument/codeAction` of up to a second,
  -- applying the same edit three times over.
  it("hooks organize-imports once per buffer, not once per FileType", function()
    local calls = stub_util()
    local java = require("lsp.languages.app.java")
    java.enable()

    with_window_buffer({ "class Probe {}" }, function(bufnr)
      for _ = 1, 3 do
        vim.bo[bufnr].filetype = "text"
        vim.bo[bufnr].filetype = "java"
      end

      assert.are.equal(1, buflocal_count(bufnr, "BufWritePre"))

      vim.api.nvim_exec_autocmds("BufWritePre", { buffer = bufnr })
      assert.are.equal(1, #calls, "one :w ran organize-imports more than once")
      assert.are.equal(bufnr, calls[1].bufnr)
      assert.are.equal("source.organizeImports", calls[1].kind)
    end)
  end)

  -- The other half of "no group": `enable()` clears `LangJava`, which could
  -- not touch a groupless autocmd. Three `enable()` runs over a buffer that
  -- keeps its filetype used to leave three handlers behind.
  it("does not leave handlers behind when enable() runs again", function()
    stub_util()
    local java = require("lsp.languages.app.java")

    with_window_buffer({ "class Probe {}" }, function(bufnr)
      for _ = 1, 3 do
        java.enable()
        vim.bo[bufnr].filetype = "text"
        vim.bo[bufnr].filetype = "java"
      end

      assert.are.equal(1, buflocal_count(bufnr, "BufWritePre"))
    end)
  end)

  it("still sets the 4-space Java indent on FileType", function()
    stub_util()
    require("lsp.languages.app.java").enable()

    with_window_buffer({ "class Probe {}" }, function(bufnr)
      vim.bo[bufnr].filetype = "java"
      assert.are.equal(4, vim.bo[bufnr].shiftwidth)
      assert.are.equal(4, vim.bo[bufnr].tabstop)
      assert.is_true(vim.bo[bufnr].expandtab)
    end)
  end)
end)

-- ===========================================================================
-- app/dart
-- ===========================================================================

describe("lsp.languages.app.dart", function()
  local starting_cwd

  before_each(function()
    starting_cwd = vim.fn.getcwd()
    unload({ "lsp.languages.app.dart" })
  end)

  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, "LangDart")
    vim.fn.chdir(starting_cwd)
  end)

  ---@param calls table[]
  ---@return nil
  local function stub_jobstart(calls)
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.jobstart = function(cmd, opts)
      calls[#calls + 1] = { cmd = cmd, opts = opts }
      return 1
    end
  end

  --- A Flutter-shaped project (a `pubspec.yaml`) in one temp directory, and
  --- Neovim's own cwd left in a *different*, unrelated one -- the ordinary
  --- shape of "opened a file from a picker without `autochdir`".
  ---@return string project_dir, integer bufnr
  local function flutter_project_buffer()
    local project = vim.fs.normalize(vim.fn.tempname())
    vim.fn.mkdir(project .. "/lib", "p")
    vim.fn.writefile({ "name: my_app" }, project .. "/pubspec.yaml")
    vim.fn.writefile({ "void main() {}" }, project .. "/lib/main.dart")

    local unrelated = vim.fs.normalize(vim.fn.tempname())
    vim.fn.mkdir(unrelated, "p")
    vim.fn.chdir(unrelated)

    local bufnr = vim.fn.bufadd(project .. "/lib/main.dart")
    vim.fn.bufload(bufnr)
    return project, bufnr
  end

  it("still sets the 2-space Dart indent on FileType", function()
    require("lsp.languages.app.dart").enable()

    with_window_buffer({ "void main() {}" }, function(bufnr)
      vim.bo[bufnr].filetype = "dart"
      assert.are.equal(2, vim.bo[bufnr].shiftwidth)
      assert.are.equal(2, vim.bo[bufnr].tabstop)
      assert.is_true(vim.bo[bufnr].expandtab)
    end)
  end)

  -- `<leader>fr` ran `vim.cmd("!flutter run --hot-reload")`. `--hot-reload` is
  -- not a real `flutter run` flag -- measured against a real `flutter`
  -- install: `flutter run --hot-reload` answers 'Could not find an option
  -- named "--hot-reload".' and exits immediately, so the binding never once
  -- did what its own `desc` claimed. `--hot` is on by default, so the fix
  -- asks for nothing extra.
  it("runs a real flutter command, with no invented flag", function()
    local orig_jobstart = vim.fn.jobstart
    local calls = {}
    stub_jobstart(calls)

    local dart = require("lsp.languages.app.dart")
    dart.enable()
    with_window_buffer({ "void main() {}" }, function(bufnr)
      vim.bo[bufnr].filetype = "dart"
      local lhs = lhs_by_desc(bufnr, "n", "Flutter: run (or focus)")
      feed(lhs)
      vim.wait(50)
    end)

    vim.fn.jobstart = orig_jobstart
    assert.are.equal(1, #calls)
    assert.are.equal("flutter run", calls[1].cmd)
    assert.is_true(calls[1].opts.term, "not run in a terminal buffer")
  end)

  -- Even with the flag fixed, `:!` is synchronous and `flutter run` never
  -- finishes on its own -- it is an interactive dev server, not a one-shot
  -- command, so the corrected command would still have frozen Neovim for as
  -- long as the app stayed up. Asserted directly against the internal
  -- function so this cannot regress back to a `vim.cmd("!...")` call, which
  -- would block this very test.
  it("does not block: opens a terminal job rather than a synchronous shell-out", function()
    local orig_jobstart = vim.fn.jobstart
    local calls = {}
    stub_jobstart(calls)

    require("lsp.languages.app.dart")._run_or_focus()

    vim.fn.jobstart = orig_jobstart
    assert.are.equal(1, #calls, "flutter run was not launched as a job")
  end)

  -- `jobstart()`'s own docs: "cwd: (string, default=|current-directory|)" --
  -- Neovim's *global* cwd, not the directory of the buffer that triggered the
  -- keybinding. Nothing here keeps those in sync, so a `.dart` file opened
  -- from anywhere else launched `flutter run` whichever directory Neovim
  -- happened to be sitting in -- at best "No pubspec.yaml file found", at
  -- worst a *different* Flutter project that happens to have one.
  it("runs from the Dart project's own root, not Neovim's cwd", function()
    local orig_jobstart = vim.fn.jobstart
    local calls = {}
    stub_jobstart(calls)

    local project, bufnr = flutter_project_buffer()
    vim.api.nvim_set_current_buf(bufnr)
    require("lsp.languages.app.dart")._run_or_focus()

    vim.fn.jobstart = orig_jobstart
    assert.are.equal(1, #calls)
    assert.are.equal(project, calls[1].opts.cwd)
    assert.are_not.equal(
      vim.fn.getcwd(),
      calls[1].opts.cwd,
      "resolved to Neovim's cwd instead of the project's"
    )
  end)

  it("falls back to the file's own directory when no project marker exists", function()
    local orig_jobstart = vim.fn.jobstart
    local calls = {}
    stub_jobstart(calls)

    local lone_dir = vim.fs.normalize(vim.fn.tempname())
    vim.fn.mkdir(lone_dir, "p")
    vim.fn.writefile({ "void main() {}" }, lone_dir .. "/scratch.dart")
    local bufnr = vim.fn.bufadd(lone_dir .. "/scratch.dart")
    vim.fn.bufload(bufnr)
    vim.api.nvim_set_current_buf(bufnr)

    require("lsp.languages.app.dart")._run_or_focus()

    vim.fn.jobstart = orig_jobstart
    assert.are.equal(lone_dir, calls[1].opts.cwd)
  end)

  it("falls back to getcwd() rather than raising on an unnamed buffer", function()
    local orig_jobstart = vim.fn.jobstart
    local calls = {}
    stub_jobstart(calls)

    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(scratch)

    assert.has_no.errors(function()
      require("lsp.languages.app.dart")._run_or_focus()
    end)

    vim.fn.jobstart = orig_jobstart
    assert.are.equal(vim.fn.getcwd(), calls[1].opts.cwd)
  end)

  it("focuses the running instance instead of launching a second one", function()
    local orig_jobstart = vim.fn.jobstart
    local calls = {}
    stub_jobstart(calls)

    local dart = require("lsp.languages.app.dart")
    dart._run_or_focus()
    local first_buf = vim.api.nvim_get_current_buf()
    local wins_before = #vim.api.nvim_list_wins()

    vim.cmd("wincmd p")
    dart._run_or_focus()

    vim.fn.jobstart = orig_jobstart
    assert.are.equal(1, #calls, "a second press launched flutter run again")
    assert.are.equal(first_buf, vim.api.nvim_get_current_buf())
    assert.are.equal(wins_before, #vim.api.nvim_list_wins())
  end)
end)

-- ===========================================================================
-- webdev/astro
-- ===========================================================================

describe("lsp.languages.webdev.astro", function()
  local saved = {}
  local cwd
  local notes = {}
  local submitted

  before_each(function()
    notes = {}
    cwd = vim.fn.getcwd()
    saved.notify = vim.notify
    saved.autotag = package.loaded["lsp.servers.webdev.astro.autotag"]
    saved.kit = package.loaded["ui.kit"]
    saved.telescope = package.loaded["telescope.builtin"]
    saved.conform = package.loaded["conform"]

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg)
      notes[#notes + 1] = tostring(msg)
    end
    -- Answering "yes" keeps the hand-rolled autoclose fallback out of the way;
    -- what it does is astro_autotag_spec.lua's business, not this file's.
    package.loaded["lsp.servers.webdev.astro.autotag"] = {
      available = function()
        return true
      end,
      setup_manual_autoclose = function() end,
    }
    package.loaded["ui.kit"] = {
      input = function(opts)
        opts.on_submit(submitted)
      end,
    }
    package.loaded["telescope.builtin"] = {
      find_files = function() end,
      live_grep = function() end,
    }
    package.loaded["conform"] = {
      format = function() end,
    }
  end)

  after_each(function()
    vim.notify = saved.notify
    package.loaded["lsp.servers.webdev.astro.autotag"] = saved.autotag
    package.loaded["ui.kit"] = saved.kit
    package.loaded["telescope.builtin"] = saved.telescope
    package.loaded["conform"] = saved.conform
    unload({
      "lsp.languages.webdev.astro",
      "lsp.languages.webdev.astro.keymaps",
      "lsp.languages.webdev.astro.usercmds",
      "lsp.languages.webdev.astro.autocmds",
    })
    vim.fn.chdir(cwd)
  end)

  ---@return string dir
  local function scratch_project()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.fn.chdir(dir)
    return dir
  end

  ---@param bufnr integer
  ---@param lines string[]
  local function make_astro(bufnr, lines)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].filetype = "astro"
  end

  -- `<leader>ax` read `'<` and `'>`. Those marks are written when Visual mode
  -- is LEFT, and a mapping invoked from Visual mode runs while it is still
  -- active -- measured on a fresh `Vj` over lines 4-5, both read 0. So
  -- `getline(0, 0)` returned nothing, the component file was written with an
  -- empty body, `deletebufline(bufnr, 0, 0)` removed nothing, no `<Name />`
  -- was inserted, and the user was told "Created component:" regardless.
  it("extracts the selection that is actually selected", function()
    local dir = scratch_project()
    vim.fn.mkdir(dir .. "/src/components", "p")
    submitted = "Extracted"
    require("lsp.languages.webdev.astro").enable()

    with_window_buffer({ "---", "---", "", "<p>one</p>", "<p>two</p>" }, function(bufnr)
      make_astro(bufnr, { "---", "---", "", "<p>one</p>", "<p>two</p>" })
      local lhs = lhs_by_desc(bufnr, "v", "Extract to component")

      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      feed("Vj" .. lhs)

      assert.are.same({
        "---",
        "---",
        "",
        "<p>one</p>",
        "<p>two</p>",
      }, vim.fn.readfile(dir .. "/src/components/Extracted.astro"))
      assert.are.same(
        { "---", "---", "", "<Extracted />" },
        vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      )
    end)
  end)

  -- `vim.fn.writefile` creates no directories, and the notification the
  -- usercmd wrapper turns the failure into is the only trace. Measured in a
  -- project with no `src/` tree: "E482: Can't open file
  -- src/components/Widget.astro for writing: no such file or directory" --
  -- from the command whose whole job is to create that file.
  it("creates the directories its scaffolding needs", function()
    local dir = scratch_project()
    require("lsp.languages.webdev.astro").enable()

    vim.cmd("AstroNewComponent Widget")
    assert.are.equal(1, vim.fn.filereadable(dir .. "/src/components/Widget.astro"))

    -- And a nested name, which failed even with `src/components` present.
    vim.cmd("AstroNewComponent ui/Button")
    assert.are.equal(1, vim.fn.filereadable(dir .. "/src/components/ui/Button.astro"))

    vim.cmd("AstroNewPage about")
    assert.are.equal(1, vim.fn.filereadable(dir .. "/src/pages/about.astro"))

    for _, note in ipairs(notes) do
      assert.is_nil(note:match("E482"), "scaffolding still failed: " .. note)
    end
  end)

  -- `<leader>an` seeded its "nearest boundary" with the line count and then
  -- required `next_line < total`, so a boundary sitting ON the last line lost
  -- to the seed and the cursor wrapped to line 1 instead of moving to it.
  -- Measured on this four-line buffer: the mapping left the cursor on 1.
  it("jumps to a section boundary on the last line", function()
    scratch_project()
    require("lsp.languages.webdev.astro").enable()

    with_window_buffer(nil, function(bufnr)
      make_astro(bufnr, { "<div>", "  hi", "</div>", "<style>h1{}</style>" })
      local lhs = lhs_by_desc(bufnr, "n", "Next Astro section")

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      feed(lhs)

      assert.are.equal(4, vim.fn.line("."))
    end)
  end)

  -- `res.stdout or res.stderr` never reached stderr: `vim.system` returns ""
  -- for an empty stream, and "" is truthy in Lua. A failing build showed an
  -- empty INFO notification and swallowed the reason. The missing-binary guard
  -- is the other half: `vim.system` raises rather than returning a non-zero
  -- code, so without it `:AstroBuild` reported
  -- "vim/_core/system.lua:324: ENOENT ... (cmd): 'astro'".
  it("reports what a failed `astro build` wrote to stderr", function()
    scratch_project()
    local real_system, real_executable = vim.system, vim.fn.executable
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.executable = function(name)
      return name == "astro" and 1 or real_executable(name)
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function()
      return {
        wait = function()
          return { code = 1, stdout = "", stderr = "Could not resolve @/layouts/Layout.astro" }
        end,
      }
    end

    local ok, err = pcall(function()
      require("lsp.languages.webdev.astro").enable()
      vim.cmd("AstroBuild")
    end)

    vim.system = real_system
    vim.fn.executable = real_executable
    assert(ok, err)

    assert.is_truthy(
      table.concat(notes, "\n"):match("Could not resolve"),
      "stderr never surfaced: " .. vim.inspect(notes)
    )
  end)

  it("warns instead of raising when astro is not on PATH", function()
    scratch_project()
    local real_executable = vim.fn.executable
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.executable = function(name)
      return name == "astro" and 0 or real_executable(name)
    end

    local ok, err = pcall(function()
      require("lsp.languages.webdev.astro").enable()
      vim.cmd("AstroBuild")
    end)

    vim.fn.executable = real_executable
    assert(ok, err)

    local all = table.concat(notes, "\n")
    assert.is_truthy(all:match("astro not found"), vim.inspect(notes))
    assert.is_nil(all:match("ENOENT"), "the raw libuv error still reached the user")
  end)

  -- The FileType handler runs on every Astro buffer; a raise there is a file
  -- that will not open cleanly. The wrong filetype must be left untouched.
  it("sets Astro buffer options without raising, and only on astro buffers", function()
    scratch_project()
    require("lsp.languages.webdev.astro").enable()

    with_window_buffer(nil, function(bufnr)
      make_astro(bufnr, { "---", "---", "<h1>hi</h1>" })
      assert.are.equal("{/* %s */}", vim.bo[bufnr].commentstring)
      assert.are.equal(2, vim.bo[bufnr].shiftwidth)
      assert.are.equal(2, vim.bo[bufnr].tabstop)
      assert.is_true(vim.bo[bufnr].expandtab)
      assert.are.same({}, notes)
    end)

    with_window_buffer({ "plain" }, function(bufnr)
      vim.bo[bufnr].filetype = "text"
      assert.are.equal(
        0,
        #vim.api.nvim_buf_get_keymap(bufnr, "n"),
        "astro keymaps landed on a non-astro buffer"
      )
      assert.are.same({}, notes)
    end)
  end)
end)

-- ===========================================================================
-- documentation/markdown.lua
-- ===========================================================================

describe("lsp.languages.documentation.markdown", function()
  local saved_notify

  before_each(function()
    saved_notify = vim.notify
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function() end
  end)

  after_each(function()
    vim.notify = saved_notify
    unload({ "lsp.languages.documentation.markdown" })
    pcall(vim.api.nvim_del_augroup_by_name, "LangMarkdownQoL")
  end)

  -- `setup_reference_hl()` writes global highlight groups (namespace 0) and
  -- used to be called from the FileType callback, so every markdown buffer
  -- restyled LSP references for the whole session. Measured: opening three
  -- markdown buffers made 9 `nvim_set_hl` calls, and a colourscheme's
  -- `LspReferenceText = { fg = "#123456" }` came back as
  -- `{ fg = #FFFFFF, bg = #2b2b2b, italic = true }`.
  it("defines the reference highlights once, not once per markdown buffer", function()
    local md = require("lsp.languages.documentation.markdown")
    md.enable()

    -- What enable() promises: the groups exist.
    assert.are.equal(0xFFFFFF, vim.api.nvim_get_hl(0, { name = "LspReferenceText" }).fg)

    -- What a colourscheme loaded afterwards would set.
    vim.api.nvim_set_hl(0, "LspReferenceText", { fg = "#123456" })

    for _ = 1, 3 do
      with_window_buffer({ "# Title" }, function(bufnr)
        vim.bo[bufnr].filetype = "markdown"
      end)
    end

    assert.are.same(
      { fg = 0x123456 },
      vim.api.nvim_get_hl(0, { name = "LspReferenceText" }),
      "opening a markdown buffer restyled the groups for every buffer in the session"
    )
  end)

  it("still applies the markdown buffer options and format keymap", function()
    require("lsp.languages.documentation.markdown").enable()

    with_window_buffer({ "# Title" }, function(bufnr)
      vim.bo[bufnr].filetype = "markdown"
      assert.are.equal(0, vim.bo[bufnr].textwidth)
      assert.are.equal("jnql", vim.bo[bufnr].formatoptions)
      assert.is_truthy(lhs_by_desc(bufnr, "n", "[lsp] Format markdown buffer"))
    end)
  end)
end)

-- ===========================================================================
-- The stub modules
-- ===========================================================================

--- `app/csharp`, `scripting/lua`, `systems/{c,go,zig}` all document their
--- FileType callback as a no-op that only registers the group. Worth checking
--- that it is still true, and that the registration is one autocmd rather than
--- something that grows.
describe("the no-op language stubs", function()
  local cases = {
    { module = "lsp.languages.app.csharp", group = "LangCs", fts = { "cs" } },
    { module = "lsp.languages.scripting.lua", group = "LangLua", fts = { "lua" } },
    { module = "lsp.languages.systems.c", group = "LangC", fts = { "c", "cpp" } },
    { module = "lsp.languages.systems.go", group = "LangGo", fts = { "go" } },
    { module = "lsp.languages.systems.zig", group = "LangZig", fts = { "zig" } },
  }

  for _, case in ipairs(cases) do
    it(case.module .. " registers one handler per filetype and changes nothing", function()
      local mod = require(case.module)
      mod.enable()
      mod.enable()

      local registered = vim.api.nvim_get_autocmds({ event = "FileType", group = case.group })
      assert.are.equal(#case.fts, #registered)

      -- Only this group's handlers are fired, never `:setfiletype`: setting
      -- the filetype for real would also run Neovim's own ftplugin, which does
      -- change options (go sets `shiftwidth` to 8, zig to 4) and would be
      -- measuring the runtime rather than this module.
      for _, ft in ipairs(case.fts) do
        with_window_buffer({ "x" }, function(bufnr)
          ---@return table
          local function snapshot()
            return {
              shiftwidth = vim.bo[bufnr].shiftwidth,
              tabstop = vim.bo[bufnr].tabstop,
              expandtab = vim.bo[bufnr].expandtab,
              commentstring = vim.bo[bufnr].commentstring,
              formatoptions = vim.bo[bufnr].formatoptions,
              keymaps = #vim.api.nvim_buf_get_keymap(bufnr, "n"),
              autocmds = #vim.api.nvim_get_autocmds({ event = "BufWritePre", buffer = bufnr }),
            }
          end

          local before = snapshot()
          vim.api.nvim_exec_autocmds("FileType", { group = case.group, pattern = ft })
          assert.are.same(before, snapshot())
        end)
      end
    end)
  end
end)
