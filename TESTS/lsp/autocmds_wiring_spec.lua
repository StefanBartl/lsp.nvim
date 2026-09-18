--- Covers `lsp.bindings.autocmds`: the `LspAttach` handler that re-binds the
--- two catalogue entries Neovim's own `gr*` defaults can shadow, and the
--- `keymaps.enable` gate and group lifecycle around it.
---
--- `lsp.bindings.keymaps` is stubbed in `package.loaded` before the module
--- under test is required, so this is about which entries get re-bind
--- attempts and in what order and with what buffer -- not whether the actual
--- keymap ends up set, which `keymaps_spec.lua` already owns.

describe("lsp.bindings.autocmds", function()
  ---@type table
  local calls
  ---@type integer[]
  local scratch_buffers

  --- Fresh stub of `lsp.bindings.keymaps`, installed before `autocmds.lua`
  --- is required so it binds to the stub rather than the real module.
  ---@return table autocmds
  local function reload()
    calls = {}
    package.loaded["lsp.bindings.keymaps"] = {
      rebind_buffer_local = function(cfg, name, bufnr)
        calls[#calls + 1] = { cfg = cfg, name = name, bufnr = bufnr }
        return true
      end,
    }
    package.loaded["lsp.bindings.autocmds"] = nil
    return require("lsp.bindings.autocmds")
  end

  --- A real, empty scratch buffer. `nvim_exec_autocmds`'s `buffer` option
  --- rejects any id that is not an actual buffer, so a bare literal like
  --- `5` fails with "Invalid buffer id" -- this is not a stand-in value.
  ---@return integer
  local function scratch_buf()
    local buf = vim.api.nvim_create_buf(false, true)
    scratch_buffers[#scratch_buffers + 1] = buf
    return buf
  end

  ---@param bufnr integer
  ---@return nil
  local function fire_attach(bufnr)
    -- `args.buf` (what the real handler reads) comes from the `buffer`
    -- option here, not from `data` -- `buffer` and `pattern` are mutually
    -- exclusive on `nvim_exec_autocmds`, so this cannot also pass `pattern`.
    vim.api.nvim_exec_autocmds("LspAttach", { buffer = bufnr })
  end

  before_each(function()
    scratch_buffers = {}
  end)

  after_each(function()
    local autocmds = package.loaded["lsp.bindings.autocmds"]
    if autocmds ~= nil and type(autocmds.clear) == "function" then
      autocmds.clear()
    end
    package.loaded["lsp.bindings.autocmds"] = nil
    package.loaded["lsp.bindings.keymaps"] = nil
    for _, buf in ipairs(scratch_buffers) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end)

  ---@param enable boolean
  ---@return table
  local function cfg(enable)
    return { keymaps = { enable = enable } }
  end

  it("registers nothing and returns 0 when keymaps are disabled", function()
    local autocmds = reload()

    local count = autocmds.setup(cfg(false))

    assert.are.equal(0, count)
    fire_attach(scratch_buf())
    assert.are.equal(0, #calls)
  end)

  it("registers one autocommand and returns 1 when keymaps are enabled", function()
    local autocmds = reload()

    local count = autocmds.setup(cfg(true))

    assert.are.equal(1, count)
  end)

  it("re-binds both catalogue entries known to collide with gr* defaults", function()
    local autocmds = reload()
    local c = cfg(true)
    autocmds.setup(c)

    local buf = scratch_buf()
    fire_attach(buf)

    assert.are.equal(2, #calls)
    assert.are.equal("rename", calls[1].name)
    assert.are.equal(buf, calls[1].bufnr)
    assert.are.equal(c, calls[1].cfg)
    assert.are.equal("goto_type_definition_gr", calls[2].name)
    assert.are.equal(buf, calls[2].bufnr)
  end)

  it("passes the buffer from the firing LspAttach event, not a stale one", function()
    local autocmds = reload()
    autocmds.setup(cfg(true))

    local buf1 = scratch_buf()
    local buf2 = scratch_buf()
    fire_attach(buf1)
    fire_attach(buf2)

    assert.are.equal(4, #calls)
    assert.are.equal(buf1, calls[1].bufnr)
    assert.are.equal(buf2, calls[3].bufnr)
  end)

  it("registers under its own named augroup", function()
    local autocmds = reload()
    autocmds.setup(cfg(true))

    local group_autocmds = vim.api.nvim_get_autocmds({ group = "lsp_nvim", event = "LspAttach" })
    assert.are.equal(1, #group_autocmds)
  end)

  -- Re-running `setup()` must not stack a second handler onto the group --
  -- `M.clear()` is called first specifically to prevent that.
  it("does not accumulate a second handler when setup() runs again", function()
    local autocmds = reload()
    autocmds.setup(cfg(true))
    autocmds.setup(cfg(true))

    fire_attach(scratch_buf())

    assert.are.equal(2, #calls, "one LspAttach fire should trigger exactly two rebind calls")
  end)

  it("clear() removes the group so a later attach does nothing", function()
    local autocmds = reload()
    autocmds.setup(cfg(true))
    autocmds.clear()

    fire_attach(scratch_buf())

    assert.are.equal(0, #calls)
  end)

  it("clear() is safe to call when nothing was ever registered", function()
    local autocmds = reload()
    assert.has_no.errors(function()
      autocmds.clear()
    end)
  end)
end)
