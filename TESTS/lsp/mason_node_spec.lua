--- Covers `lsp.core.mason_node`: resolving a Mason-installed Node server to a
--- direct `node <entry>` command by parsing npm's generated `.bin/<name>.cmd`
--- shim, and the Windows-only gate around it. The module header explains why
--- this exists at all -- Neovim cannot reap a grandchild through `cmd.exe` on
--- Windows, which hangs `:qa` -- so what is worth pinning here is that the
--- parser resolves the entry point it is documented to resolve, degrades to
--- `nil` on anything it does not recognize (a caller then keeps its previous
--- command; a failed parse must never cost more than the fix), and does the
--- backslash-to-forward-slash conversion Windows shim paths need.
---
--- `vim.fn.stdpath("data")` is redirected to a throwaway temp directory for
--- every case, so this never reads or writes the machine's real Mason
--- install. `vim.fn.has("win32")` is stubbed the same way the rest of the
--- suite stubs `vim.fn.executable`, so the Windows-only gate is exercised on
--- every platform this suite runs on, not just Windows.

local mason_node = require("lsp.core.mason_node")

---@param overrides table<string, integer>
---@param fn fun(): nil
local function with_has(overrides, fn)
  local orig = vim.fn.has
  vim.fn.has = function(feature)
    if overrides[feature] ~= nil then
      return overrides[feature]
    end
    return orig(feature)
  end
  local ok, err = pcall(fn)
  vim.fn.has = orig
  assert(ok, err)
end

---@param fn fun(datadir: string): nil
local function with_data_dir(fn)
  local datadir = vim.fn.tempname()
  vim.fn.mkdir(datadir, "p")
  local orig = vim.fn.stdpath
  vim.fn.stdpath = function(what)
    if what == "data" then
      return datadir
    end
    return orig(what)
  end
  local ok, err = pcall(fn, datadir)
  vim.fn.stdpath = orig
  pcall(vim.fn.delete, datadir, "rf")
  assert(ok, err)
end

---@param datadir string
---@param pkg string
---@return string bin_dir
local function make_bin_dir(datadir, pkg)
  local bin_dir = datadir .. "/mason/packages/" .. pkg .. "/node_modules/.bin"
  vim.fn.mkdir(bin_dir, "p")
  return bin_dir
end

---@param bin_dir string
---@param bin_name string
---@param lines string[]
local function write_shim(bin_dir, bin_name, lines)
  vim.fn.writefile(lines, bin_dir .. "/" .. bin_name .. ".cmd")
end

--- A real shim line shaped like npm's generated `.bin/<name>.cmd`, pointing
--- (via `%dp0%\..\...`) at `<node_modules>/<rel>`.
---@param rel string  # backslash-separated, relative to node_modules
---@return string
local function shim_line(rel)
  return ('"%%_prog%%"  "%%dp0%%\\..\\%s" %%*'):format(rel)
end

describe("lsp.core.mason_node", function()
  describe("off Windows", function()
    it("M.cmd always returns nil, even with a resolvable shim present", function()
      with_has({ win32 = 0 }, function()
        with_data_dir(function(datadir)
          local bin_dir = make_bin_dir(datadir, "tailwindcss-language-server")
          vim.fn.mkdir(
            datadir .. "/mason/packages/tailwindcss-language-server/node_modules/pkg/bin",
            "p"
          )
          vim.fn.writefile(
            { "x" },
            datadir .. "/mason/packages/tailwindcss-language-server/node_modules/pkg/bin/entry.js"
          )
          write_shim(bin_dir, "tailwindcss-language-server", { shim_line("pkg\\bin\\entry.js") })

          assert.is_nil(mason_node.cmd("tailwindcss-language-server"))
        end)
      end)
    end)

    it("M.cmd_or falls back to the caller's command", function()
      with_has({ win32 = 0 }, function()
        with_data_dir(function()
          assert.are.same(
            { "tailwindcss-language-server", "--stdio" },
            mason_node.cmd_or(
              "tailwindcss-language-server",
              { "tailwindcss-language-server", "--stdio" }
            )
          )
        end)
      end)
    end)
  end)

  describe("on Windows", function()
    it("returns nil when the package is not installed at all", function()
      with_has({ win32 = 1 }, function()
        with_data_dir(function()
          assert.is_nil(mason_node.cmd("not-installed-pkg"))
        end)
      end)
    end)

    it("returns nil when the .bin shim file itself is missing", function()
      with_has({ win32 = 1 }, function()
        with_data_dir(function(datadir)
          make_bin_dir(datadir, "some-pkg")
          -- Directory exists, but no `some-pkg.cmd` was ever written into it.
          assert.is_nil(mason_node.cmd("some-pkg"))
        end)
      end)
    end)

    it("returns nil when no line in the shim matches the %dp0% shape", function()
      with_has({ win32 = 1 }, function()
        with_data_dir(function(datadir)
          local bin_dir = make_bin_dir(datadir, "some-pkg")
          write_shim(bin_dir, "some-pkg", { "@ECHO OFF", "REM not an npm-generated shim" })

          assert.is_nil(mason_node.cmd("some-pkg"))
        end)
      end)
    end)

    it("returns nil when the matched entry does not exist on disk", function()
      with_has({ win32 = 1 }, function()
        with_data_dir(function(datadir)
          local bin_dir = make_bin_dir(datadir, "some-pkg")
          write_shim(bin_dir, "some-pkg", { shim_line("some-pkg\\bin\\missing.js") })
          -- Deliberately not creating node_modules/some-pkg/bin/missing.js.

          assert.is_nil(mason_node.cmd("some-pkg"))
        end)
      end)
    end)

    -- The Windows-specific risk: a `\`-separated shim path must resolve to a
    -- real file via a `/`-normalized comparison, not silently fail because
    -- the separators never matched.
    it("resolves a real entry and normalizes backslashes to forward slashes", function()
      with_has({ win32 = 1 }, function()
        with_data_dir(function(datadir)
          local pkg = "tailwindcss-language-server"
          local bin_dir = make_bin_dir(datadir, pkg)
          local target_dir = datadir .. "/mason/packages/" .. pkg .. "/node_modules/@tw/pkg/bin"
          vim.fn.mkdir(target_dir, "p")
          vim.fn.writefile({ "#!/usr/bin/env node" }, target_dir .. "/entry.js")
          write_shim(bin_dir, pkg, { shim_line("@tw\\pkg\\bin\\entry.js") })

          local cmd = mason_node.cmd(pkg)

          assert.is_not_nil(cmd)
          assert.are.equal("node", cmd[1])
          assert.is_nil(
            cmd[2]:find("\\", 1, true),
            "entry path still contains a backslash: " .. cmd[2]
          )
          assert.is_truthy(cmd[2]:find("@tw/pkg/bin/entry%.js$"))
        end)
      end)
    end)

    it("defaults bin_name to the package name", function()
      with_has({ win32 = 1 }, function()
        with_data_dir(function(datadir)
          local pkg = "marksman"
          local bin_dir = make_bin_dir(datadir, pkg)
          local target_dir = datadir .. "/mason/packages/" .. pkg .. "/node_modules/marksman/bin"
          vim.fn.mkdir(target_dir, "p")
          vim.fn.writefile({ "x" }, target_dir .. "/entry.js")
          -- Written under the package name, i.e. what bin_name defaults to.
          write_shim(bin_dir, pkg, { shim_line("marksman\\bin\\entry.js") })

          assert.is_not_nil(mason_node.cmd(pkg))
        end)
      end)
    end)

    it("uses an explicit bin_name distinct from the package name", function()
      with_has({ win32 = 1 }, function()
        with_data_dir(function(datadir)
          local pkg = "some-pkg"
          local bin_dir = make_bin_dir(datadir, pkg)
          local target_dir = datadir .. "/mason/packages/" .. pkg .. "/node_modules/inner/bin"
          vim.fn.mkdir(target_dir, "p")
          vim.fn.writefile({ "x" }, target_dir .. "/entry.js")
          write_shim(bin_dir, "actual-binary", { shim_line("inner\\bin\\entry.js") })

          assert.is_nil(mason_node.cmd(pkg, "wrong-name"))
          assert.is_not_nil(mason_node.cmd(pkg, "actual-binary"))
        end)
      end)
    end)

    describe("M.cmd_or", function()
      it("appends args to a resolved direct command", function()
        with_has({ win32 = 1 }, function()
          with_data_dir(function(datadir)
            local pkg = "some-pkg"
            local bin_dir = make_bin_dir(datadir, pkg)
            local target_dir = datadir .. "/mason/packages/" .. pkg .. "/node_modules/inner/bin"
            vim.fn.mkdir(target_dir, "p")
            vim.fn.writefile({ "x" }, target_dir .. "/entry.js")
            write_shim(bin_dir, pkg, { shim_line("inner\\bin\\entry.js") })

            local cmd = mason_node.cmd_or(pkg, { "fallback" }, { "--stdio" })

            assert.are.equal("node", cmd[1])
            assert.are.equal("--stdio", cmd[#cmd])
          end)
        end)
      end)

      it("falls back to the caller's command when resolution fails", function()
        with_has({ win32 = 1 }, function()
          with_data_dir(function()
            assert.are.same(
              { "fallback", "--stdio" },
              mason_node.cmd_or("nowhere", { "fallback", "--stdio" })
            )
          end)
        end)
      end)
    end)
  end)
end)
