--- Executables are resolved when they are used, not while the config is set up.
---
--- Measured on Windows: `vim.fn.exepath` costs ~40 ms for every name that is NOT
--- installed (every $PATH entry x every $PATHEXT extension), and the synchronous
--- startup phase paid that for four formatters and three html server names, plus
--- a failed `require("nvchad...")` (~13 ms) on each of four calls.

describe("lazy executable resolution", function()
  local native ---@type integer
  local real_exepath, real_executable

  before_each(function()
    native = 0
    real_exepath, real_executable = vim.fn.exepath, vim.fn.executable
    vim.fn.exepath = function(...)
      native = native + 1
      return real_exepath(...)
    end
    vim.fn.executable = function(...)
      native = native + 1
      return real_executable(...)
    end
    require("lib.nvim.cross.executable").clear()
  end)

  after_each(function()
    vim.fn.exepath, vim.fn.executable = real_exepath, real_executable
    package.loaded["conform"] = nil
    require("lib.nvim.cross.executable").clear()
  end)

  describe("formatter.conform", function()
    ---@return table opts what `M.setup` handed to `conform.setup`
    local function setup_capture()
      local captured
      package.loaded["conform"] = {
        setup = function(opts)
          captured = opts
        end,
      }
      package.loaded["lsp.formatter.conform"] = nil
      require("lsp.formatter.conform").setup()
      return captured
    end

    it("resolves no executable while setting up", function()
      native = 0
      setup_capture()
      assert.are.equal(0, native)
    end)

    it("hands conform a function per formatter command", function()
      local opts = setup_capture()
      for _, name in ipairs({ "mdformat", "prettierd", "prettier", "shfmt", "shellharden" }) do
        assert.are.equal("function", type(opts.formatters[name].command), name)
      end
    end)

    it("answers a missing formatter with an absolute path, not the bare name", function()
      -- conform runs vim.fn.executable(command) on every format call: for a bare
      -- name that is the full $PATH walk each time, for an absolute path one stat.
      local opts = setup_capture()
      local command = opts.formatters.shellharden.command({}, {})
      local expected_dir = vim.fn.stdpath("data"):gsub("\\", "/") .. "/mason/bin/"
      local shown = command:gsub("\\", "/")
      -- Not installed here -> the Mason location; installed -> wherever it is.
      -- Either way it is a path, never the bare name.
      assert.is_truthy(shown:find("/", 1, true), command)
      assert.are_not.equal("shellharden", command)
      if not shown:find(expected_dir, 1, true) then
        assert.are.equal(1, real_executable(command), command)
      end
    end)

    it("does not repeat the $PATH walk on a second resolve", function()
      local opts = setup_capture()
      opts.formatters.shellharden.command({}, {})
      local after_first = native
      opts.formatters.shellharden.command({}, {})
      assert.are.equal(after_first, native)
    end)
  end)

  describe("servers.webdev.html", function()
    local shared = {}

    ---@param opts table
    ---@return table config
    local function setup_html(opts)
      package.loaded["lsp.servers.webdev.html"] = nil
      require("lsp.servers.webdev.html").setup(
        shared,
        vim.tbl_extend("force", { enable = false }, opts)
      )
      return vim.lsp.config["html"]
    end

    it("resolves no candidate while setting up", function()
      native = 0
      setup_html({ cmd = { "no-such-html-server-a", "no-such-html-server-b" } })
      assert.are.equal(0, native)
    end)

    it("makes cmd a function that starts the client", function()
      local cfg = setup_html({ cmd = { "no-such-html-server-a" } })
      assert.are.equal("function", type(cfg.cmd))
    end)

    it("starts the first candidate that resolves, with --stdio", function()
      local cfg = setup_html({ cmd = { "no-such-html-server-a", "nvim" } })
      local started
      local real_start = vim.lsp.rpc.start
      vim.lsp.rpc.start = function(argv, dispatchers, params)
        started = { argv = argv, dispatchers = dispatchers, params = params }
        return { fake = true }
      end
      local client = cfg.cmd({ marker = 1 }, { cmd_cwd = "/work", detached = false })
      vim.lsp.rpc.start = real_start

      assert.are.same({ fake = true }, client)
      assert.are.equal("--stdio", started.argv[2])
      assert.are.equal("nvim", vim.fs.basename(started.argv[1]):lower():gsub("%.exe$", ""))
      assert.are.same({ marker = 1 }, started.dispatchers)
      assert.are.equal("/work", started.params.cwd)
      assert.are.equal(false, started.params.detached)
    end)

    it("falls back to the candidate list when nothing is installed", function()
      local cfg = setup_html({ cmd = { "no-such-html-server-a", "no-such-html-server-b" } })
      local argv
      local real_start = vim.lsp.rpc.start
      vim.lsp.rpc.start = function(cmd)
        argv = cmd
        return {}
      end
      cfg.cmd({}, {})
      vim.lsp.rpc.start = real_start
      assert.are.same({ "no-such-html-server-a", "no-such-html-server-b" }, argv)
    end)
  end)

  describe("integrations.nvchad", function()
    it("probes for a missing NvChad once, not on every call", function()
      local attempts = 0
      local real_require = require
      _G.require = function(name)
        if name == "nvchad.configs.lspconfig" then
          attempts = attempts + 1
        end
        return real_require(name)
      end

      package.loaded["lsp.integrations.nvchad"] = nil
      local nvchad = real_require("lsp.integrations.nvchad")
      nvchad.reset()
      local available = nvchad.available()
      nvchad.available()
      nvchad.capabilities({})
      nvchad.on_init({})
      _G.require = real_require

      if available then
        -- NvChad is installed on this machine: nothing to remember.
        assert.is_true(attempts >= 1)
      else
        assert.are.equal(1, attempts)
      end
    end)

    it("picks NvChad up once its module is loaded by someone else", function()
      package.loaded["lsp.integrations.nvchad"] = nil
      local nvchad = require("lsp.integrations.nvchad")
      nvchad.reset()
      package.loaded["nvchad.configs.lspconfig"] = nil
      -- Probe negative first (or positive if installed) ...
      local was_available = nvchad.available()
      package.loaded["nvchad.configs.lspconfig"] = { capabilities = { fake = true } }
      -- ... then a loaded module is answered from package.loaded either way.
      assert.is_true(nvchad.available())
      package.loaded["nvchad.configs.lspconfig"] = nil
      if not was_available then
        nvchad.reset()
      end
    end)
  end)
end)
