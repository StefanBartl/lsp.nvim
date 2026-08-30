--- Covers `lsp.core.workspace_folders`: the capability gate, the client
--- attribution, and the candidate discovery.
---
--- Everything here runs against stubbed clients. That is not a compromise --
--- the three things this module exists to add to Neovim's builtins (a gate on
--- `changeNotifications`, per-client attribution, no duplicate sent to the
--- wire) are all decisions made *before* a byte reaches a server, so a real
--- server would test nothing extra and would make the capability matrix
--- untestable: no single server declares all four combinations.
---
--- The candidate cases build a real directory tree under a temp dir, because
--- the upward walk and the sibling scan are filesystem behaviour and stubbing
--- `vim.fs` would only assert that the stub was called.

local uv = vim.uv or vim.loop

---@param path string
local function mkdir(path)
  vim.fn.mkdir(path, "p")
end

---@param path string
local function touch(path)
  local fd = assert(uv.fs_open(path, "w", 420))
  uv.fs_close(fd)
end

--- A stub client shaped like the parts `workspace_folders` reads.
---@param opts table
---@return table
local function client(opts)
  local folders = {}
  for _, name in ipairs(opts.folders or {}) do
    folders[#folders + 1] = { name = name, uri = "file://" .. name }
  end

  return {
    id = opts.id or 1,
    name = opts.name or "stub",
    root_dir = opts.root,
    workspace_folders = folders,
    server_capabilities = opts.caps or {
      workspace = { workspaceFolders = { supported = true, changeNotifications = true } },
    },
    _added = {},
    _removed = {},
    _add_workspace_folder = function(self, dir)
      if opts.reject then
        error("nope")
      end
      self._added[#self._added + 1] = dir
      self.workspace_folders[#self.workspace_folders + 1] = { name = dir, uri = "file://" .. dir }
    end,
    _remove_workspace_folder = function(self, dir)
      if opts.reject then
        error("nope")
      end
      self._removed[#self._removed + 1] = dir
      for i, folder in ipairs(self.workspace_folders) do
        if folder.name == dir then
          table.remove(self.workspace_folders, i)
          break
        end
      end
    end,
  }
end

describe("lsp.core.workspace_folders", function()
  local saved = {}
  ---@type table[]
  local clients = {}

  ---@return table
  local function reload()
    package.loaded["lsp.core.workspace_folders"] = nil
    return require("lsp.core.workspace_folders")
  end

  before_each(function()
    saved.get_clients = vim.lsp.get_clients
    saved.config = package.loaded["lsp.config"]
    clients = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.get_clients = function()
      return clients
    end
  end)

  after_each(function()
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.get_clients = saved.get_clients
    package.loaded["lsp.config"] = saved.config
    package.loaded["lsp.core.workspace_folders"] = nil
  end)

  describe("the capability gate", function()
    it("takes a server that supports folders and wants change notifications", function()
      clients = { client({ name = "gopls" }) }
      local ws = reload()

      local ok, added, skipped = ws.add(vim.fn.getcwd())
      assert.is_true(ok)
      assert.are.same({ "gopls" }, added)
      assert.are.same({}, skipped)
    end)

    it("skips a server that supports folders but never asked to hear about changes", function()
      -- The distinction Neovim's builtin does not make: `supported` licenses
      -- folders at initialize, `changeNotifications` licenses them at runtime.
      clients = {
        client({
          name = "quiet",
          caps = { workspace = { workspaceFolders = { supported = true } } },
        }),
      }
      local ws = reload()

      local ok, added, skipped = ws.add(vim.fn.getcwd())
      assert.is_false(ok)
      assert.are.same({}, added)
      assert.are.equal(1, #skipped)
      assert.is_truthy(skipped[1]:match("didChangeWorkspaceFolders"))
    end)

    it("skips a server that declares no workspaceFolders support at all", function()
      clients = { client({ name = "bare", caps = {} }) }
      local ws = reload()

      local ok, _, skipped = ws.add(vim.fn.getcwd())
      assert.is_false(ok)
      assert.is_truthy(skipped[1]:match("no workspaceFolders support"))
    end)

    it("names the unswitchable clients in the report instead of hiding them", function()
      clients = {
        client({ id = 1, name = "gopls", root = "/repo" }),
        client({ id = 2, name = "bare", root = "/repo", caps = {} }),
      }
      local ws = reload()

      local entries = ws.clients()
      assert.are.equal(2, #entries)

      local by_name = {}
      for _, entry in ipairs(entries) do
        by_name[entry.name] = entry
      end
      assert.is_true(by_name.gopls.switchable)
      assert.is_false(by_name.bare.switchable)
      assert.is_string(by_name.bare.reason)
    end)
  end)

  describe("adding", function()
    it("never sends a duplicate to the wire", function()
      -- Neovim answers a duplicate with a bare `print()`; the point of
      -- resolving it here is that nothing is notified and the caller is told.
      local c = client({ name = "gopls", folders = { vim.fn.getcwd() } })
      clients = { c }
      local ws = reload()

      local ok, added, skipped = ws.add(vim.fn.getcwd())
      assert.is_false(ok)
      assert.are.same({}, added)
      assert.are.equal(0, #c._added)
      assert.is_truthy(skipped[1]:match("already a workspace folder"))
    end)

    it("refuses a path that is not a directory", function()
      clients = { client({ name = "gopls" }) }
      local ws = reload()

      local ok, _, skipped = ws.add(vim.fn.getcwd() .. "/definitely-not-here")
      assert.is_false(ok)
      assert.is_truthy(skipped[1]:match("not a directory"))
    end)

    it("keeps one throwing client from costing the others their folder", function()
      local good = client({ id = 1, name = "gopls" })
      clients = { good, client({ id = 2, name = "angry", reject = true }) }
      local ws = reload()

      local ok, added, skipped = ws.add(vim.fn.getcwd())
      assert.is_true(ok)
      assert.are.same({ "gopls" }, added)
      assert.are.equal(1, #skipped)
      assert.are.equal(1, #good._added)
    end)
  end)

  describe("removing", function()
    it("hands the client back its own spelling of the path", function()
      -- The client stores what it was given; `Client:_remove_workspace_folder`
      -- matches `folder.name == dir` literally. Handing it the normalized
      -- spelling would notify the server and then leave the entry in place.
      local raw = vim.fn.getcwd() .. "\\sub"
      local c = client({ name = "gopls", folders = { raw } })
      clients = { c }
      local ws = reload()

      local normalized = vim.fs.normalize(raw)
      local ok, removed = ws.remove(normalized)
      assert.is_true(ok)
      assert.are.same({ "gopls" }, removed)
      assert.are.same({ raw }, c._removed)
      assert.are.equal(0, #c.workspace_folders)
    end)

    it("stays quiet about clients that never held the folder", function()
      clients = {
        client({ id = 1, name = "holder", folders = { vim.fn.getcwd() } }),
        client({ id = 2, name = "bystander" }),
      }
      local ws = reload()

      local ok, removed, skipped = ws.remove(vim.fn.getcwd())
      assert.is_true(ok)
      assert.are.same({ "holder" }, removed)
      assert.are.same({}, skipped)
    end)
  end)

  describe("listing", function()
    it("deduplicates a shared folder and records both clients", function()
      local shared = vim.fs.normalize(vim.fn.getcwd())
      clients = {
        client({ id = 1, name = "gopls", folders = { shared } }),
        client({ id = 2, name = "ts_ls", folders = { shared } }),
      }
      local ws = reload()

      local folders = ws.folders()
      assert.are.equal(1, #folders)
      assert.are.equal(shared, folders[1].path)
      assert.are.same({ "gopls", "ts_ls" }, folders[1].clients)
    end)
  end)

  describe("candidate discovery", function()
    ---@type string
    local root
    ---@type integer
    local bufnr

    ---@param markers string[]|nil
    ---@param containers string[]|nil
    local function with_config(markers, containers)
      package.loaded["lsp.config"] = {
        get = function()
          return {
            workspace = {
              markers = markers or { ".git", "go.mod" },
              containers = containers or { "packages" },
            },
          }
        end,
      }
    end

    before_each(function()
      root = vim.fs.normalize(vim.fn.tempname())
      -- A monorepo: a VCS root, one package the buffer lives in, one sibling
      -- it does not, and a directory with no marker that must not be offered.
      mkdir(root .. "/.git")
      mkdir(root .. "/packages/api")
      mkdir(root .. "/packages/web")
      mkdir(root .. "/packages/scratch")
      touch(root .. "/go.mod")
      touch(root .. "/packages/api/go.mod")
      touch(root .. "/packages/web/go.mod")

      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, root .. "/packages/api/main.go")
    end)

    after_each(function()
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
      vim.fn.delete(root, "rf")
    end)

    it("walks upward and puts the nearest project first", function()
      with_config()
      local ws = reload()

      local candidates = ws.candidates(bufnr)
      assert.are.equal(root .. "/packages/api", candidates[1])
      assert.is_true(vim.tbl_contains(candidates, root))
    end)

    it("finds the sibling package an upward walk cannot see", function()
      with_config()
      local ws = reload()

      -- The whole reason the sibling scan exists: from `packages/api`,
      -- `packages/web` is never above you.
      assert.is_true(vim.tbl_contains(ws.candidates(bufnr), root .. "/packages/web"))
    end)

    it("leaves out a directory with no marker", function()
      with_config()
      local ws = reload()

      assert.is_false(vim.tbl_contains(ws.candidates(bufnr), root .. "/packages/scratch"))
    end)

    it("descends only through the configured container names", function()
      with_config({ ".git", "go.mod" }, {})
      local ws = reload()

      local candidates = ws.candidates(bufnr)
      -- `packages` itself carries no marker, so with no containers configured
      -- nothing below it is reachable from the root scan.
      assert.is_false(vim.tbl_contains(candidates, root .. "/packages/web"))
      -- The upward walk is untouched by that: the buffer's own package and the
      -- repo root are still there.
      assert.is_true(vim.tbl_contains(candidates, root .. "/packages/api"))
    end)

    it("leaves out what is already a workspace folder", function()
      with_config()
      clients = { client({ name = "gopls", folders = { root .. "/packages/api" } }) }
      local ws = reload()

      local candidates = ws.candidates(bufnr)
      assert.is_false(vim.tbl_contains(candidates, root .. "/packages/api"))
      assert.is_true(vim.tbl_contains(candidates, root .. "/packages/web"))
    end)

    it("offers nothing but the cwd when every marker is configured away", function()
      with_config({}, {})
      local ws = reload()

      local candidates = ws.candidates(bufnr)
      assert.are.same({ vim.fs.normalize(vim.fn.getcwd()) }, candidates)
    end)
  end)
end)
