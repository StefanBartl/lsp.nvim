--- Covers `lsp.core.util.organize_imports_sync` and its two BufWritePre call
--- sites (`lsp.languages.app.java`, `lsp.languages.webdev.astro.autocmds`).
---
--- The bug this file exists for: both call sites used to run organize-imports
--- through `vim.lsp.buf.code_action({ apply = true })`, which is
--- asynchronous -- it fires the request and returns immediately. On
--- `BufWritePre` that means the buffer is written to disk *before* the
--- server's response (and the edit it carries) ever arrives, so "organize
--- imports on save" silently applied one save late, against whatever the
--- buffer had become by the time the response showed up. `lsp.languages.
--- webdev.typescript` already worked around this with a hand-rolled
--- `buf_request_sync` call; that implementation is now the shared
--- `lsp.core.util.organize_imports_sync`, and both other call sites use it.

describe("lsp.core.util.organize_imports_sync", function()
  local saved = {}

  before_each(function()
    saved.get_clients = vim.lsp.get_clients
    saved.buf_request_sync = vim.lsp.buf_request_sync
    saved.apply_workspace_edit = vim.lsp.util.apply_workspace_edit
    saved.code_action = vim.lsp.buf.code_action
  end)

  after_each(function()
    vim.lsp.get_clients = saved.get_clients
    vim.lsp.buf_request_sync = saved.buf_request_sync
    vim.lsp.util.apply_workspace_edit = saved.apply_workspace_edit
    vim.lsp.buf.code_action = saved.code_action
    package.loaded["lsp.core.util"] = nil
  end)

  --- Install stand-ins that answer a "source.organizeImports"-shaped request
  --- with one action carrying `edit`, and make the async
  --- `vim.lsp.buf.code_action` fail the test if it is ever reached.
  ---@return table calls
  local function stub_client(kind)
    local calls = { buf_request_sync = 0, apply_workspace_edit = {}, code_action = 0 }

    local client = {
      id = 1,
      name = "stub",
      offset_encoding = "utf-16",
      server_capabilities = { codeActionProvider = { codeActionKinds = { kind } } },
      supports_method = function()
        return true
      end,
    }

    vim.lsp.get_clients = function()
      return { client }
    end

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_, method, params, _)
      calls.buf_request_sync = calls.buf_request_sync + 1
      assert.are.equal("textDocument/codeAction", method)
      assert.are.same({ kind }, params.context.only)
      return { [1] = { result = { { edit = { changes = {} } } } } }
    end

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.util.apply_workspace_edit = function(edit, enc)
      calls.apply_workspace_edit[#calls.apply_workspace_edit + 1] = { edit = edit, enc = enc }
    end

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf.code_action = function()
      calls.code_action = calls.code_action + 1
      error("organize_imports_sync must not fall back to the async code_action path")
    end

    return calls
  end

  it("requests and applies the edit synchronously, scoped to the given kind", function()
    local calls = stub_client("source.organizeImports")
    local util = require("lsp.core.util")

    local applied = util.organize_imports_sync(0, "source.organizeImports")

    assert.is_true(applied)
    assert.are.equal(1, calls.buf_request_sync)
    assert.are.equal(1, #calls.apply_workspace_edit)
    assert.are.equal(0, calls.code_action)
  end)

  it("scopes the request to a server-specific kind (e.g. astro's variant)", function()
    local calls = stub_client("source.organizeImports.astro")
    local util = require("lsp.core.util")

    local applied = util.organize_imports_sync(0, "source.organizeImports.astro")

    assert.is_true(applied)
    assert.are.equal(1, calls.buf_request_sync)
  end)

  it("returns false without requesting when no client is attached", function()
    vim.lsp.get_clients = function()
      return {}
    end
    local util = require("lsp.core.util")

    assert.is_false(util.organize_imports_sync(0, "source.organizeImports"))
  end)
end)

--- The BufWritePre call sites: verify each reaches for the synchronous
--- helper, never the async `vim.lsp.buf.code_action` path.
describe("organize-imports-on-save call sites", function()
  local saved_code_action

  before_each(function()
    saved_code_action = vim.lsp.buf.code_action
  end)

  after_each(function()
    vim.lsp.buf.code_action = saved_code_action
    package.loaded["lsp.core.util"] = nil
    package.loaded["lsp.languages.app.java"] = nil
    package.loaded["lsp.languages.webdev.astro.autocmds"] = nil
  end)

  --- Stub `lsp.core.util` with a spy `organize_imports_sync` and make the
  --- async `vim.lsp.buf.code_action` fail the test if reached.
  ---@return table calls
  local function stub_util()
    local calls = {}
    package.loaded["lsp.core.util"] = {
      organize_imports_sync = function(bufnr, kind)
        calls[#calls + 1] = { bufnr = bufnr, kind = kind }
        return true
      end,
    }
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf.code_action = function()
      error("must not use the async code_action path on BufWritePre")
    end
    return calls
  end

  --- Run `fn` on a scratch buffer, then wipe it.
  ---@param fn fun(bufnr: integer)
  local function with_scratch_buffer(fn)
    local bufnr = vim.api.nvim_create_buf(false, true)
    local prev = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_current_buf(bufnr)
    local ok, err = pcall(fn, bufnr)
    pcall(vim.api.nvim_set_current_buf, prev)
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    assert(ok, err)
  end

  it("lsp.languages.app.java organizes imports through organize_imports_sync", function()
    local calls = stub_util()
    package.loaded["lsp.languages.app.java"] = nil
    local java = require("lsp.languages.app.java")

    with_scratch_buffer(function(bufnr)
      java.enable()
      vim.bo[bufnr].filetype = "java" -- fires FileType, installs the buffer-local BufWritePre
      vim.api.nvim_exec_autocmds("BufWritePre", { buffer = bufnr })

      assert.are.equal(1, #calls)
      assert.are.equal(bufnr, calls[1].bufnr)
      assert.are.equal("source.organizeImports", calls[1].kind)
    end)
  end)

  it(
    "lsp.languages.webdev.astro.autocmds organizes imports through organize_imports_sync",
    function()
      local calls = stub_util()
      package.loaded["lsp.languages.webdev.astro.autocmds"] = nil
      local astro = require("lsp.languages.webdev.astro.autocmds")

      with_scratch_buffer(function(bufnr)
        vim.api.nvim_buf_set_name(bufnr, "stub.astro")
        astro.setup()
        vim.api.nvim_exec_autocmds("BufWritePre", { buffer = bufnr })

        assert.are.equal(1, #calls)
        assert.are.equal(bufnr, calls[1].bufnr)
        assert.are.equal("source.organizeImports.astro", calls[1].kind)
      end)
    end
  )
end)
