---@module 'lsp.servers.marksman.hints'
--- Runtime toggle for marksman's Hint-severity diagnostics — the closest
--- thing marksman has to an editor "lightbulb" (unresolved references,
--- dangling link suggestions, etc.). Toggling calls back into
--- lsp.servers.marksman.diagnostics_handler to re-publish already-attached
--- buffers immediately, instead of waiting for the next server push.
--- Driven by :LspMdHints (lsp.usercmds) and <leader>lb.

local notify = require("lib.nvim.notify").create("[lsp.servers.marksman.hints]")

local M = {}

---@type { enabled: boolean }
local state = {
  enabled = true,
}

--- Whether marksman Hint-severity diagnostics are currently shown.
---@return boolean
function M.enabled()
  return state.enabled
end

--- Explicitly show/hide marksman hints and refresh open buffers.
---@param value boolean
---@return nil
function M.set(value)
  value = value and true or false
  if state.enabled == value then
    return
  end
  state.enabled = value

  local ok, handler = pcall(require, "lsp.servers.marksman.diagnostics_handler")
  if ok and type(handler.republish_all) == "function" then
    handler.republish_all()
  end

  notify.info(value and "Markdown hints: on" or "Markdown hints: off")
end

--- Flip the current state.
---@return nil
function M.toggle()
  M.set(not state.enabled)
end

return M
