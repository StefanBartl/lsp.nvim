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

--- A created temp directory, in the spelling the *operating system* reports
--- for it -- which is the spelling every path that reaches these resolvers
--- already carries.
---
--- `vim.fn.tempname()` alone is not that spelling. On macOS `$TMPDIR` lives
--- under the `/var` -> `/private/var` symlink, so tempname() answers
--- `/var/folders/...` while Neovim canonicalizes a buffer name on the way in
--- (`nvim_buf_get_name` after `bufadd`/`:edit` gives `/private/var/...`) and
--- `uv.cwd()` does the same for the working directory. A resolver handed a
--- buffer therefore *correctly* returns the resolved spelling, and comparing
--- it against the raw tempname compares two spellings of one directory.
--- Measured on macOS CI: `/private/var/folders/.../9` vs
--- `/var/folders/.../9`. Windows has the same trap when `%TEMP%` is the 8.3
--- short form (`C:/Users/STEFAN~1/...`).
---
--- `fs_realpath` needs the directory to exist, so this resolves after
--- `mkdir`, not before.
---@param path string  # a path that exists on disk
---@return string
local function real(path)
  return norm((vim.uv or vim.loop).fs_realpath(path) or path)
end

---@param fn fun(dir: string): nil
local function with_tempdir(fn)
  local dir = norm(vim.fn.tempname())
  vim.fn.mkdir(dir .. "/sub", "p")
  dir = real(dir)
  local ok, err = pcall(fn, dir)
  pcall(vim.fn.delete, dir, "rf")
  assert(ok, err)
end

--- Create a directory symlink, reporting *why* it could not be created rather
--- than only that it was not.
---
--- A junction (`mklink /J`) is not a substitute: it is a different object with
--- different resolution semantics, and these cases are specifically about what
--- `uv.fs_realpath` sees through.
---@param target string
---@param link string
---@return boolean ok
---@return string|nil err
local function try_symlink(target, link)
  local ok, err = (vim.uv or vim.loop).fs_symlink(target, link, { dir = true, junction = false })
  return ok == true, err
end

--- Skip the current case because this machine cannot create a symlink -- and
--- say so loudly enough that the skip cannot be mistaken for a pass.
---
--- Same rules as `probe_live_spec.lua`, for the same reason: plenary's
--- `pending` prints `Pending` and the run still tallies the case under
--- `Success`, so a gate that quietly skips itself reports confidence it never
--- earned. So this names the reason, writes it to stderr as well as into the
--- `PENDING` line, and **fails instead of skipping under `CI` on any platform
--- that is not Windows**.
---
--- The gate is on whether a symlink can actually be *made*, not on the
--- platform. That distinction earns its keep: creating one on Windows needs
--- `SeCreateSymbolicLinkPrivilege` (Developer Mode or elevation), so a blanket
--- `has("win32")` skip is the obvious move -- and it would be wrong. Measured
--- on this workflow's own runners: ubuntu, macos *and* windows-latest all
--- create it, so all three run these cases. A plain platform skip would have
--- thrown away the Windows coverage that works.
---
--- Windows stays the one platform allowed to skip, because it is the one where
--- the privilege can genuinely be absent -- a developer machine without
--- Developer Mode. Linux and macOS have no such excuse: a symlink failing
--- there is a broken environment, and these are exactly the platforms where
--- the bug bites, because Unix Neovim canonicalizes a path on the way into a
--- buffer name and Windows -- measured -- does not. The Windows escape hatch
--- is kept rather than tightened to match what the runner does today, since a
--- future runner image could drop the privilege and that should read as a skip
--- rather than a failure about the wrong thing.
---@param why string
local function skip_no_symlink(why)
  local message = "needs a real directory symlink, which this machine refused: " .. why
  io.stderr:write("\n[rootresolvers] SKIPPED: " .. message .. "\n")
  local ci = vim.env.CI
  local windows = vim.fn.has("win32") == 1
  if ci ~= nil and ci ~= "" and ci ~= "false" and not windows then
    assert.is_true(false, "outside Windows a symlink must be creatable under CI, so: " .. message)
  end
  pending(message)
end

--- The dotfiles layout these cases are about:
---
---   <base>/dotfiles/.git          -- so the VCS search has something to find
---   <base>/dotfiles/nvim/lua/     -- the real config tree
---   <base>/config_link  ->  <base>/dotfiles/nvim
---
--- `fn` receives the link spelling, the resolved spelling of that same
--- directory, and the repo root the VCS search would otherwise settle on.
--- Skips (loudly) and returns false when the symlink could not be created.
---@param fn fun(link: string, resolved: string, repo: string): nil
---@return boolean ran
local function with_symlinked_config(fn)
  local base = norm(vim.fn.tempname())
  vim.fn.mkdir(base .. "/dotfiles/nvim/lua/plugins", "p")
  vim.fn.mkdir(base .. "/dotfiles/.git", "p")
  base = real(base)

  local repo = base .. "/dotfiles"
  local link = base .. "/config_link"
  local ok, err = try_symlink(repo .. "/nvim", link)
  if not ok then
    pcall(vim.fn.delete, base, "rf")
    skip_no_symlink(tostring(err))
    return false
  end

  local ran, ferr = pcall(fn, norm(link), real(link), repo)
  pcall(vim.fn.delete, base, "rf")
  assert(ran, ferr)
  return true
end

--- Run `fn` with `stdpath("config")` answering `link`, restoring the real one
--- afterwards whatever happens -- a leaked stub would silently redirect every
--- later case in the run.
---@param link string
---@param fn fun(): nil
local function with_stdpath_config(link, fn)
  local orig = vim.fn.stdpath
  vim.fn.stdpath = function(what)
    if what == "config" then
      return link
    end
    return orig(what)
  end
  local ok, err = pcall(fn)
  vim.fn.stdpath = orig
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

  -- The dotfiles case, and the reason the check above is not enough.
  --
  -- `~/.config/nvim` is a symlink into a dotfiles repo on a very large share
  -- of real setups. `stdpath("config")` reports that symlink verbatim; the
  -- directory this resolver is handed comes from a buffer name, and Unix
  -- Neovim canonicalizes a path on the way in -- the same canonicalization
  -- that made fifteen cases fail on the macOS runner over `/var` against
  -- `/private/var` (d6b5b62). So the two arrive spelled differently, a plain
  -- string compare answers false, and "the config directory is a root of its
  -- own" silently stops being true for precisely the people whose config is
  -- version-controlled -- lua_ls gets the whole dotfiles repo instead.
  --
  -- The resolved spelling is passed as a filename rather than opened as a
  -- buffer on purpose. On Unix a buffer produces exactly this; on Windows --
  -- measured, not assumed -- `nvim_buf_get_name` keeps the link spelling and
  -- there would be nothing to test. Handing the resolver the spelling a Unix
  -- buffer yields pins the contract itself, identically wherever a symlink can
  -- be made at all.
  it("roots at the config directory when stdpath('config') is a symlink", function()
    with_symlinked_config(function(link, resolved, repo)
      with_stdpath_config(link, function()
        for _, scope in ipairs({ "git", "cwd", "path" }) do
          root_scope.set(scope)
          local root = norm(resolve(resolved .. "/lua/plugins/init.lua"))

          assert.are_not.equal(norm(repo), root, "rooted at the dotfiles repo, scope=" .. scope)
          assert.are.equal(norm(resolved), root, "scope=" .. scope)
        end
      end)
    end)
  end)

  -- A root has to be a prefix of the file it is a root *for*. Returning the raw
  -- `stdpath("config")` would satisfy "did the config-directory rule fire"
  -- while handing lua_ls a workspace the buffer is not inside -- which is worse
  -- than the miss it replaces. Measured against a real lua-language-server: it
  -- indexes the tree through the symlink and answers textDocument/definition
  -- with the *other* spelling, so jumping to a definition opens a second
  -- buffer on a file that is already open.
  it("returns a config spelling that is a prefix of the file's own path", function()
    with_symlinked_config(function(link, resolved)
      with_stdpath_config(link, function()
        local file = norm(resolved .. "/lua/plugins/init.lua")
        local root = norm(resolve(file))

        assert.are.equal(root, file:sub(1, #root), "root is not a prefix of " .. file)
      end)
    end)
  end)

  -- The other direction, and the regression guard on the fix: a directory
  -- already spelled the way `stdpath("config")` spells it must still resolve to
  -- exactly that value. Canonicalizing unconditionally would quietly rewrite
  -- the root for every setup that never had this problem.
  it("still returns stdpath('config') verbatim for a path spelled that way", function()
    with_symlinked_config(function(link)
      with_stdpath_config(link, function()
        assert.are.equal(link, resolve(link .. "/lua/plugins/init.lua"))
      end)
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
