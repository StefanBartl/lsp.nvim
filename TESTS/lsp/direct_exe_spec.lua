--- Covers `lsp.core.direct_exe` and the two server configs that use it.
---
--- Through Mason's `mason/bin/<name>.CMD` wrapper the server is a grandchild
--- of Neovim (`nvim -> cmd.exe -> server.exe`) and `:LspStop` only kills the
--- `cmd.exe`; the module header has the details. What is pinned here: the
--- resolver picks the installed exe when it exists, keeps the PATH name when
--- it does not (and off Windows), and marksman / lua_ls actually register the
--- resolved command.
---
--- `stdpath("data")` and `$SCOOP` point at a throwaway directory for every
--- case, so the machine's real Mason and scoop installs are never consulted.
--- `vim.fn.has("win32")` is stubbed so the Windows-only branch runs on every
--- platform.

local direct_exe = require("lsp.core.direct_exe")

---@param win32 integer
---@param fn fun(root: string): nil
local function with_env(win32, fn)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  local orig_has, orig_stdpath, orig_scoop = vim.fn.has, vim.fn.stdpath, vim.env.SCOOP
  vim.fn.has = function(feature)
    if feature == "win32" then
      return win32
    end
    return orig_has(feature)
  end
  vim.fn.stdpath = function(what)
    if what == "data" then
      return root .. "/data"
    end
    return orig_stdpath(what)
  end
  vim.env.SCOOP = root .. "/scoop"
  local ok, err = pcall(fn, root)
  vim.fn.has, vim.fn.stdpath, vim.env.SCOOP = orig_has, orig_stdpath, orig_scoop
  pcall(vim.fn.delete, root, "rf")
  assert(ok, err)
end

---@param path string
---@return string path
local function touch(path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({}, path)
  return path
end

---@param name string
---@param module string
---@return string[]
local function registered_cmd(name, module)
  ---@diagnostic disable-next-line: invisible
  vim.lsp.config._configs[name] = nil
  package.loaded[module] = nil
  require(module).setup({}, { enable = false })
  return vim.lsp.config[name].cmd
end

describe("lsp.core.direct_exe", function()
  it("resolve picks the first existing candidate on Windows", function()
    with_env(1, function(root)
      local missing = root .. "/nope/a.exe"
      local present = touch(root .. "/pkg/a.exe")
      assert.are.equal(vim.fs.normalize(present), direct_exe.resolve("a", { missing, present }))
    end)
  end)

  it("resolve keeps the PATH name when no candidate exists", function()
    with_env(1, function(root)
      assert.are.equal("a", direct_exe.resolve("a", { root .. "/nope/a.exe" }))
    end)
  end)

  it("resolve ignores a directory with the candidate's name", function()
    with_env(1, function(root)
      vim.fn.mkdir(root .. "/dir/a.exe", "p")
      assert.are.equal("a", direct_exe.resolve("a", { root .. "/dir/a.exe" }))
    end)
  end)

  it("resolve keeps the PATH name off Windows even when the exe exists", function()
    with_env(0, function(root)
      local present = touch(root .. "/pkg/a.exe")
      assert.are.equal("a", direct_exe.resolve("a", { present }))
    end)
  end)

  it("cmd appends the arguments to the resolved executable", function()
    with_env(1, function(root)
      local present = touch(root .. "/pkg/a.exe")
      assert.are.same(
        { vim.fs.normalize(present), "x", "y" },
        direct_exe.cmd("a", { present }, { "x", "y" })
      )
    end)
  end)

  it("scoop_app falls back to ~/scoop when $SCOOP is unset", function()
    local orig = vim.env.SCOOP
    vim.env.SCOOP = nil
    local path = direct_exe.scoop_app("app", "bin/app.exe")
    vim.env.SCOOP = orig
    assert.are.equal(vim.fn.expand("~") .. "/scoop/apps/app/current/bin/app.exe", path)
  end)
end)

describe("server commands", function()
  it("marksman starts the Mason exe directly when it is installed", function()
    with_env(1, function(root)
      local exe = touch(root .. "/data/mason/packages/marksman/marksman.exe")
      assert.are.same(
        { vim.fs.normalize(exe), "server" },
        registered_cmd("marksman", "lsp.servers.marksman")
      )
    end)
  end)

  it("marksman keeps the PATH name when the Mason exe is missing", function()
    with_env(1, function()
      assert.are.same({ "marksman", "server" }, registered_cmd("marksman", "lsp.servers.marksman"))
    end)
  end)

  it("lua_ls starts the scoop app's exe instead of the shim", function()
    with_env(1, function(root)
      local exe =
        touch(root .. "/scoop/apps/lua-language-server/current/bin/lua-language-server.exe")
      assert.are.same({ vim.fs.normalize(exe) }, registered_cmd("lua_ls", "lsp.servers.lua_ls"))
    end)
  end)

  it("lua_ls falls back to the Mason package, then to the PATH name", function()
    with_env(1, function(root)
      assert.are.same({ "lua-language-server" }, registered_cmd("lua_ls", "lsp.servers.lua_ls"))
      local exe =
        touch(root .. "/data/mason/packages/lua-language-server/bin/lua-language-server.exe")
      assert.are.same({ vim.fs.normalize(exe) }, registered_cmd("lua_ls", "lsp.servers.lua_ls"))
    end)
  end)
end)
