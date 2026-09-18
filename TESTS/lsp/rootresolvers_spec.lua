--- Covers the root-directory algorithms this plugin owns on top of
--- `lib.nvim.fs.polymorphic_rootresolver` (that module's own argument
--- normalization -- buffer number or filename, unnamed-buffer fallback, the
--- optional callback -- is `lib.nvim`'s to test, not this plugin's):
---
--- - `lsp.servers.lua_ls.rootresolver`'s `strict_root_from` algorithm: the
---   `<leader>lsp` root-scope switch, the VCS-then-marker-then-fallback
---   search, and that the Neovim config directory always wins regardless of
---   scope.
--- - `lsp.servers.marksman.rootresolver`: that it actually wires marksman's
---   own marker list through rather than the shared default.
--- - `lsp.tools.eslint_prettier.core.find_root`'s wrapper around
---   `lib.nvim.fs.find_root`: the unnamed-buffer guard and bufnr handling.
---
--- All three touch real directories under a real temp root rather than
--- stubbing `vim.fs.*` -- the risk here is path comparison and search order,
--- which a stub would define away.

local root_scope = require("lsp.core.root_scope")

---@param path string
---@return string
local function norm(path)
  return vim.fs.normalize(path)
end

---@param dir string
---@param name string
---@return nil
local function touch(dir, name)
  vim.fn.writefile({}, dir .. "/" .. name)
end

---@param fn fun(dir: string): nil
local function with_tempdir(fn)
  local dir = norm(vim.fn.tempname())
  vim.fn.mkdir(dir .. "/sub", "p")
  local ok, err = pcall(fn, dir)
  pcall(vim.fn.delete, dir, "rf")
  assert(ok, err)
end

describe("lsp.servers.lua_ls.rootresolver", function()
  local resolve = require("lsp.servers.lua_ls.rootresolver")

  after_each(function()
    root_scope.set("git")
  end)

  it("finds the nearest VCS root over a marker further up", function()
    with_tempdir(function(dir)
      vim.fn.mkdir(dir .. "/.git", "p")
      touch(dir, "stylua.toml")

      local root = resolve(dir .. "/sub/file.lua")

      assert.are.equal(norm(dir), norm(root))
    end)
  end)

  it("falls back to a Lua marker's directory when there is no VCS root", function()
    with_tempdir(function(dir)
      touch(dir, ".luarc.json")

      local root = resolve(dir .. "/sub/file.lua")

      assert.are.equal(norm(dir), norm(root))
    end)
  end)

  it("falls back to the starting directory when neither is found", function()
    with_tempdir(function(dir)
      local root = resolve(dir .. "/sub/file.lua")

      assert.are.equal(norm(dir .. "/sub"), norm(root))
    end)
  end)

  it("scope=cwd returns the current working directory, ignoring markers", function()
    with_tempdir(function(dir)
      vim.fn.mkdir(dir .. "/.git", "p")
      root_scope.set("cwd")

      local root = resolve(dir .. "/sub/file.lua")
      local cwd = (vim.uv or vim.loop).cwd() or vim.fn.getcwd()

      assert.are.equal(norm(cwd), norm(root))
    end)
  end)

  it("scope=path returns the file's own directory, ignoring markers", function()
    with_tempdir(function(dir)
      vim.fn.mkdir(dir .. "/.git", "p")
      root_scope.set("path")

      local root = resolve(dir .. "/sub/file.lua")

      assert.are.equal(norm(dir .. "/sub"), norm(root))
    end)
  end)

  -- Checked first, before the scope switch and before any search -- a file
  -- edited under the Neovim config directory belongs to the config even when
  -- the active scope is "cwd" or "path".
  it("treats the Neovim config directory as a root regardless of scope", function()
    with_tempdir(function(fake_config)
      local orig = vim.fn.stdpath
      vim.fn.stdpath = function(what)
        if what == "config" then
          return fake_config
        end
        return orig(what)
      end

      local ok, err = pcall(function()
        for _, scope in ipairs({ "git", "cwd", "path" }) do
          root_scope.set(scope)
          local root = resolve(fake_config .. "/sub/init.lua")
          assert.are.equal(norm(fake_config), norm(root), "scope=" .. scope)
        end
      end)

      vim.fn.stdpath = orig
      assert(ok, err)
    end)
  end)
end)

describe("lsp.servers.marksman.rootresolver", function()
  -- A factory, not a resolver directly -- `require(...)()` builds the bound
  -- function, matching how `lsp.servers.marksman` actually calls it.
  local resolve = require("lsp.servers.marksman.rootresolver")()

  it("uses marksman's own marker list, not the shared VCS default", function()
    with_tempdir(function(dir)
      touch(dir, ".marksman.toml")

      local root = resolve(dir .. "/sub/doc.md")

      assert.are.equal(norm(dir), norm(root))
    end)
  end)

  it("also honours the mkdocs.yml fallback from lsp.servers.marksman.config", function()
    with_tempdir(function(dir)
      touch(dir, "mkdocs.yml")

      local root = resolve(dir .. "/sub/doc.md")

      assert.are.equal(norm(dir), norm(root))
    end)
  end)

  it("falls back to the file's own directory when no marker is found", function()
    with_tempdir(function(dir)
      local root = resolve(dir .. "/sub/doc.md")

      assert.are.equal(norm(dir .. "/sub"), norm(root))
    end)
  end)
end)

describe("lsp.tools.eslint_prettier.core.find_root", function()
  local find_root = require("lsp.tools.eslint_prettier.core.find_root")

  it("returns nil for an unnamed buffer instead of resolving from cwd", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local ok, err = pcall(function()
      assert.is_nil(find_root(bufnr))
    end)
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    assert(ok, err)
  end)

  it("resolves the nearest package.json upward from a named buffer", function()
    with_tempdir(function(dir)
      touch(dir, "package.json")
      local path = dir .. "/sub/index.js"
      vim.fn.writefile({}, path)

      local bufnr = vim.fn.bufadd(path)
      local ok, err = pcall(function()
        assert.are.equal(norm(dir), norm(find_root(bufnr)))
      end)
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      assert(ok, err)
    end)
  end)

  it("defaults to the current buffer when no bufnr is given", function()
    with_tempdir(function(dir)
      touch(dir, ".eslintrc")
      local path = dir .. "/sub/index.js"
      vim.fn.writefile({}, path)

      local prev = vim.api.nvim_get_current_buf()
      vim.cmd.edit(vim.fn.fnameescape(path))
      local bufnr = vim.api.nvim_get_current_buf()

      local ok, err = pcall(function()
        assert.are.equal(norm(dir), norm(find_root(nil)))
      end)
      pcall(vim.api.nvim_win_set_buf, 0, prev)
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      assert(ok, err)
    end)
  end)
end)
