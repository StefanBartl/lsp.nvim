--- Covers the per-buffer debouncers of `lsp.core.winbar` and
--- `lsp.core.implement`: a buffer that is unloaded (`:bdelete`, not only
--- `:bwipeout`) must not leave its libuv timer behind.
---
--- A `lib.nvim.debounce` handle keeps its one-shot timer open after it fired,
--- until `cancel()`. Both modules used to cancel only on `BufWipeout`, which
--- `:bdelete` never fires: a long session with hundreds of deleted buffers
--- ended up holding two idle timers for each of them.

local winbar = require("lsp.core.winbar")
local implement = require("lsp.core.implement")
local symbols = require("lsp.core.symbols")

local uv = vim.uv or vim.loop

---@return integer
local function timers()
  local n = 0
  uv.walk(function(handle)
    if handle:get_type() == "timer" and not handle:is_closing() then
      n = n + 1
    end
  end)
  return n
end

describe("per-buffer debouncers", function()
  local real_get_clients

  before_each(function()
    real_get_clients = vim.lsp.get_clients
    -- No server: a refresh that fires has nothing to ask, which is all this
    -- case needs -- the timer is what is under test, not the request.
    vim.lsp.get_clients = function()
      return {}
    end
    symbols.reset()
  end)

  after_each(function()
    vim.lsp.get_clients = real_get_clients
    winbar.detach()
    implement.detach()
    symbols.reset()
  end)

  it("are released when a buffer is deleted, not only when it is wiped", function()
    winbar.setup({ refresh_ms = 0 })
    implement.setup({ enable = true, debounce_ms = 0 })
    -- Let the setup round and the module-wide debouncers settle first.
    vim.wait(100)
    local baseline = timers()

    local bufs = {}
    for i = 1, 50 do
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(buf, ("debounce_cleanup_%d.lua"):format(i))
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local x = " .. i })
      vim.bo[buf].filetype = "lua"
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
      bufs[#bufs + 1] = buf
    end
    -- Positive control: the measurement sees the timers it is meant to count.
    assert.is_true(timers() >= baseline + 50)
    -- Every debouncer fires once; its timer stays open afterwards.
    vim.wait(100)

    for _, buf in ipairs(bufs) do
      vim.cmd(("silent! bdelete! %d"):format(buf))
      assert.is_true(vim.api.nvim_buf_is_valid(buf)) -- deleted, not wiped
    end
    -- Closing a handle completes on the next loop iteration.
    vim.wait(50)

    assert.are.equal(baseline, timers())

    for _, buf in ipairs(bufs) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end)
end)
