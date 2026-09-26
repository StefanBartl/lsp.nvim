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
--- **Every client on the buffer is resynced, not just the one whose group
--- desynced.** `vim.lsp._changetracking` groups clients by sync kind and
--- position encoding, and this wrapper only sees "the call failed", not which
--- group -- telling them apart would mean reaching into that private
--- grouping, the exact coupling this module avoids everywhere else. The cost
--- is a spurious didClose/didOpen (and a diagnostics reset) for a client that
--- was never actually desynced, on the rare edit that trips this at all. That
--- is judged cheaper than the alternative of tracking private state to avoid
--- it.
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

--- Per-buffer count of consecutive resyncs that did not clear the desync.
--- Cleared on the next successful call, so a buffer that recovers is not
--- penalized by an earlier, unrelated run of failures.
---@type table<integer, integer>
local attempts = {}

--- Give up resyncing a buffer after this many consecutive failures, rather
--- than resync (and warn) on every single keystroke forever if a desync
--- turns out not to be one `resync()` clears -- not every upstream cause
--- listed above is necessarily fixed by a detach+reattach.
---@type integer
local MAX_ATTEMPTS = 3

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

--- Install the guard. Idempotent: a second call is a no-op, so the wrapper
--- never stacks a second `pcall` layer around itself.
---
--- The idempotency marker lives on `changetracking` itself, not a module
--- local: `:Lazy reload lsp.nvim` clears every `lsp.*` module (see
--- `lsp.completion.register`) but never touches Neovim's own core modules, so
--- a module-local flag would reset to `false` on reload while
--- `vim.lsp._changetracking.send_changes` was still last setup()'s wrapper --
--- reading that as `original` and wrapping it again on every reload, stacking
--- one dead, never-erroring `pcall` layer per reload forever.
---@return nil
function M.setup()
  local ok, changetracking = pcall(require, "vim.lsp._changetracking")
  if
    not ok
    or type(changetracking) ~= "table"
    or type(changetracking.send_changes) ~= "function"
  then
    return
  end

  if changetracking._lsp_nvim_guard_installed then
    return
  end

  local original = changetracking.send_changes

  ---@diagnostic disable-next-line: duplicate-set-field
  changetracking.send_changes = function(bufnr, firstline, lastline, new_lastline)
    local call_ok = pcall(original, bufnr, firstline, lastline, new_lastline)
    if call_ok then
      attempts[bufnr] = nil
      return
    end

    local n = (attempts[bufnr] or 0) + 1
    attempts[bufnr] = n
    if n > MAX_ATTEMPTS then
      if n == MAX_ATTEMPTS + 1 then
        notify.warn(
          ("LSP change-tracking for this buffer would not stay resynced after %d attempt(s);"):format(
            MAX_ATTEMPTS
          ) .. " giving up -- run :edit to recover"
        )
      end
      return
    end

    notify.warn(
      "LSP change-tracking desynced for this buffer (upstream Neovim bug,"
        .. " see neovim/neovim#37814) -- resyncing attached clients"
    )
    resync(bufnr)
  end

  changetracking._lsp_nvim_guard_installed = true
end

--- Exposed for the spec suite.
---@private
M._resync = resync

return M
