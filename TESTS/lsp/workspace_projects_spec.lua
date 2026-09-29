--- Covers `lsp.core.workspace_projects`: per-project overrides for
--- workspace-wide diagnostics, and the two places they take effect -- the
--- populate in `lsp.core.workspace_diagnostics` and the `publishDiagnostics`
--- wrapper in `lsp.core.handlers`.
---
--- The publish half is the reason this module exists. Measured on a 897-file
--- Markdown vault, marksman pushed ten warnings for ten files with a single
--- buffer open, identically with and without the populate -- so an override
--- that only stopped the populate would have looked implemented and changed
--- nothing. The handler cases below therefore assert on what Neovim's own
--- handler would have *rendered*, not on which function was called.

local uv = vim.uv or vim.loop

---@param path string
---@param text string
local function write_file(path, text)
  local fd = assert(uv.fs_open(path, "w", 420))
  uv.fs_write(fd, text)
  uv.fs_close(fd)
end

--- An in-process LSP client that records every notification it is sent.
---@param opts { name: string, filetypes?: string[], root: string, bufnr: integer, sink: table[] }
---@return integer|nil client_id
local function start_stub(opts)
  return vim.lsp.start({
    name = opts.name,
    cmd = function(dispatchers)
      local closing = false
      return {
        request = function(method, _params, cb)
          cb(nil, method == "initialize" and { capabilities = { textDocumentSync = 1 } } or nil)
          return true, 1
        end,
        notify = function(method, params)
          opts.sink[#opts.sink + 1] = { client = opts.name, method = method, params = params }
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
    root_dir = opts.root,
    filetypes = opts.filetypes,
  }, { bufnr = opts.bufnr, attach = true })
end

---@param sink table[]
---@param name string
---@return table<string, true>
local function opened_by(sink, name)
  local out = {}
  for _, entry in ipairs(sink) do
    if entry.client == name and entry.method == "textDocument/didOpen" then
      out[vim.fs.normalize(vim.uri_to_fname(entry.params.textDocument.uri))] = true
    end
  end
  return out
end

---@param path string
---@return integer bufnr
local function open_buf(path)
  local bufnr = vim.fn.bufadd(path)
  vim.fn.bufload(bufnr)
  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

describe("lsp.core.workspace_projects", function()
  ---@type string
  local tmp
  ---@type string
  local vault, plugin
  ---@type table
  local projects

  --- Fresh module state per case: the overrides and the held pushes are
  --- file-locals.
  ---@return table
  local function reload()
    package.loaded["lsp.core.workspace_projects"] = nil
    return require("lsp.core.workspace_projects")
  end

  ---@param path string
  ---@return string
  local function real(path)
    return vim.fs.normalize(uv.fs_realpath(path) or path)
  end

  before_each(function()
    tmp = real(vim.fn.tempname())
    vim.fn.mkdir(tmp, "p")
    tmp = real(tmp)
    vault, plugin = tmp .. "/vault", tmp .. "/plugin"
    vim.fn.mkdir(vault .. "/.git", "p")
    vim.fn.mkdir(plugin .. "/.git", "p")
    write_file(vault .. "/a.md", "# a\n")
    write_file(vault .. "/b.md", "# b\n")
    write_file(plugin .. "/x.lua", "-- x\n")
    projects = reload()
  end)

  after_each(function()
    vim.env.LSPTEST_PROJ = nil
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    vim.fn.delete(tmp, "rf")
  end)

  describe("state", function()
    it("answers nil for a path no override covers", function()
      projects.seed({ [vault] = false })
      assert.is_nil((projects.state_of(plugin .. "/x.lua")))
    end)

    it("covers the folder itself and everything below it", function()
      projects.seed({ [vault] = false })
      assert.is_false((projects.state_of(vault)))
      assert.is_false((projects.state_of(vault .. "/a.md")))
      assert.is_false((projects.state_of(vault .. "/deep/er/c.md")))
    end)

    -- `/x/vault` must not swallow `/x/vault-old`: prefix matching on the raw
    -- string would, and the sibling would silently lose its diagnostics.
    it("does not match a sibling that merely shares the prefix", function()
      projects.seed({ [vault] = false })
      assert.is_nil((projects.state_of(vault .. "-old/a.md")))
    end)

    it("lets the most specific project win", function()
      projects.seed({ [vault] = false, [vault .. "/keep"] = true })
      assert.is_false((projects.state_of(vault .. "/a.md")))
      assert.is_true((projects.state_of(vault .. "/keep/a.md")))
    end)

    it("expands $VAR and ~ in the configured path", function()
      vim.env.LSPTEST_PROJ = vault
      projects.seed({ ["$LSPTEST_PROJ"] = false })
      assert.is_false((projects.state_of(vault .. "/a.md")))
    end)

    it("seeds only once, so a runtime change is not clobbered", function()
      projects.seed({ [vault] = false })
      projects.set(vault, true)
      projects.seed({ [vault] = false })
      assert.is_true((projects.state_of(vault .. "/a.md")))
    end)

    it("ignores an entry that is not `string -> boolean`", function()
      ---@diagnostic disable-next-line: assign-type-mismatch
      projects.seed({ [vault] = "off", [""] = false })
      assert.are.same({}, projects.list())
    end)

    it("falls back to the global switch and says so", function()
      projects.seed({ [vault] = false })
      local on, source = projects.effective(plugin .. "/x.lua", true)
      assert.is_true(on)
      assert.are.equal("global", source)

      on, source = projects.effective(vault .. "/a.md", true)
      assert.is_false(on)
      assert.are.equal("project", source)
    end)

    it("reports whether any project is switched ON", function()
      projects.seed({ [vault] = false })
      assert.is_false(projects.any_enabled())
      projects.set(plugin, true)
      assert.is_true(projects.any_enabled())
    end)
  end)

  describe("resolve", function()
    local saved_repos

    before_each(function()
      saved_repos = vim.env.REPOS_DIR
      vim.env.REPOS_DIR = tmp
    end)

    after_each(function()
      vim.env.REPOS_DIR = saved_repos
    end)

    it("takes a bare name as a folder under $REPOS_DIR", function()
      assert.are.equal(vault, (projects.resolve("vault")))
    end)

    it("takes a path, with $VAR expanded", function()
      vim.env.LSPTEST_PROJ = plugin
      assert.are.equal(plugin, (projects.resolve("$LSPTEST_PROJ")))
      assert.are.equal(plugin, (projects.resolve(plugin)))
    end)

    it("takes `.` as the project root of the cwd, not the cwd itself", function()
      local prev = vim.fn.getcwd()
      vim.fn.mkdir(vault .. "/sub/dir", "p")
      vim.cmd.cd(vim.fn.fnameescape(vault .. "/sub/dir"))
      local got = projects.resolve(".")
      vim.cmd.cd(vim.fn.fnameescape(prev))
      assert.are.equal(vault, got)
    end)

    -- A typo must not create an override that matches nothing and then
    -- reports success.
    it("refuses what is not an existing directory", function()
      local path, err = projects.resolve("no-such-project")
      assert.is_nil(path)
      assert.is_truthy(err and err:find("not a directory", 1, true))

      path, err = projects.resolve(vault .. "/a.md")
      assert.is_nil(path)
      assert.is_truthy(err)
    end)

    it("refuses an empty argument", function()
      assert.is_nil((projects.resolve("")))
      assert.is_nil((projects.resolve(nil)))
    end)

    it("lists the folders under $REPOS_DIR, dot-directories and files excluded", function()
      vim.fn.mkdir(tmp .. "/.hidden", "p")
      write_file(tmp .. "/loose.txt", "x")
      assert.are.same({ "plugin", "vault" }, projects.repo_names())
    end)
  end)

  describe("publish gate", function()
    local KEY = "textDocument/publishDiagnostics"

    ---@param file string
    ---@param count integer|nil
    ---@return table result
    local function push(file, count)
      local diagnostics = {}
      for i = 1, count or 1 do
        diagnostics[i] = {
          range = {
            start = { line = i - 1, character = 0 },
            ["end"] = { line = i - 1, character = 1 },
          },
          severity = 2,
          message = "d" .. i,
        }
      end
      return { uri = vim.uri_from_fname(file), diagnostics = diagnostics }
    end

    local real_get_client_by_id, real_handler

    before_each(function()
      -- No real client behind the pushes; the replay checks one is alive.
      real_get_client_by_id = vim.lsp.get_client_by_id
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.lsp.get_client_by_id = function(id)
        return { id = id }
      end
      real_handler = vim.lsp.handlers[KEY]
    end)

    after_each(function()
      vim.lsp.get_client_by_id = real_get_client_by_id
      vim.lsp.handlers[KEY] = real_handler
    end)

    it("holds nothing while no project is OFF", function()
      assert.is_false(projects.hold_push(nil, push(vault .. "/a.md"), { client_id = 1 }, nil))
      projects.seed({ [vault] = true })
      assert.is_false(projects.hold_push(nil, push(vault .. "/a.md"), { client_id = 1 }, nil))
    end)

    it("holds a push for a closed file in a project that is OFF", function()
      projects.seed({ [vault] = false })
      assert.is_true(projects.hold_push(nil, push(vault .. "/a.md"), { client_id = 1 }, nil))
      assert.are.equal(1, projects.held_count())
    end)

    it("keeps only the newest push per (client, file)", function()
      projects.seed({ [vault] = false })
      projects.hold_push(nil, push(vault .. "/a.md", 1), { client_id = 1 }, nil)
      projects.hold_push(nil, push(vault .. "/a.md", 3), { client_id = 1 }, nil)
      assert.are.equal(1, projects.held_count())
    end)

    it("does not hold a push for a file that is open", function()
      projects.seed({ [vault] = false })
      open_buf(vault .. "/a.md")
      assert.is_false(projects.hold_push(nil, push(vault .. "/a.md"), { client_id = 1 }, nil))
      -- ... but still holds its closed neighbour.
      assert.is_true(projects.hold_push(nil, push(vault .. "/b.md"), { client_id = 1 }, nil))
    end)

    -- An empty push only clears. Holding it would leave stale diagnostics on a
    -- buffer that was unloaded since.
    it("lets an empty push through", function()
      projects.seed({ [vault] = false })
      assert.is_false(projects.hold_push(nil, push(vault .. "/a.md", 0), { client_id = 1 }, nil))
    end)

    it("does not hold a push for another project", function()
      projects.seed({ [vault] = false })
      assert.is_false(projects.hold_push(nil, push(plugin .. "/x.lua"), { client_id = 1 }, nil))
    end)

    it("does not raise on a payload that is not a push", function()
      projects.seed({ [vault] = false })
      assert.is_false(projects.hold_push(nil, nil, { client_id = 1 }, nil))
      assert.is_false(projects.hold_push(nil, { diagnostics = {} }, nil, nil))
      assert.is_false(projects.hold_push(nil, { uri = 1, diagnostics = {} }, {}, nil))
    end)

    it("replays what was held when the project is switched back ON", function()
      local replayed = {}
      vim.lsp.handlers[KEY] = function(_, result)
        replayed[#replayed + 1] = result.uri
      end
      projects.seed({ [vault] = false })
      projects.hold_push(nil, push(vault .. "/a.md"), { client_id = 1 }, nil)
      projects.hold_push(nil, push(vault .. "/b.md"), { client_id = 1 }, nil)

      projects.set(vault, true)

      table.sort(replayed)
      assert.are.same(
        { vim.uri_from_fname(vault .. "/a.md"), vim.uri_from_fname(vault .. "/b.md") },
        replayed
      )
      assert.are.equal(0, projects.held_count())
    end)

    it("replays on `clear` when the global switch is on, and not when it is off", function()
      local replayed = {}
      vim.lsp.handlers[KEY] = function(_, result)
        replayed[#replayed + 1] = result.uri
      end

      projects.seed({ [vault] = false })
      projects.hold_push(nil, push(vault .. "/a.md"), { client_id = 1 }, nil)
      projects.clear(vault, false)
      assert.are.equal(0, #replayed, "global OFF: nothing to deliver")

      projects = reload()
      projects.seed({ [vault] = false })
      projects.hold_push(nil, push(vault .. "/a.md"), { client_id = 1 }, nil)
      projects.clear(vault, true)
      assert.are.equal(1, #replayed, "global ON: the held push is delivered")
    end)

    it("delivers the held push of a buffer that has just been opened", function()
      local replayed = {}
      vim.lsp.handlers[KEY] = function(_, result)
        replayed[#replayed + 1] = result.uri
      end
      projects.seed({ [vault] = false })
      projects.hold_push(nil, push(vault .. "/a.md"), { client_id = 7 }, nil)

      local bufnr = open_buf(vault .. "/a.md")
      projects.release_buffer({ id = 7 }, bufnr)
      -- The project is still OFF, but the file is open now: not gated.
      assert.are.equal(1, #replayed)
      assert.are.equal(0, projects.held_count())
    end)

    it("purges leftovers of the scan on switching OFF, but not an open file's", function()
      local ns = vim.api.nvim_create_namespace("workspace_projects_spec")
      local diag = { { lnum = 0, col = 0, message = "x" } }

      local closed = vim.fn.bufadd(vault .. "/a.md")
      vim.diagnostic.set(ns, closed, diag)
      local open = open_buf(vault .. "/b.md")
      vim.diagnostic.set(ns, open, diag)
      local other = vim.fn.bufadd(plugin .. "/x.lua")
      vim.diagnostic.set(ns, other, diag)

      projects.set(vault, false)

      assert.are.equal(0, #vim.diagnostic.get(closed), "closed file in the project: cleared")
      assert.are.equal(1, #vim.diagnostic.get(open), "open file keeps its diagnostics")
      assert.are.equal(1, #vim.diagnostic.get(other), "another project is untouched")
    end)
  end)

  describe("lsp.core.handlers integration", function()
    local KEY = "textDocument/publishDiagnostics"
    local received, real_handler, real_get_client_by_id

    before_each(function()
      real_handler = vim.lsp.handlers[KEY]
      real_get_client_by_id = vim.lsp.get_client_by_id
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.lsp.get_client_by_id = function(id)
        return { id = id }
      end
      received = {}
      vim.lsp.handlers[KEY] = function(_, result)
        received[#received + 1] = result.uri
      end
      package.loaded["lsp.core.handlers"] = nil
      -- `hold_push` is looked up through `require`, so the module under test is
      -- the one `projects` names here.
      package.loaded["lsp.core.workspace_projects"] = projects
      require("lsp.core.handlers").setup({ debounce_ms = 0 })
    end)

    after_each(function()
      package.loaded["lsp.core.handlers"] = nil
      vim.lsp.handlers[KEY] = real_handler
      vim.lsp.get_client_by_id = real_get_client_by_id
    end)

    ---@param file string
    ---@return nil
    local function publish(file)
      vim.lsp.handlers[KEY](nil, {
        uri = vim.uri_from_fname(file),
        diagnostics = {
          {
            range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 1 } },
            severity = 2,
            message = "boom",
          },
        },
      }, { client_id = 1, method = KEY }, nil)
    end

    it("renders nothing for a closed file in a project that is OFF", function()
      projects.seed({ [vault] = false })
      publish(vault .. "/a.md")
      assert.are.same({}, received)
    end)

    it("renders a file that is open, in the same project", function()
      projects.seed({ [vault] = false })
      open_buf(vault .. "/a.md")
      publish(vault .. "/a.md")
      assert.are.equal(1, #received)
    end)

    it("renders everything outside the project", function()
      projects.seed({ [vault] = false })
      publish(plugin .. "/x.lua")
      assert.are.equal(1, #received)
    end)

    it("renders again after the project is switched back ON", function()
      projects.seed({ [vault] = false })
      publish(vault .. "/a.md")
      assert.are.same({}, received)

      projects.set(vault, true)
      -- The replay goes through the wrapper, and the wrapper now lets it by.
      assert.are.equal(1, #received)
    end)
  end)

  describe("lsp.core.workspace_diagnostics", function()
    ---@type table[]
    local sink

    --- Both modules fresh, so `schedule_populate` reads THIS `projects`.
    ---@param global boolean
    ---@return table wd
    local function reload_wd(global)
      package.loaded["lsp.core.workspace_diagnostics"] = nil
      package.loaded["lsp.core.workspace_projects"] = projects
      local wd = require("lsp.core.workspace_diagnostics")
      wd.seed(global)
      wd.configure({ delay_ms = 20, chunk_delay_ms = 1 })
      return wd
    end

    before_each(function()
      sink = {}
      write_file(plugin .. "/y.lua", "-- y\n")
      write_file(vault .. "/c.md", "# c\n")
    end)

    after_each(function()
      package.loaded["lsp.core.workspace_diagnostics"] = nil
      for _, c in ipairs(vim.lsp.get_clients()) do
        c:stop(true)
      end
      vim.wait(500, function()
        return #vim.lsp.get_clients() == 0
      end)
    end)

    ---@param name string
    ---@param root string
    ---@param file string
    ---@param filetypes string[]
    ---@return vim.lsp.Client client
    ---@return integer bufnr
    local function attach(name, root, file, filetypes)
      local bufnr = open_buf(file)
      start_stub({ name = name, filetypes = filetypes, root = root, bufnr = bufnr, sink = sink })
      assert.is_true(vim.wait(2000, function()
        return #vim.lsp.get_clients({ bufnr = bufnr }) > 0
      end))
      return vim.lsp.get_clients({ bufnr = bufnr })[1], bufnr
    end

    it("populates a project that is ON while the global switch is off", function()
      local wd = reload_wd(false)
      projects.seed({ [plugin] = true })
      local client, bufnr = attach("srv_plugin", plugin, plugin .. "/x.lua", { "lua" })

      wd.schedule_populate(client, bufnr)

      assert.is_true(
        vim.wait(3000, function()
          return opened_by(sink, "srv_plugin")[plugin .. "/y.lua"] == true
        end, 20),
        "the project override did not turn the populate on"
      )
    end)

    -- The point of the override: no walk, hence no didOpen and no max_files
    -- warning, for a project that is OFF -- while the global switch is ON.
    it("does not populate a project that is OFF, though the global switch is on", function()
      local wd = reload_wd(true)
      projects.seed({ [vault] = false })
      local client, bufnr = attach("srv_vault", vault, vault .. "/a.md", { "markdown" })

      wd.schedule_populate(client, bufnr)
      vim.wait(400, function()
        return false
      end)

      -- Neovim itself sends `didOpen` for the buffer the client attached to;
      -- what must be absent is the rest of the workspace.
      local opened = opened_by(sink, "srv_vault")
      assert.is_nil(opened[vault .. "/b.md"])
      assert.is_nil(opened[vault .. "/c.md"])
    end)

    it("still populates a project no override covers", function()
      local wd = reload_wd(true)
      projects.seed({ [vault] = false })
      local client, bufnr = attach("srv_plugin", plugin, plugin .. "/x.lua", { "lua" })

      wd.schedule_populate(client, bufnr)

      assert.is_true(vim.wait(3000, function()
        return opened_by(sink, "srv_plugin")[plugin .. "/y.lua"] == true
      end, 20))
    end)

    it("honours a switch flipped during the delay", function()
      local wd = reload_wd(true)
      local client, bufnr = attach("srv_plugin", plugin, plugin .. "/x.lua", { "lua" })

      wd.schedule_populate(client, bufnr)
      -- Armed, and then the user turns the project off before the timer fires.
      projects.set(plugin, false)
      vim.wait(400, function()
        return false
      end)

      assert.is_nil(opened_by(sink, "srv_plugin")[plugin .. "/y.lua"])
    end)

    it("may_populate is the global switch or any project that is ON", function()
      local wd = reload_wd(false)
      assert.is_false(wd.may_populate())
      projects.set(plugin, true)
      assert.is_true(wd.may_populate())
      projects.clear(plugin, false)
      assert.is_false(wd.may_populate())
      wd.set(true)
      assert.is_true(wd.may_populate())
    end)

    it("populate_project walks the attached clients inside the project, once", function()
      local wd = reload_wd(false)
      local _, bufnr = attach("srv_plugin", plugin, plugin .. "/x.lua", { "lua" })
      -- A second buffer of the same client in the same root must not walk twice.
      vim.cmd.edit(vim.fn.fnameescape(plugin .. "/y.lua"))
      vim.lsp.buf_attach_client(
        vim.api.nvim_get_current_buf(),
        vim.lsp.get_clients({ bufnr = bufnr })[1].id
      )

      local scheduled = wd.populate_project(plugin)

      assert.are.equal(1, scheduled)
      assert.is_true(vim.wait(3000, function()
        return opened_by(sink, "srv_plugin")[plugin .. "/y.lua"] == true
          or opened_by(sink, "srv_plugin")[plugin .. "/x.lua"] == true
      end, 20))
    end)

    it("populate_project ignores a client whose workspace is elsewhere", function()
      local wd = reload_wd(false)
      attach("srv_plugin", plugin, plugin .. "/x.lua", { "lua" })

      assert.are.equal(0, wd.populate_project(vault))
    end)
  end)
end)
