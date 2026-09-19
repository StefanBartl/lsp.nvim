--- Regression cases for the `lua_ls` library/scan subsystem.
---
--- Every case here was written against the *broken* version of the file it
--- covers and observed to fail there; the numbers in each comment are what the
--- old code actually produced on this machine, not what it looked like it
--- would produce.
---
--- Four defects are covered:
---
--- * `find_type_dirs` checked `#matches < MAX_RESULTS` only when popping a
---   node, so one directory's worth of matches was appended unbounded --
---   `max_results = 10` returned 500 paths.
--- * `find_type_dirs` popped with `table.remove(stack)`, i.e. depth-first,
---   while the README calls it BFS. Invisible until the cap held; under a
---   cap it decides which directories make the budget.
--- * `library_profiles.build_runtime_library` omitted
---   `${3rd}/luassert/library`, and that function -- not `build_library` --
---   is what `init.lua`'s `before_init` installs, so no running server ever
---   saw luassert.
--- * `ignore` seeded itself from the shared list's `as_luals_patterns()`
---   instead of its `basenames`, so every "basename" was present twice, once
---   as `name` and once as `**/name`.

local uv = vim.uv or vim.loop

describe("lsp.servers.lua_ls", function()
  ---@type string[]
  local tmpdirs = {}

  --- Create a throwaway directory tree and remember it for teardown.
  ---@param dirs string[] # directories to create, relative to the new root
  ---@param files string[] # files to create, relative to the new root
  ---@return string root
  local function tree(dirs, files)
    local root = vim.fn.tempname()
    tmpdirs[#tmpdirs + 1] = root
    vim.fn.mkdir(root, "p")
    for _, d in ipairs(dirs) do
      vim.fn.mkdir(root .. "/" .. d, "p")
    end
    for _, f in ipairs(files) do
      local dir = vim.fs.dirname(root .. "/" .. f)
      vim.fn.mkdir(dir, "p")
      local fh = assert(io.open(root .. "/" .. f, "w"))
      fh:write("return {}\n")
      fh:close()
    end
    return root
  end

  ---@return fun(root: string, opts: table|nil): string[]
  local function find_type_dirs()
    package.loaded["lsp.servers.lua_ls.find_type_dirs"] = nil
    return require("lsp.servers.lua_ls.find_type_dirs")
  end

  after_each(function()
    for _, d in ipairs(tmpdirs) do
      vim.fn.delete(d, "rf")
    end
    tmpdirs = {}
  end)

  describe("find_type_dirs: max_results", function()
    it("stops at max_results when one directory holds more matches than the cap", function()
      -- The whole point: 500 matching directories are siblings, so they are
      -- all appended during a single pass of the inner scandir loop. The old
      -- outer-loop-only check never ran between them and returned all 500 for
      -- `max_results = 10` -- a 50x overshoot handed to lua_ls as
      -- `workspace.library`.
      local dirs, files = {}, {}
      for i = 1, 500 do
        dirs[i] = string.format("plugin%03dtypes", i)
        files[i] = string.format("plugin%03dtypes/a.lua", i)
      end
      local root = tree(dirs, files)

      local found = find_type_dirs()(root, { max_results = 10, max_depth = 15 })
      assert.are.equal(10, #found)
    end)

    it("stops at max_results when the matches are standalone type files", function()
      -- The file branch had the same hole. A directory can hold at most two
      -- matching files, so the overshoot is small -- but it is an overshoot:
      -- the old code returned both for `max_results = 1`.
      local root = tree({}, { "types.lua", "@types.lua" })

      assert.are.equal(1, #find_type_dirs()(root, { max_results = 1, max_depth = 15 }))
    end)
  end)

  describe("find_type_dirs: traversal order", function()
    it("spends a tight budget on the shallow type dir, not the deep one", function()
      -- `aaa/types` sits at depth 1, `zzz/a/b/c/types` at depth 4. Depth-first
      -- with a LIFO stack reached the deep one first, so `max_results = 1`
      -- returned `zzz/a/b/c/types` and dropped `aaa/types` entirely. A
      -- vendored subtree four levels down must not spend the budget before
      -- `<root>/lua/types` has been looked at.
      local root = tree({}, { "aaa/types/x.lua", "zzz/a/b/c/types/x.lua" })

      local found = find_type_dirs()(root, { max_results = 1, max_depth = 15 })
      assert.are.equal(1, #found)
      assert.is_truthy(found[1]:match("aaa/types$"))
    end)

    it("returns shallow matches before deep ones when the budget is ample", function()
      local root = tree({}, { "aaa/types/x.lua", "zzz/a/b/c/types/x.lua" })

      local found = find_type_dirs()(root, { max_results = 99, max_depth = 15 })
      assert.are.equal(2, #found)
      assert.is_truthy(found[1]:match("aaa/types$"))
      assert.is_truthy(found[2]:match("c/types$"))
    end)
  end)

  describe("find_type_dirs: ignore list", function()
    it("still skips ignored directories after the ignore rework", function()
      -- Guard on the `ignore._names` change rather than a bug of its own: the
      -- set used to carry both `node_modules` and `**/node_modules`, and only
      -- the first of those can ever equal a basename. Dropping the dead half
      -- must not drop the live one.
      local root = tree({}, { "node_modules/types/x.lua", "lua/types/x.lua" })

      local found = find_type_dirs()(root, { max_results = 50, max_depth = 5 })
      assert.are.equal(1, #found)
      assert.is_truthy(found[1]:match("lua/types$"))
    end)
  end)

  describe("ignore", function()
    ---@return table
    local function ignore()
      package.loaded["lsp.servers.lua_ls.ignore"] = nil
      return require("lsp.servers.lua_ls.ignore")
    end

    it("names() returns basenames, not glob patterns", function()
      -- Measured on the old code: 62 entries, 31 of them `**/name`, against a
      -- docstring promising "raw directory basenames for path-level checks".
      local names = ignore().names()
      assert.is_true(#names > 0)
      for _, n in ipairs(names) do
        assert.is_nil(n:find("*", 1, true), "not a basename: " .. n)
      end
    end)

    it("as_set() has no key a basename could never match", function()
      local set = ignore().as_set()
      assert.is_true(set["node_modules"])
      assert.is_true(set[".git"])
      for k in pairs(set) do
        assert.is_nil(k:find("*", 1, true), "unmatchable set key: " .. k)
      end
    end)

    it("as_luals_patterns() emits each pattern once and never nests `**/`", function()
      -- Old code: 124 patterns for 31 directories -- 31 exact duplicates and
      -- 31 `**/**/name`, because it doubled a list that was already doubled.
      local patterns = ignore().as_luals_patterns()
      local seen = {}
      for _, p in ipairs(patterns) do
        assert.is_nil(seen[p], "duplicate pattern: " .. p)
        assert.is_nil(p:match("^%*%*/%*%*/"), "nested glob: " .. p)
        seen[p] = true
      end
      -- Exactly the two documented spellings per name, nothing more.
      assert.are.equal(#ignore().names() * 2, #patterns)
    end)
  end)

  describe("build_runtime_library", function()
    it("carries luassert, which is the list a server actually receives", function()
      -- `build_library.lua` has had this entry (and the note explaining why)
      -- for a while, but it is not on the startup path: `before_init` calls
      -- `build_runtime_library`. Measured against a real
      -- `lua-language-server` before the fix: the client's
      -- `settings.Lua.workspace.library` held three entries and no luassert,
      -- hover on `assert.are.equal` resolved to the Lua stdlib `assert`, and
      -- the server asked "Do you need to configure your work environment as
      -- `luassert`?".
      package.loaded["lsp.servers.lua_ls.library_profiles"] = nil
      local library = require("lsp.servers.lua_ls.library_profiles").build_runtime_library()
      assert.is_true(vim.tbl_contains(library, "${3rd}/luassert/library"))
    end)

    it("reaches the server config through before_init", function()
      -- The wiring half of the same defect. Capture what `setup` registers
      -- and run its `before_init` the way `vim.lsp` would.
      local saved_config = vim.lsp.config
      local saved_reload = package.loaded["lsp.servers.lua_ls.reload"]
      -- `reload.setup` registers user commands and autocommands; stub it so
      -- the case stays a pure inspection of the registered config.
      package.loaded["lsp.servers.lua_ls.reload"] = { setup = function() end }

      local registered
      ---@diagnostic disable-next-line: assign-type-mismatch
      vim.lsp.config = setmetatable({}, {
        __call = function(_, _, cfg)
          registered = cfg
        end,
      })

      local ok, err = pcall(function()
        package.loaded["lsp.servers.lua_ls"] = nil
        package.loaded["lsp.servers.lua_ls.init"] = nil
        require("lsp.servers.lua_ls").setup({}, { enable = false })
      end)

      vim.lsp.config = saved_config
      package.loaded["lsp.servers.lua_ls.reload"] = saved_reload
      assert.is_true(ok, tostring(err))
      assert.is_table(registered)

      local config = { settings = vim.deepcopy(registered.settings) }
      registered.before_init({}, config)
      local library = vim.tbl_get(config, "settings", "Lua", "workspace", "library")

      assert.is_table(library)
      assert.is_true(vim.tbl_contains(library, "${3rd}/luassert/library"))
      assert.is_true(vim.tbl_contains(library, "${3rd}/luv/library"))
      assert.is_true(vim.tbl_contains(library, "${3rd}/busted/library"))
    end)
  end)

  describe("debug", function()
    ---@return table
    local function debug_mod()
      package.loaded["lsp.servers.lua_ls.debug"] = nil
      return require("lsp.servers.lua_ls.debug")
    end

    it("reports the root the server actually uses", function()
      -- `debug` carried its own copy of the root algorithm, and the copy had
      -- drifted from the resolver `lua_ls` is registered with in two ways.
      --
      -- One is the `<leader>lsp` root-scope switch, which the copy knew
      -- nothing about: under scope "cwd" the resolver returns the working
      -- directory and the copy still returned the repo root, so every root
      -- this module printed was wrong for as long as the switch was off
      -- "git". That is what this case pins, because it needs nothing but a
      -- repo in a temp dir.
      --
      -- The other was ordering: the copy tried VCS markers before the
      -- `stdpath("config")` check, where the resolver does the config check
      -- first and says so. Measured with `stdpath("config")` pointed at a
      -- fixture holding a nested repo at `<config>/lua/vendor/plug/.git`:
      -- resolver `<config>`, this module `<config>/lua/vendor/plug`. Not
      -- covered here -- `stdpath` is fixed for the process and the only way
      -- to move it is an env var at startup.
      local root = tree({ ".git" }, { "lua/a.lua" })
      local bufnr = vim.fn.bufadd(root .. "/lua/a.lua")
      vim.fn.bufload(bufnr)

      local root_scope = require("lsp.core.root_scope")
      local restore = root_scope.get()
      root_scope.set("cwd")

      local expected = require("lsp.servers.lua_ls.rootresolver")(bufnr)
      local reported = debug_mod().root_for_buf(bufnr)

      root_scope.set(restore)
      vim.api.nvim_buf_delete(bufnr, { force = true })

      assert.are.equal(expected, reported)
      -- Guard against the assertion passing because both sides went wrong the
      -- same way: under scope "cwd" the answer is the working directory, not
      -- the repo the file sits in.
      assert.are_not.equal(vim.fs.normalize(root), vim.fs.normalize(reported))
    end)

    it("debug_library returns the array it is annotated to return", function()
      -- `build_library` hands back a `{ [path] = true }` map and this passed it
      -- through unchanged: measured on this repo, 22 keys and an array length
      -- of 0, so `#libs` was 0 and `ipairs(libs)` yielded nothing.
      local library = debug_mod().debug_library(vim.fn.getcwd())

      assert.is_true(#library > 0)
      assert.is_string(library[1])
      for _, path in ipairs(library) do
        assert.is_string(path)
      end
      -- Sorted, so a dump of it can be diffed between runs.
      local sorted = vim.deepcopy(library)
      table.sort(sorted)
      assert.are.same(sorted, library)
    end)
  end)

  describe("find_type_dirs: paths the platform can produce", function()
    it("handles a root with a space and a trailing separator identically", function()
      -- Windows: `norm` is the only thing keeping `node.path .. pathsep ..
      -- name` from producing mixed separators, and the machine's own plugin
      -- tree lives under "AppData\\Local". A space is the other half of the
      -- same question ("C:/Program Files/...").
      local base = tree({}, { "with space/lua/types/x.lua" })
      local root = base .. "/with space"

      local plain = find_type_dirs()(root, { max_results = 50, max_depth = 5 })
      local trailing = find_type_dirs()(root .. "/", { max_results = 50, max_depth = 5 })
      local backslash =
        find_type_dirs()((root:gsub("/", "\\")), { max_results = 50, max_depth = 5 })

      assert.are.equal(1, #plain)
      assert.are.same(plain, trailing)
      assert.are.same(plain, backslash)
      assert.is_truthy(uv.fs_stat(plain[1]))
    end)
  end)

  describe("build_library: profile-gated (LLS-31)", function()
    -- `build_library.lua` used to hardcode `max_results = 200, max_depth =
    -- 15, include_files = true` -- the "full" profile's own numbers --
    -- regardless of `LUA_LS_PROFILE`, so `:LuaLsSetProfile`/`reload_library`
    -- ran the identical unbounded scan under every profile name.
    local saved_env

    ---@return fun(root: string): table<string, boolean>
    local function build_library()
      package.loaded["lsp.servers.lua_ls.library_profiles"] = nil
      package.loaded["lsp.servers.lua_ls.build_library"] = nil
      return require("lsp.servers.lua_ls.build_library")
    end

    before_each(function()
      saved_env = vim.env.LUA_LS_PROFILE
    end)

    after_each(function()
      vim.env.LUA_LS_PROFILE = saved_env
    end)

    it("caps find_type_dirs results at the active profile's max_results", function()
      local dirs, files = {}, {}
      for i = 1, 80 do
        dirs[i] = string.format("plugin%03dtypes", i)
        files[i] = string.format("plugin%03dtypes/a.lua", i)
      end
      local root = tree(dirs, files)

      vim.env.LUA_LS_PROFILE = "minimal"
      local minimal_count = 0
      for path in pairs(build_library()(root)) do
        if path:match("plugin%d%d%dtypes$") then
          minimal_count = minimal_count + 1
        end
      end

      vim.env.LUA_LS_PROFILE = "full"
      local full_count = 0
      for path in pairs(build_library()(root)) do
        if path:match("plugin%d%d%dtypes$") then
          full_count = full_count + 1
        end
      end

      -- "minimal" caps at 50 results (which this fixture's 80 matches
      -- exceed); "full" caps at 200, well above the fixture's size.
      assert.are.equal(50, minimal_count)
      assert.are.equal(80, full_count)
    end)

    it("only includes local deps/vendor dirs under a profile that wants them", function()
      local root = tree({ "vendor" }, {})

      vim.env.LUA_LS_PROFILE = "minimal"
      assert.is_nil(build_library()(root)[root .. "/vendor"], "minimal must not scan local deps")

      vim.env.LUA_LS_PROFILE = "normal"
      assert.is_true(
        build_library()(root)[root .. "/vendor"] == true,
        "normal must include local deps"
      )
    end)
  end)
end)
