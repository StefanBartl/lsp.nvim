--- Pins four defects found by measuring `lua/lsp/core/*`, one per module.
--- Every case here failed against the version at the commit that introduced
--- it; none of them is a restatement of what the module already documents.
---
--- The two `workspace_diagnostics` cases drive in-process stub servers
--- (`vim.lsp.start` with a function `cmd`) over two real directory trees,
--- because the defect is about *which repository* gets walked -- a stubbed
--- `vim.lsp.get_clients` would assert that the stub was called and nothing
--- about the walk. The stub is still not a language server: it answers
--- `initialize` with a capability table and records the notifications it is
--- sent, which is the whole surface under test.

local uv = vim.uv or vim.loop

---@param path string
---@param text string
local function write_file(path, text)
  local fd = assert(uv.fs_open(path, "w", 420))
  uv.fs_write(fd, text)
  uv.fs_close(fd)
end

--- An in-process LSP client that records every notification it is sent.
---@param opts { name: string, caps?: table, filetypes?: string[], root: string, bufnr: integer, sink: table[] }
---@return integer|nil client_id
local function start_stub(opts)
  local caps = opts.caps or { textDocumentSync = 1 }
  return vim.lsp.start({
    name = opts.name,
    cmd = function(dispatchers)
      local closing = false
      return {
        request = function(method, _params, cb)
          -- Everything other than `initialize` is answered empty: this module
          -- only ever notifies, so a real response would be unused anyway.
          cb(nil, method == "initialize" and { capabilities = caps } or nil)
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

--- The absolute paths a client was sent `textDocument/didOpen` for.
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

describe("lsp.core.workspace_folders", function()
  local saved_get_clients
  ---@type table[]
  local clients = {}

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
      workspace_folders = folders,
      server_capabilities = opts.caps
        or { workspace = { workspaceFolders = { supported = true, changeNotifications = true } } },
      _remove_workspace_folder = function(self, dir)
        for i, folder in ipairs(self.workspace_folders) do
          if folder.name == dir then
            table.remove(self.workspace_folders, i)
            break
          end
        end
      end,
    }
  end

  before_each(function()
    saved_get_clients = vim.lsp.get_clients
    vim.lsp.get_clients = function()
      return clients
    end
  end)

  after_each(function()
    vim.lsp.get_clients = saved_get_clients
    clients = {}
  end)

  -- The existing spec's "stays quiet about clients that never held the folder"
  -- only had a bystander that *could* have taken the change, so the capability
  -- gate it ran anyway never produced a reason. An ordinary webdev buffer has
  -- three servers that declare no workspaceFolders support at all, and with
  -- those the gate spoke for every one of them: a removal that fully succeeded
  -- came back with a three-entry `skipped`, which `workspace_picker.announce`
  -- renders as "Removed <dir> (gopls); 3 client(s) skipped".
  it("does not report the servers a removal never had anything to ask of", function()
    local cwd = vim.fn.getcwd()
    clients = {
      client({ id = 1, name = "gopls", folders = { cwd } }),
      client({ id = 2, name = "html", caps = {} }),
      client({ id = 3, name = "jsonls", caps = {} }),
      client({ id = 4, name = "cssls", caps = {} }),
    }

    package.loaded["lsp.core.workspace_folders"] = nil
    local ws = require("lsp.core.workspace_folders")

    local ok, removed, skipped = ws.remove(cwd)
    assert.is_true(ok)
    assert.are.same({ "gopls" }, removed)
    assert.are.same({}, skipped)
  end)

  -- The gate still has to speak when it is about the folder in hand: a client
  -- that holds it and cannot drop it is the case the report exists for.
  it("still names a holder that cannot take the removal", function()
    local cwd = vim.fn.getcwd()
    clients = {
      client({ id = 1, name = "marksman", folders = { cwd }, caps = {} }),
    }

    package.loaded["lsp.core.workspace_folders"] = nil
    local ws = require("lsp.core.workspace_folders")

    local ok, removed, skipped = ws.remove(cwd)
    assert.is_false(ok)
    assert.are.same({}, removed)
    assert.are.equal(1, #skipped)
    assert.is_truthy(skipped[1]:find("marksman", 1, true))
  end)
end)

describe("lsp.core.inlay_hints", function()
  local saved_get_clients
  ---@type table[]
  local clients = {}

  before_each(function()
    saved_get_clients = vim.lsp.get_clients
    vim.lsp.get_clients = function()
      return clients
    end
  end)

  after_each(function()
    vim.lsp.get_clients = saved_get_clients
    clients = {}
  end)

  -- `inlayHintProvider` is `boolean | InlayHintOptions`, so a server that does
  -- not do hints answers `false` rather than omitting the key. Testing the key
  -- for presence read that explicit "no" as a "yes", and the buffer then
  -- appeared in `status()` under "buffers with an inlayHintProvider ... on" --
  -- the report the module header says must not exist, because it sends you
  -- looking for a broken toggle instead of a server that never offered hints.
  it("does not count a server that answered inlayHintProvider = false", function()
    clients = { { id = 1, name = "html", server_capabilities = { inlayHintProvider = false } } }

    package.loaded["lsp.core.inlay_hints"] = nil
    local hints = require("lsp.core.inlay_hints")
    hints.setup({ enable = true })

    for _, line in ipairs(hints.status()) do
      assert.is_nil(line:match("^  buffer "), "a declined provider was listed: " .. line)
    end
    assert.is_truthy(
      vim.tbl_contains(
        hints.status(),
        "no loaded buffer has a client advertising inlayHintProvider"
      )
    )
  end)

  it("still counts a server that answered inlayHintProvider = true", function()
    clients = { { id = 1, name = "lua_ls", server_capabilities = { inlayHintProvider = true } } }

    package.loaded["lsp.core.inlay_hints"] = nil
    local hints = require("lsp.core.inlay_hints")
    hints.setup({ enable = true })

    local listed = false
    for _, line in ipairs(hints.status()) do
      listed = listed or line:match("^  buffer ") ~= nil
    end
    assert.is_true(listed)
  end)
end)

describe("lsp.core.workspace_diagnostics", function()
  ---@type string
  local tmp
  ---@type string
  local repo_a, repo_b
  ---@type table[]
  local sink

  ---@return table
  local function reload()
    package.loaded["lsp.core.workspace_diagnostics"] = nil
    local wd = require("lsp.core.workspace_diagnostics")
    wd.seed(true)
    -- The real delay is 1.5s and exists to stay off the attach path; here it
    -- only has to be longer than nothing, so the timer is observable.
    wd.configure({ delay_ms = 20, chunk_delay_ms = 1 })
    return wd
  end

  before_each(function()
    sink = {}
    tmp = vim.fs.normalize(vim.fn.tempname())
    repo_a, repo_b = tmp .. "/repoA", tmp .. "/repoB"
    vim.fn.mkdir(repo_a .. "/.git", "p")
    vim.fn.mkdir(repo_b .. "/.git", "p")
    write_file(repo_a .. "/a_main.lua", "-- a main\n")
    write_file(repo_a .. "/a_other.lua", "-- a other\n")
    write_file(repo_b .. "/b_main.lua", "-- b main\n")
    write_file(repo_b .. "/b_other.lua", "-- b other\n")
  end)

  after_each(function()
    for _, c in ipairs(vim.lsp.get_clients()) do
      c:stop(true)
    end
    vim.wait(500, function()
      return #vim.lsp.get_clients() == 0
    end)
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    vim.fn.delete(tmp, "rf")
  end)

  -- The walk's root came from `nvim_buf_get_name(0)`, while the populate is
  -- deferred by `delay_ms` precisely so that it runs *later* -- by which time
  -- the current buffer is routinely a different file in a different repo. The
  -- server for repoB was then told about repoA's files and never about its
  -- own, which is a workspace-wide diagnostic run over the wrong workspace.
  it("walks the repository of the buffer it was given, not of the current one", function()
    local wd = reload()

    local buf_b = open_buf(repo_b .. "/b_main.lua")
    start_stub({
      name = "srv_b",
      filetypes = { "lua" },
      root = repo_b,
      bufnr = buf_b,
      sink = sink,
    })
    assert.is_true(vim.wait(2000, function()
      return #vim.lsp.get_clients({ bufnr = buf_b }) > 0
    end))
    local client_b = vim.lsp.get_clients({ bufnr = buf_b })[1]

    wd.schedule_populate(client_b, buf_b)
    -- Exactly the race the delay creates: the user moves on while it is armed.
    open_buf(repo_a .. "/a_main.lua")

    assert.is_true(
      vim.wait(3000, function()
        return opened_by(sink, "srv_b")[repo_b .. "/b_other.lua"] == true
      end, 20),
      "srv_b was never sent its own repository's file"
    )

    local opened = opened_by(sink, "srv_b")
    for path in pairs(opened) do
      assert.is_nil(
        path:match("^" .. vim.pesc(repo_a) .. "/"),
        "srv_b was sent a file from the other repository: " .. path
      )
    end
  end)

  -- The file list was cached under the extension set alone, so the second
  -- client covering the same filetypes -- the monorepo / two-projects case,
  -- which is the only reason two clients of one shape exist -- was handed the
  -- first client's repository verbatim and its own walk never ran.
  it("does not hand a second repository the first one's file list", function()
    local wd = reload()

    local buf_a = open_buf(repo_a .. "/a_main.lua")
    start_stub({
      name = "srv_a",
      filetypes = { "lua" },
      root = repo_a,
      bufnr = buf_a,
      sink = sink,
    })
    assert.is_true(vim.wait(2000, function()
      return #vim.lsp.get_clients({ bufnr = buf_a }) > 0
    end))
    wd.schedule_populate(vim.lsp.get_clients({ bufnr = buf_a })[1], buf_a)
    assert.is_true(
      vim.wait(3000, function()
        return opened_by(sink, "srv_a")[repo_a .. "/a_other.lua"] == true
      end, 20),
      "srv_a was never populated, so the cache under test was never filled"
    )

    local buf_b = open_buf(repo_b .. "/b_main.lua")
    start_stub({
      name = "srv_b",
      filetypes = { "lua" },
      root = repo_b,
      bufnr = buf_b,
      sink = sink,
    })
    assert.is_true(vim.wait(2000, function()
      return #vim.lsp.get_clients({ bufnr = buf_b }) > 0
    end))
    wd.schedule_populate(vim.lsp.get_clients({ bufnr = buf_b })[1], buf_b)

    assert.is_true(
      vim.wait(3000, function()
        return opened_by(sink, "srv_b")[repo_b .. "/b_other.lua"] == true
      end, 20),
      "srv_b got the cached list of the other repository instead of its own"
    )

    for path in pairs(opened_by(sink, "srv_b")) do
      assert.is_nil(
        path:match("^" .. vim.pesc(repo_a) .. "/"),
        "srv_b was sent a file from the other repository: " .. path
      )
    end
  end)
end)

describe("lsp.core.diagnostics", function()
  -- `vim.diagnostic.config()` is `for k, v in pairs(opts) do t[k] = v end`: a
  -- key it is not given keeps whatever the previous call left there. So a
  -- contribution of a top-level key the baseline does not carry survived
  -- `forget()` + `apply()` forever, while `M.applied()` and `M.sources()` --
  -- the answer to "where did this come from" -- already reported it gone.
  it("puts a dropped contribution's key back to Neovim's own value", function()
    package.loaded["lsp.core.diagnostics"] = nil
    local diagnostics = require("lsp.core.diagnostics")
    diagnostics.__reset()

    local pristine = vim.deepcopy(vim.diagnostic.config().jump)
    assert.is_true(pristine.wrap, "precondition: Neovim's own jump.wrap is true")

    diagnostics.apply(nil)
    diagnostics.contribute("fancy.nvim", { jump = { wrap = false } })
    diagnostics.apply(nil)
    assert.is_false(vim.diagnostic.config().jump.wrap)

    assert.is_true(diagnostics.forget("fancy.nvim"))
    diagnostics.apply(nil)

    assert.is_nil(diagnostics.applied().jump)
    assert.are.same(pristine, vim.diagnostic.config().jump)

    diagnostics.__reset()
  end)
end)
