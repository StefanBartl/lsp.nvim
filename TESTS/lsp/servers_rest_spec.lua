--- Regression cases for the per-server modules under `lua/lsp/servers/` that
--- have no spec of their own (`lua_ls/`, `bashls`, `marksman`'s diagnostics
--- handler and `astro/autotag` are covered elsewhere).
---
--- Every case here failed against the code as it was; the comment on each one
--- says with what. They fall into three shapes that the native `vim.lsp`
--- pipeline makes easy to get wrong:
---
--- * a `root_dir` written to nvim-lspconfig's `fun(fname)` contract instead of
---   Neovim's `fun(bufnr, on_dir)` one,
--- * a global -- `vim.lsp.handlers`, the shared capabilities table, another
---   module's `vim.lsp.config` entry -- written from inside one server's setup,
--- * a name (`filetypes`, `root_markers`) that reads plausibly and matches
---   nothing.

describe("lsp.servers (the modules without their own spec)", function()
  ---@type table
  local shared

  before_each(function()
    shared = {
      capabilities = vim.lsp.protocol.make_client_capabilities(),
      on_attach = function() end,
      on_init = function()
        return true
      end,
    }
  end)

  --- Re-require a server module so module-level captures (`local executable =
  --- vim.fn.executable`) see whatever is stubbed right now.
  ---@param name string
  ---@return table
  local function fresh(name)
    package.loaded[name] = nil
    return require(name)
  end

  --- Forget a registered config so a second `setup()` in this file registers
  --- from scratch rather than merging into the previous case's entry.
  ---@param name string
  ---@return nil
  local function forget(name)
    ---@diagnostic disable-next-line: invisible
    vim.lsp.config._configs[name] = nil
  end

  --- What `lsp_enable_callback()` in `vim/lsp.lua` does with a config's root
  --- inputs, and nothing else: a `root_dir` *function* is called as
  --- `(bufnr, on_dir)` and has to call `on_dir`, while `root_markers` goes to
  --- `vim.fs.root()`. Reproducing the contract here rather than driving a real
  --- FileType autocmd keeps the failure readable -- inside the autocmd the same
  --- raise arrives wrapped in four layers of "Lua callback".
  ---@param cfg table
  ---@param bufnr integer
  ---@return string|nil
  local function resolve_root(cfg, bufnr)
    if type(cfg.root_dir) == "function" then
      local got ---@type string|nil
      cfg.root_dir(bufnr, function(root)
        got = root
      end)
      return got
    end
    if type(cfg.root_dir) == "string" then
      return cfg.root_dir
    end
    if type(cfg.root_markers) == "table" then
      return vim.fs.root(bufnr, cfg.root_markers)
    end
    return nil
  end

  --- A throwaway directory tree, plus a loaded buffer on one file in it.
  ---@param files string[] # paths relative to the tree root
  ---@param open string # which of them to open
  ---@return string root, integer bufnr
  local function tree(files, open)
    local root = vim.fs.normalize(vim.fn.tempname())
    for _, rel in ipairs(files) do
      local path = root .. "/" .. rel
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      vim.fn.writefile({ "" }, path)
    end
    local bufnr = vim.fn.bufadd(root .. "/" .. open)
    vim.fn.bufload(bufnr)
    return root, bufnr
  end

  ------------------------------------------------------------------------------
  -- mobiledev/dartls
  ------------------------------------------------------------------------------

  describe("mobiledev.dartls", function()
    ---@return table cfg
    local function register()
      forget("dartls")
      local orig_executable = vim.fn.executable
      local orig_exepath = vim.fn.exepath
      vim.fn.executable = function(name)
        return name == "dart" and 1 or orig_executable(name)
      end
      -- Resolvable via PATH, so find_flutter_sdk() takes the flutter_bin
      -- branch rather than falling back to FLUTTER_ROOT/FLUTTER_SDK.
      vim.fn.exepath = function(name)
        return name == "flutter" and "/opt/flutter/bin/flutter" or orig_exepath(name)
      end
      local ok, err = pcall(function()
        fresh("lsp.servers.mobiledev.dartls").setup(shared, { enable = false })
      end)
      vim.fn.executable, vim.fn.exepath = orig_executable, orig_exepath
      assert.is_true(ok, tostring(err))
      return vim.lsp.config["dartls"]
    end

    --- A fake `vim.lsp.Client`, shaped like `Client:initialize()` leaves it the
    --- moment `on_init` runs: `settings` already holds whatever the static
    --- `vim.lsp.config()` call declared, and `workspace/didChangeConfiguration`
    --- has already been sent from it -- `on_init` is the *second* chance a
    --- server has to learn anything, not the first.
    ---@param cfg table
    ---@return table client
    ---@return table[] notified
    local function fake_client(cfg)
      local notified = {}
      local client = {
        settings = vim.deepcopy(cfg.settings),
        config = cfg,
        notify = function(_self, method, params)
          notified[#notified + 1] = { method = method, params = params }
        end,
      }
      return client, notified
    end

    -- Failed before the fix: `on_init` wrote the Flutter SDK path into
    -- `client.config.settings`, a *reassignment* -- but `client.settings`
    -- (captured once at construction, before `on_init` ever runs) is what
    -- both delivery mechanisms actually read: the initial
    -- `workspace/didChangeConfiguration` push already fired from it by the
    -- time `on_init` runs, and Neovim's own default `workspace/configuration`
    -- pull handler looks up `client.settings`, never `client.config.settings`
    -- (`handlers.lua`'s `RSC['workspace/configuration']`). So the sdkPath
    -- reached neither path, on every machine with `flutter` on PATH.
    it("puts the Flutter SDK path where a server can actually read it", function()
      local cfg = register()
      local client = fake_client(cfg)

      cfg.on_init(client, {})

      assert.are.equal("/opt/flutter/bin/cache/dart-sdk", client.settings.dart.sdkPath)
      assert.are.equal("/opt/flutter", client.settings.dart.flutterSdkPath)
    end)

    it("pushes the update, since nothing re-sends it on its own", function()
      local cfg = register()
      local client, notified = fake_client(cfg)

      cfg.on_init(client, {})

      assert.are.equal(1, #notified)
      assert.are.equal("workspace/didChangeConfiguration", notified[1].method)
      assert.are.equal("/opt/flutter/bin/cache/dart-sdk", notified[1].params.settings.dart.sdkPath)
    end)

    it("still runs the shared on_init after its own work", function()
      local cfg = register()
      local client = fake_client(cfg)
      local shared_ran = false
      shared.on_init = function()
        shared_ran = true
        return true
      end

      assert.is_true(cfg.on_init(client, {}))
      assert.is_true(shared_ran)
    end)
  end)

  ------------------------------------------------------------------------------
  -- mobiledev/jdtls
  ------------------------------------------------------------------------------

  describe("mobiledev.jdtls", function()
    ---@return table cfg
    local function register()
      forget("jdtls")
      local exe = require("lib.nvim.cross.executable")
      local orig_mason, orig_executable = exe.mason_bin, vim.fn.executable
      exe.mason_bin = function(name)
        return name == "jdtls" and "/fake/bin/jdtls" or orig_mason(name)
      end
      vim.fn.executable = function(name)
        return name == "java" and 1 or orig_executable(name)
      end
      local ok, err = pcall(function()
        fresh("lsp.servers.mobiledev.jdtls").setup(shared, { enable = false })
      end)
      exe.mason_bin, vim.fn.executable = orig_mason, orig_executable
      assert.is_true(ok, tostring(err))
      return vim.lsp.config["jdtls"]
    end

    -- Failed before the fix with
    --   vim/fs.lua:89: file: expected string, got number
    -- raised from `java_root_dir`, because the module declared
    -- `root_dir = function(fname)` -- the lspconfig signature -- and the native
    -- pipeline calls `root_dir(bufnr, on_dir)`. Opening a .java buffer aborted
    -- `:edit` itself and left `#vim.lsp.get_clients{ name = "jdtls" } == 0`.
    it("resolves a Java project root through the native root contract", function()
      local cfg = register()
      local root, bufnr = tree({ "proj/pom.xml", "proj/src/A.java" }, "proj/src/A.java")

      local resolved
      assert.has_no.errors(function()
        resolved = resolve_root(cfg, bufnr)
      end)
      assert.are.equal(root .. "/proj", resolved)
    end)

    it("still prefers a Gradle wrapper over the enclosing repository", function()
      local cfg = register()
      local root, bufnr = tree({ ".git/HEAD", "app/gradlew", "app/A.java" }, "app/A.java")
      assert.are.equal(root .. "/app", resolve_root(cfg, bufnr))
    end)
  end)

  ------------------------------------------------------------------------------
  -- csharp
  ------------------------------------------------------------------------------

  describe("csharp", function()
    ---@return table cfg
    local function register()
      forget("omnisharp")
      local orig = vim.fn.executable
      vim.fn.executable = function(name)
        return name == "omnisharp" and 1 or orig(name)
      end
      local ok, err = pcall(function()
        fresh("lsp.servers.csharp").setup(shared, { enable = false })
      end)
      vim.fn.executable = orig
      assert.is_true(ok, tostring(err))
      return vim.lsp.config["omnisharp"]
    end

    -- Failed before the fix: the module declared
    --   root_markers = { ".git", ".sln", ".csproj" }
    -- but `root_markers` entries are file *names*, not extensions -- `vim.fs.root`
    -- hands each to `vim.fs.find`, which stats `<dir>/<name>` literally.
    -- Measured against this exact tree: `{ ".sln", ".csproj" }` resolved to nil
    -- and `{ "*.sln", "*.csproj" }` too (globs are not available through
    -- `root_markers` at all), so the solution's own directory was never found
    -- and the root came from `.git` one level up.
    it("roots a C# buffer at its project, not at the enclosing repository", function()
      local cfg = register()
      local root, bufnr = tree({ ".git/HEAD", "proj/App.csproj", "proj/src/Q.cs" }, "proj/src/Q.cs")
      assert.are.equal(root .. "/proj", resolve_root(cfg, bufnr))
    end)

    it("prefers a solution file and falls back to the repository", function()
      local cfg = register()

      local sln_root, sln_buf = tree({ "sol/App.sln", "sol/lib/L.cs" }, "sol/lib/L.cs")
      assert.are.equal(sln_root .. "/sol", resolve_root(cfg, sln_buf))

      local git_root, git_buf = tree({ ".git/HEAD", "loose/S.cs" }, "loose/S.cs")
      assert.are.equal(git_root, resolve_root(cfg, git_buf))
    end)

    it("declines rather than raising for a buffer with no file behind it", function()
      local cfg = register()
      local scratch = vim.api.nvim_create_buf(false, true)
      local started = false
      assert.has_no.errors(function()
        cfg.root_dir(scratch, function()
          started = true
        end)
      end)
      assert.is_false(started)
    end)
  end)

  ------------------------------------------------------------------------------
  -- marksman/code_action_handler
  ------------------------------------------------------------------------------

  describe("marksman.code_action_handler", function()
    ---@type any
    local saved

    before_each(function()
      saved = vim.lsp.handlers["textDocument/codeAction"]
      -- Neovim ships none since 0.11 (`vim.lsp.buf.code_action()` keeps its own
      -- so it can aggregate several clients into one prompt). Pinned to nil
      -- here so the case does not depend on nothing else having installed one.
      vim.lsp.handlers["textDocument/codeAction"] = nil
    end)

    after_each(function()
      vim.lsp.handlers["textDocument/codeAction"] = saved
    end)

    -- Failed before the fix with
    --   code_action_handler.lua:17: attempt to call upvalue 'default_handler'
    --   (a nil value)
    -- `make_handler()` captured `vim.lsp.handlers["textDocument/codeAction"]`
    -- when the wrapper was built, and that key is nil, so every path through
    -- the wrapper raised -- including the fall-through this module documents as
    -- "every other client's code actions pass through untouched".
    it("survives Neovim having no default codeAction handler", function()
      local handler = require("lsp.servers.marksman.code_action_handler")()
      local result = { { title = "Update TOC" } }
      local returned
      assert.has_no.errors(function()
        returned = handler(nil, result, nil, {})
      end)
      assert.are.same(result, returned)
    end)

    -- Failed before the fix for both reasons at once: nil at build time, and
    -- captured at build time -- `make_handler()` runs from `M.setup`, so a
    -- handler installed afterwards was invisible to it either way.
    it("filters TOC actions and forwards to a handler installed after setup", function()
      forget("marksman")
      require("lsp.servers.marksman").setup(shared, { enable = false })
      local cfg = vim.lsp.config["marksman"]
      assert.are.equal("function", type(cfg.handlers["textDocument/codeAction"]))

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, vim.fs.normalize(vim.fn.tempname()) .. ".md")
      vim.bo[bufnr].filetype = "markdown"

      local client_id = vim.lsp.start({
        name = "marksman",
        cmd = function(dispatchers)
          local closing = false
          return {
            request = function(method, _params, cb)
              if method == "initialize" then
                cb(nil, { capabilities = { codeActionProvider = true } })
              elseif method == "textDocument/codeAction" then
                cb(nil, {
                  { title = "Update TOC" },
                  { title = "Create missing document" },
                  { title = "Regenerate table of contents" },
                })
              else
                cb(nil, nil)
              end
              return true, 1
            end,
            notify = function()
              return true
            end,
            is_closing = function()
              return closing
            end,
            terminate = function()
              closing = true
              dispatchers.on_exit(0, 0)
            end,
          }
        end,
        root_dir = vim.fs.normalize(vim.fn.getcwd()),
        handlers = cfg.handlers,
      }, { bufnr = bufnr })
      assert.is_not_nil(client_id)

      -- Installed *after* the wrapper was built, which is the half a build-time
      -- capture cannot see.
      local seen
      vim.lsp.handlers["textDocument/codeAction"] = function(_err, result)
        seen = result
      end

      local client = assert(vim.lsp.get_client_by_id(client_id))
      assert.has_no.errors(function()
        -- No explicit handler, so the config's handler is what runs
        -- (`Client:_resolve_handler`).
        client:request("textDocument/codeAction", {
          textDocument = { uri = vim.uri_from_bufnr(bufnr) },
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
          context = { diagnostics = {} },
        }, nil, bufnr)
      end)

      client:stop(true)

      assert.are.same({ { title = "Create missing document" } }, seen)
    end)
  end)

  ------------------------------------------------------------------------------
  -- webdev/html
  ------------------------------------------------------------------------------

  describe("webdev.html", function()
    -- Failed before the fix: `on_init` assigned
    -- `vim.lsp.handlers["workspace/diagnostic/refresh"]`, the *global* table
    -- every client falls back to. Neovim 0.12.2 ships a real handler for that
    -- method, so the first html buffer of a session replaced pull-diagnostics
    -- refresh with a no-op for ts_ls, gopls and everything else attached.
    it("does not replace Neovim's global diagnostic-refresh handler", function()
      forget("html")
      local before = vim.lsp.handlers["workspace/diagnostic/refresh"]
      require("lsp.servers.webdev.html").setup(shared, { enable = false })

      local cfg = vim.lsp.config["html"]
      if type(cfg.on_init) == "function" then
        cfg.on_init({ name = "html", server_capabilities = {} }, {})
      end

      assert.are.equal(before, vim.lsp.handlers["workspace/diagnostic/refresh"])
      assert.are.equal("function", type(cfg.handlers["workspace/diagnostic/refresh"]))
      assert.are.equal(vim.NIL, cfg.handlers["workspace/diagnostic/refresh"]())
    end)
  end)

  ------------------------------------------------------------------------------
  -- webdev/ssp
  ------------------------------------------------------------------------------

  describe("webdev.ssp", function()
    -- Failed before the fix: both modules called `vim.lsp.config("html", …)`,
    -- and `vim.lsp.config()` merges into the existing entry, so setting up ssp
    -- after html rewrote html's own config in place. Measured, in that order:
    -- filetypes became { html, ssp, ejs, erb }, root_markers became
    -- { .git, package.json }, and html's `on_attach` wrapper -- the one that
    -- turns documentFormattingProvider off so prettier/conform own formatting
    -- -- was replaced by the bare shared one.
    it("leaves the html server's config alone", function()
      forget("html")
      forget("ssp")
      require("lsp.servers.webdev.html").setup(shared, { enable = false })
      local html = vim.lsp.config["html"]
      local filetypes = vim.deepcopy(html.filetypes)
      local root_markers = vim.deepcopy(html.root_markers)
      local on_attach = html.on_attach

      require("lsp.servers.webdev.ssp").setup(shared, { enable = false })

      html = vim.lsp.config["html"]
      assert.are.same(filetypes, html.filetypes)
      assert.are.same(root_markers, html.root_markers)
      assert.are.equal(on_attach, html.on_attach)
    end)

    it("registers under its own name and does not fight html for html buffers", function()
      forget("html")
      forget("ssp")
      require("lsp.servers.webdev.html").setup(shared, { enable = false })
      require("lsp.servers.webdev.ssp").setup(shared, { enable = false })

      local ssp = vim.lsp.config["ssp"]
      assert.are.equal("table", type(ssp))
      assert.is_false(
        vim.tbl_contains(ssp.filetypes, "html"),
        "two configs claiming 'html' would start two clients for one buffer"
      )
      assert.is_true(vim.tbl_contains(ssp.filetypes, "ssp"))

      -- Every filetype either config claims belongs to exactly one of them.
      -- `erb` in particular: Neovim sets `eruby` for a .erb file, and that name
      -- is html's -- so listing `erb` here matched nothing, and correcting it to
      -- `eruby` would have started a second html server on the same buffer.
      local html = vim.lsp.config["html"]
      for _, ft in ipairs(ssp.filetypes) do
        assert.is_false(
          vim.tbl_contains(html.filetypes, ft),
          ("%q is claimed by both the html and the ssp config"):format(ft)
        )
      end
    end)
  end)

  ------------------------------------------------------------------------------
  -- webdev/astro
  ------------------------------------------------------------------------------

  describe("webdev.astro", function()
    -- Failed before the fix: the module did `local caps = shared.capabilities`
    -- and wrote into it. `shared.capabilities` is the single table `lsp.init`
    -- builds once and passes to every server module, so Astro's snippetSupport
    -- landed on every server set up after it -- and, because it was the same
    -- table, Astro had no capability set of its own either.
    it("extends a copy of the shared capabilities, not the caller's table", function()
      forget("astro")
      local caps = { textDocument = {} }
      require("lsp.servers.webdev.astro").setup({ capabilities = caps }, { enable = false })

      assert.is_nil(caps.textDocument.completion, "the caller's table must come back unchanged")

      local cfg = vim.lsp.config["astro"]
      assert.is_false(rawequal(caps, cfg.capabilities))
      assert.is_true(cfg.capabilities.textDocument.completion.completionItem.snippetSupport)
    end)
  end)

  ------------------------------------------------------------------------------
  -- mobiledev/sourcekit
  ------------------------------------------------------------------------------

  describe("mobiledev.sourcekit", function()
    -- Failed before the fix: `filetypes` said "objective-c"/"objective-cpp".
    -- `can_start()` matches `filetypes` against `vim.bo.filetype` with a plain
    -- `tbl_contains`, and neither hyphenated name exists anywhere in Neovim's
    -- runtime -- `vim/filetype/detect.lua` returns `objc` and `objcpp`. So
    -- sourcekit covered Swift and silently never attached to Objective-C.
    it("uses the filetype names Neovim actually sets", function()
      forget("sourcekit")
      local orig_uname, orig_executable = vim.loop.os_uname, vim.fn.executable
      vim.loop.os_uname = function()
        return { sysname = "Darwin" }
      end
      vim.fn.executable = function(name)
        return name == "sourcekit-lsp" and 1 or orig_executable(name)
      end
      local ok, err = pcall(function()
        fresh("lsp.servers.mobiledev.sourcekit").setup(shared, { enable = false })
      end)
      vim.loop.os_uname, vim.fn.executable = orig_uname, orig_executable
      assert.is_true(ok, tostring(err))

      local cfg = vim.lsp.config["sourcekit"]
      assert.are.same({ "swift", "objc", "objcpp" }, cfg.filetypes)

      -- The same two names clangd is configured with, in this same plugin.
      forget("clangd")
      require("lsp.servers.clangd").setup(shared, { enable = false })
      for _, ft in ipairs({ "objc", "objcpp" }) do
        assert.is_true(
          vim.tbl_contains(vim.lsp.config["clangd"].filetypes, ft),
          ft .. " must be spelled the same way in both C-family server configs"
        )
      end
    end)
  end)
end)
