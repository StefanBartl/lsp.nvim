--- Covers `lsp.core.changetracking_guard`: the wrapper stays invisible while
--- `vim.lsp._changetracking.send_changes` behaves, resyncs every attached
--- client through public API when it throws the upstream desync
--- (neovim/neovim#28987, #37814) instead of letting the error surface as the
--- `msg_show.lua_error` the issues describe, survives a `:Lazy reload
--- lsp.nvim` without double-wrapping, and stops retrying a buffer that will
--- not stay resynced.
---
--- `vim.lsp._changetracking` is the real core module -- there is no fixture
--- for it -- so each case saves and restores its `send_changes` field, and
--- the idempotency marker this module sets on it, rather than risk leaking
--- either into a later spec file.

describe("lsp.core.changetracking_guard", function()
  local changetracking = require("vim.lsp._changetracking")
  local original_send_changes

  --- Fresh module state per case: `attempts` is a file-local, re-created
  --- empty by re-executing the module chunk. The idempotency marker is not
  --- (see after_each) -- it deliberately lives on `changetracking` instead,
  --- which this reload does not touch, matching what `:Lazy reload lsp.nvim`
  --- does to the real modules.
  ---@return table
  local function reload()
    package.loaded["lsp.core.changetracking_guard"] = nil
    return (require("lsp.core.changetracking_guard"))
  end

  --- Stub `get_clients`/`buf_detach_client`/`buf_attach_client` for `bufnr`
  --- so a resync can be counted without touching real LSP clients, and
  --- return a restorer to run before the case's buffer is deleted.
  ---@param bufnr integer
  ---@param client_ids integer[]
  ---@return fun(): nil restore
  ---@return integer[] attach_calls client ids passed to buf_attach_client, in order
  local function stub_resync(bufnr, client_ids)
    local real_get_clients = vim.lsp.get_clients
    local real_detach = vim.lsp.buf_detach_client
    local real_attach = vim.lsp.buf_attach_client
    local attached = {}

    vim.lsp.get_clients = function(opts)
      if opts and opts.bufnr == bufnr then
        local clients = {}
        for _, id in ipairs(client_ids) do
          clients[#clients + 1] = { id = id }
        end
        return clients
      end
      return real_get_clients(opts)
    end
    vim.lsp.buf_detach_client = function() end
    vim.lsp.buf_attach_client = function(_, id)
      attached[#attached + 1] = id
    end

    return function()
      vim.lsp.get_clients = real_get_clients
      vim.lsp.buf_detach_client = real_detach
      vim.lsp.buf_attach_client = real_attach
    end,
      attached
  end

  before_each(function()
    original_send_changes = changetracking.send_changes
  end)

  after_each(function()
    changetracking.send_changes = original_send_changes
    changetracking._lsp_nvim_guard_installed = nil
  end)

  it("passes calls through untouched when the original does not error", function()
    local guard = reload()
    local calls = {}
    changetracking.send_changes = function(bufnr, firstline, lastline, new_lastline)
      calls[#calls + 1] = { bufnr, firstline, lastline, new_lastline }
    end
    guard.setup()

    changetracking.send_changes(7, 1, 2, 3)

    assert.are.same({ { 7, 1, 2, 3 } }, calls)
  end)

  it("swallows the desync error instead of letting it propagate", function()
    local guard = reload()
    changetracking.send_changes = function()
      error("attempt to index local 'buf_state' (a nil value)")
    end
    guard.setup()

    local ok = pcall(changetracking.send_changes, 7, 1, 2, 3)

    assert.is_true(ok)
  end)

  it("resyncs every client attached to the buffer via public attach/detach", function()
    local guard = reload()
    changetracking.send_changes = function()
      error("attempt to index local 'buf_state' (a nil value)")
    end
    guard.setup()

    local bufnr = vim.api.nvim_create_buf(false, true)
    local restore, attached = stub_resync(bufnr, { 1, 2 })

    changetracking.send_changes(bufnr, 0, 1, 1)

    restore()
    vim.api.nvim_buf_delete(bufnr, { force = true })

    assert.are.same({ 1, 2 }, attached)
  end)

  it("does not resync a buffer that no longer exists", function()
    local guard = reload()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_delete(bufnr, { force = true })

    local real_get_clients = vim.lsp.get_clients
    local seen = false
    vim.lsp.get_clients = function(opts)
      if opts and opts.bufnr == bufnr then
        seen = true
      end
      return real_get_clients(opts)
    end

    guard._resync(bufnr)

    vim.lsp.get_clients = real_get_clients
    assert.is_false(seen)
  end)

  it(
    "setup() is idempotent: a second call in the same module instance does not wrap the wrapper",
    function()
      local guard = reload()
      changetracking.send_changes = function() end
      guard.setup()
      local wrapped_once = changetracking.send_changes

      guard.setup()

      assert.are.equal(wrapped_once, changetracking.send_changes)
    end
  )

  it("does not double-wrap across a reload of this plugin's own modules", function()
    -- `:Lazy reload lsp.nvim` clears every `lsp.*` module and calls setup()
    -- again; `vim.lsp._changetracking` is a Neovim core module and is not
    -- touched by that reload. reload() here reproduces exactly that: a fresh
    -- module table (so a module-local flag would read as "not installed"
    -- again) around the same, already-wrapped changetracking.send_changes.
    local guard1 = reload()
    changetracking.send_changes = function() end
    guard1.setup()
    local wrapped_once = changetracking.send_changes

    local guard2 = reload()
    guard2.setup()

    assert.are.equal(wrapped_once, changetracking.send_changes)
  end)

  it("stops resyncing a buffer after repeated failures instead of retrying forever", function()
    local guard = reload()
    changetracking.send_changes = function()
      error("attempt to index local 'buf_state' (a nil value)")
    end
    guard.setup()

    local bufnr = vim.api.nvim_create_buf(false, true)
    local restore, attached = stub_resync(bufnr, { 1 })

    -- 6 consecutive failing edits; the module gives up after 3.
    for _ = 1, 6 do
      changetracking.send_changes(bufnr, 0, 1, 1)
    end

    restore()
    vim.api.nvim_buf_delete(bufnr, { force = true })

    assert.are.equal(3, #attached)
  end)

  it("resets the retry count after a successful call, so a later desync resyncs again", function()
    local guard = reload()
    local should_fail = true
    changetracking.send_changes = function()
      if should_fail then
        error("attempt to index local 'buf_state' (a nil value)")
      end
    end
    guard.setup()

    local bufnr = vim.api.nvim_create_buf(false, true)
    local restore, attached = stub_resync(bufnr, { 1 })

    changetracking.send_changes(bufnr, 0, 1, 1) -- fails, resyncs (1)
    should_fail = false
    changetracking.send_changes(bufnr, 0, 1, 1) -- succeeds, clears the count
    should_fail = true
    changetracking.send_changes(bufnr, 0, 1, 1) -- fails again, resyncs (2)

    restore()
    vim.api.nvim_buf_delete(bufnr, { force = true })

    assert.are.equal(2, #attached)
  end)
end)
