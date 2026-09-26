---@module 'lsp.core.changetracking_guard'
---@brief Self-heal Neovim's LSP change-tracking state after it desyncs.
---@description
--- `vim.lsp._changetracking` keeps a per-buffer state table that has to be
--- seeded by its own `init()` exactly when a client attaches and torn down
--- exactly when it detaches. When the two fall out of sync -- several
--- clients on one buffer, a client restarted by `lsp.core.supervisor`, a
--- reload -- `send_changes_for_group` indexes a `buf_state` that was never
--- (re)created and throws `attempt to index local 'buf_state' (a nil value)`
--- on every following keystroke, pointing at whatever happened to call
--- `nvim_buf_set_lines`/`nvim_put`/`normal` next. That is upstream, not this
--- plugin: neovim/neovim#28987, #37814, #19930 and #28575 all describe the
--- same desync, open as of Neovim 0.12.2, with "quit and reopen the buffer"
--- as the only documented workaround.
---
--- This wraps the module's `send_changes` -- the one entry point that indexes
--- `buf_state` without a nil guard -- in a `pcall`. On error, running
--- `vim.lsp.buf_detach_client` + `buf_attach_client` for every client on that
--- buffer forces Neovim's own attach path to re-seed `changetracking.init()`,
--- which is what desynced in the first place -- all through public API;
--- nothing here reaches into the module's private `state_by_group` upvalue.
--- That is deliberately less than `:edit`, the workaround in the upstream
--- issues: `:edit` reloads from disk and can drop unsaved changes,
--- detach+reattach only resets LSP bookkeeping and leaves buffer content and
--- undo history untouched.
---
--- Wrapping `send_changes` rather than `pcall`-ing its call site
--- (`vim/lsp.lua`'s `on_lines`) is not a style choice: that callback runs
--- through `nvim_buf_attach`, which catches a Lua error itself and reports it
--- as the `msg_show.lua_error` the upstream issues show -- by the time code
--- in this plugin could see it, it has already been swallowed. Patching the
--- field on the module table `require` hands back (Lua caches
--- `package.loaded`) is the only point downstream of the crash and upstream
--- of that swallow.
---
---@see lsp.core.supervisor

local notify = require("lib.nvim.notify").create("[lsp.core.changetracking_guard]")

local M = {}

---@type boolean
local installed = false

--- Re-run the real attach/detach pair for every client on `bufnr`, forcing
--- `vim.lsp._changetracking` to re-seed its state for each of them.
---@param bufnr integer
---@return nil
local function resync(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    pcall(vim.lsp.buf_detach_client, bufnr, client.id)
    pcall(vim.lsp.buf_attach_client, bufnr, client.id)
  end
end

--- Install the guard. Idempotent: a second call (a config reload) is a
--- no-op, so the wrapper never stacks a second `pcall` layer around itself.
---@return nil
function M.setup()
  if installed then
    return
  end

  local ok, changetracking = pcall(require, "vim.lsp._changetracking")
  if
    not ok
    or type(changetracking) ~= "table"
    or type(changetracking.send_changes) ~= "function"
  then
    return
  end

  local original = changetracking.send_changes

  ---@diagnostic disable-next-line: duplicate-set-field
  changetracking.send_changes = function(bufnr, firstline, lastline, new_lastline)
    local call_ok = pcall(original, bufnr, firstline, lastline, new_lastline)
    if call_ok then
      return
    end

    notify.warn(
      "LSP change-tracking desynced for this buffer (upstream Neovim bug,"
        .. " see neovim/neovim#37814) -- resyncing attached clients"
    )
    resync(bufnr)
  end

  installed = true
end

--- Exposed for the spec suite.
---@private
M._resync = resync

return M
