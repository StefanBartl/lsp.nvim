--- Covers `lsp.core.changetracking_guard`: the wrapper stays invisible while
--- `vim.lsp._changetracking.send_changes` behaves, and resyncs every attached
--- client through public API when it throws the upstream desync
--- (neovim/neovim#28987, #37814) instead of letting the error surface as the
--- `msg_show.lua_error` the issues describe.
---
--- `vim.lsp._changetracking` is the real core module -- there is no fixture
--- for it -- so each case saves and restores its `send_changes` field rather
--- than risk leaking a stub into a later spec file.

describe("lsp.core.changetracking_guard", function()
  local changetracking = require("vim.lsp._changetracking")
  local original_send_changes

  --- Fresh module state per case: `installed` is a file-local, so a case that
  --- already wrapped `send_changes` would see the next `setup()` as a no-op.
  ---@return table
  local function reload()
    package.loaded["lsp.core.changetracking_guard"] = nil
    return (require("lsp.core.changetracking_guard"))
  end

  before_each(function()
    original_send_changes = changetracking.send_changes
  end)

  after_each(function()
    changetracking.send_changes = original_send_changes
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
    local real_get_clients = vim.lsp.get_clients
    local real_detach = vim.lsp.buf_detach_client
    local real_attach = vim.lsp.buf_attach_client
    local detached, attached = {}, {}

    vim.lsp.get_clients = function(opts)
      if opts and opts.bufnr == bufnr then
        return { { id = 1 }, { id = 2 } }
      end
      return real_get_clients(opts)
    end
    vim.lsp.buf_detach_client = function(_, id)
      detached[#detached + 1] = id
    end
    vim.lsp.buf_attach_client = function(_, id)
      attached[#attached + 1] = id
    end

    changetracking.send_changes(bufnr, 0, 1, 1)

    vim.lsp.get_clients = real_get_clients
    vim.lsp.buf_detach_client = real_detach
    vim.lsp.buf_attach_client = real_attach
    vim.api.nvim_buf_delete(bufnr, { force = true })

    assert.are.same({ 1, 2 }, detached)
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

  it("setup() is idempotent: a second call does not wrap the wrapper", function()
    local guard = reload()
    changetracking.send_changes = function() end
    guard.setup()
    local wrapped_once = changetracking.send_changes

    guard.setup()

    assert.are.equal(wrapped_once, changetracking.send_changes)
  end)
end)
