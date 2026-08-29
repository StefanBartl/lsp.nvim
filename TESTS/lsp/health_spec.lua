--- Covers the parts of `:checkhealth lsp` that answer "what is this costing
--- me": the installed side, the per-buffer attached line, and the one warning
--- that fires for a heavy server held over many buffers.
---
--- `vim.health` is replaced by a recorder rather than left to write into a
--- report buffer, so what these cases assert is the text a user would read,
--- at the severity they would read it at. Severity is half the message here:
--- "38 servers installed" is information and "ts_ls is holding 40 buffers" is
--- a warning, and swapping the two would make the report useless in opposite
--- directions.
---
--- The clients are stubbed. There is no language server in this harness, and
--- the interesting cases -- forty attached buffers, a client on a file the
--- report was not opened from -- are ones you would not want to reproduce for
--- real anyway.

describe("lsp.health", function()
  ---@type { level: string, msg: string }[]
  local emitted = {}

  ---@type table<string, any>
  local saved = {}

  --- Collect the health output of one `check()` run.
  ---@return string[] lines # "level|message", in emission order.
  local function lines()
    ---@type string[]
    local out = {}
    for _, entry in ipairs(emitted) do
      out[#out + 1] = entry.level .. "|" .. entry.msg
    end
    return out
  end

  --- Find the first emitted line containing `needle`.
  ---@param needle string
  ---@return { level: string, msg: string }|nil
  local function find(needle)
    for _, entry in ipairs(emitted) do
      if entry.msg:find(needle, 1, true) then
        return entry
      end
    end
    return nil
  end

  --- One stub LSP client.
  ---@param name string
  ---@param buffers integer[]
  ---@return table
  local function client(name, buffers)
    ---@type table<integer, boolean>
    local attached = {}
    for _, bufnr in ipairs(buffers) do
      attached[bufnr] = true
    end
    return {
      id = #buffers,
      name = name,
      root_dir = "/repo",
      attached_buffers = attached,
    }
  end

  --- Install every stub and load a fresh `lsp.health`.
  ---@param opts { clients?: table[], here?: table[], servers?: string[] }
  ---@return table
  local function setup(opts)
    emitted = {}

    vim.health = {
      start = function() end,
      ok = function(msg)
        emitted[#emitted + 1] = { level = "ok", msg = msg }
      end,
      info = function(msg)
        emitted[#emitted + 1] = { level = "info", msg = msg }
      end,
      warn = function(msg)
        emitted[#emitted + 1] = { level = "warn", msg = msg }
      end,
      error = function(msg)
        emitted[#emitted + 1] = { level = "error", msg = msg }
      end,
    }

    local servers = opts.servers or { "lua_ls", "ts_ls" }
    package.loaded["lsp"] = {
      status = function()
        return {
          initialized = true,
          config = require("lsp.config").setup({ servers = servers }),
          keymaps = {},
          usrcmd = true,
          servers = servers,
          clients = opts.clients or {},
          warnings = {},
        }
      end,
    }

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.get_clients = function(filter)
      if filter ~= nil and filter.bufnr ~= nil then
        return opts.here or {}
      end
      return opts.clients or {}
    end

    package.loaded["lsp.health"] = nil
    return require("lsp.health")
  end

  before_each(function()
    saved.health = vim.health
    saved.get_clients = vim.lsp.get_clients
    saved.lsp = package.loaded["lsp"]
    saved.registry = package.loaded["mason-registry"]
    -- Not installed by default; the cases that need it install their own.
    package.loaded["mason-registry"] = nil
  end)

  after_each(function()
    vim.health = saved.health
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.get_clients = saved.get_clients
    package.loaded["lsp"] = saved.lsp
    package.loaded["mason-registry"] = saved.registry
    package.loaded["lsp.health"] = nil
    package.loaded["lsp.config"] = nil
  end)

  describe("installed side", function()
    it("says why the installed count is unknown rather than reporting zero", function()
      setup({}).check()

      local entry = find("installed (mason): unknown")
      assert.is_not_nil(entry)
      assert.are.equal("info", entry.level)
      assert.is_truthy(entry.msg:find("mason.nvim is not installed", 1, true))
    end)

    it("counts only the packages mason files under LSP", function()
      package.loaded["mason-registry"] = {
        get_installed_packages = function()
          return {
            { name = "lua-language-server", spec = { categories = { "LSP" } } },
            { name = "stylua", spec = { categories = { "Formatter" } } },
            { name = "bash-language-server", spec = { categories = { "LSP" } } },
          }
        end,
      }
      setup({}).check()

      local entry = find("installed (mason): 2 LSP package(s)")
      assert.is_not_nil(entry)
      assert.is_truthy(entry.msg:find("bash-language-server", 1, true))
      assert.is_falsy(entry.msg:find("stylua", 1, true))
    end)

    -- A package's categories come from the registry index, which is only
    -- loaded once mason.setup() has run. Reporting "0 installed" next to
    -- seventy present packages would be a plain lie, so it reports neither.
    it("refuses to report zero when the registry is not hydrated", function()
      package.loaded["mason-registry"] = {
        get_installed_packages = function()
          return {
            { name = "lua-language-server", spec = { categories = {} } },
            { name = "stylua", spec = { categories = {} } },
          }
        end,
      }
      setup({}).check()

      assert.is_nil(find("installed (mason): no LSP package"))
      local entry = find("registry is not loaded yet")
      assert.is_not_nil(entry)
      assert.are.equal("info", entry.level)
    end)

    it("reports an empty install as empty, not as unknown", function()
      package.loaded["mason-registry"] = {
        get_installed_packages = function()
          return { { name = "stylua", spec = { categories = { "Formatter" } } } }
        end,
      }
      setup({}).check()

      assert.is_not_nil(find("installed (mason): no LSP package"))
    end)
  end)

  describe("attached to this buffer", function()
    it("names the clients serving the buffer, against the running total", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(bufnr, "/repo/init.lua")
      vim.api.nvim_set_current_buf(bufnr)

      setup({
        clients = { client("lua_ls", { bufnr }), client("marksman", { 99 }) },
        here = { client("lua_ls", { bufnr }) },
      }).check()

      local entry = find("attached to init.lua")
      assert.is_not_nil(entry)
      assert.are.equal("ok", entry.level)
      assert.is_truthy(entry.msg:find("1 of 2 running client(s)", 1, true))
      assert.is_truthy(entry.msg:find("lua_ls", 1, true))
    end)

    it("says none rather than staying silent when nothing serves the buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(bufnr, "/repo/notes.txt")
      vim.api.nvim_set_current_buf(bufnr)

      setup({ clients = { client("lua_ls", { 99 }) }, here = {} }).check()

      local entry = find("attached to notes.txt")
      assert.is_not_nil(entry)
      assert.are.equal("info", entry.level)
      assert.is_truthy(entry.msg:find("none of the 1 running client(s)", 1, true))
    end)

    -- Neovim makes the `health://` buffer current before running any check, so
    -- reading the current buffer would report on the report itself. The buffer
    -- the user came from is the alternate one.
    it("reports on the buffer behind the health report, not the report", function()
      local file = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(file, "/repo/main.go")
      vim.api.nvim_set_current_buf(file)

      local report = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_name(report, "health://")
      vim.api.nvim_set_current_buf(report)
      assert.are.equal(file, vim.fn.bufnr("#"))

      setup({ clients = { client("gopls", { file }) }, here = { client("gopls", { file }) } }).check()

      assert.is_not_nil(find("attached to main.go"))
      assert.is_nil(find("attached to health://"))
    end)
  end)

  describe("the heavy-server warning", function()
    ---@param count integer
    ---@return integer[]
    local function buffers(count)
      ---@type integer[]
      local list = {}
      for i = 1, count do
        list[i] = 10000 + i -- not real buffers; the line count guard skips them
      end
      return list
    end

    it("warns when a heavy server is held over many buffers", function()
      setup({ clients = { client("ts_ls", buffers(40)) } }).check()

      local entry = find("ts_ls (id 40)")
      assert.is_not_nil(entry)
      assert.are.equal("warn", entry.level)
    end)

    -- A count on its own is not a problem. Five buffers on ts_ls is a working
    -- set, and warning about it would train the reader to ignore the section.
    it("stays quiet about a heavy server on a normal working set", function()
      setup({ clients = { client("ts_ls", buffers(5)) } }).check()

      local entry = find("ts_ls (id 5)")
      assert.is_not_nil(entry)
      assert.are.equal("ok", entry.level)
    end)

    it("does not warn about a cheap server whatever the count", function()
      setup({ clients = { client("marksman", buffers(40)) } }).check()

      local entry = find("marksman (id 40)")
      assert.is_not_nil(entry)
      assert.are.equal("ok", entry.level)
    end)

    it("still reports every client, warned or not", function()
      setup({
        clients = { client("ts_ls", buffers(40)), client("lua_ls", buffers(3)) },
      }).check()

      assert.is_not_nil(find("ts_ls"))
      assert.is_not_nil(find("lua_ls"))
      assert.is_true(#lines() > 0)
    end)
  end)
end)
