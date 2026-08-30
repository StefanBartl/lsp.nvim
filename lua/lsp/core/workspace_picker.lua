---@module 'lsp.core.workspace_picker'
---@brief The two choosers over `lsp.core.workspace_folders`.
---@description
--- `add()` offers the discovered candidate directories, `remove()` offers the
--- folders the buffer's clients currently hold. Split from the module that
--- talks to the clients so that one stays testable without a UI -- the specs
--- drive `workspace_folders` directly and never open a float.
---
--- Both refuse up front rather than opening an empty picker, and both say
--- *why* nothing happened. "Nothing to add" has three different causes here
--- (no client, no switchable client, every candidate already added) and they
--- want different fixes.
---
---@see lsp.core.workspace_folders
---@see lsp.core.root_scope_picker

local select = require("lib.nvim.ui.kit.select")
local workspace = require("lsp.core.workspace_folders")
local notify = require("lib.nvim.notify").create("[lsp.core.workspace_picker]")

local M = {}

---@internal
--- Summarize what `add`/`remove` did, in one notification rather than one per
--- client: a monorepo buffer can carry four clients, and four toasts for one
--- keypress is worse than no feedback at all.
---@param verb string
---@param dir string
---@param acted string[]
---@param skipped string[]
---@return nil
local function announce(verb, dir, acted, skipped)
  if #acted > 0 then
    local msg = ("%s %s (%s)"):format(verb, dir, table.concat(acted, ", "))
    if #skipped > 0 then
      msg = msg .. ("; %d client(s) skipped"):format(#skipped)
    end
    notify.info(msg)
    return
  end

  if #skipped > 0 then
    notify.warn(("%s: nothing happened -- %s"):format(dir, table.concat(skipped, "; ")))
  else
    notify.warn(("%s: no LSP client on this buffer took it"):format(dir))
  end
end

---@internal
--- Whether any client on the buffer can take a runtime folder change, and a
--- reason to show when none can.
---@param bufnr integer
---@return boolean ok
---@return string reason
local function switchable(bufnr)
  local clients = workspace.clients(bufnr)
  if #clients == 0 then
    return false, "no LSP client is attached to this buffer"
  end
  for _, entry in ipairs(clients) do
    if entry.switchable then
      return true, ""
    end
  end
  return false, "no attached client accepts runtime workspace-folder changes (see `:Lsp root show`)"
end

--- Pick a directory to add to the workspace.
---@return nil
function M.add()
  local bufnr = vim.api.nvim_get_current_buf()

  local ok, reason = switchable(bufnr)
  if not ok then
    notify.warn(reason)
    return
  end

  local candidates = workspace.candidates(bufnr)
  if #candidates == 0 then
    notify.info("Nothing to add: every candidate is already a workspace folder")
    return
  end

  select.open({
    items = candidates,
    title = "Add workspace folder",
    on_select = function(dir)
      if type(dir) ~= "string" then
        return
      end
      local _, added, skipped = workspace.add(dir, bufnr)
      announce("Added", dir, added, skipped)
    end,
  })
end

--- Pick a workspace folder to remove.
---@return nil
function M.remove()
  local bufnr = vim.api.nvim_get_current_buf()

  local folders = workspace.folders(bufnr)
  if #folders == 0 then
    notify.info("This buffer's clients hold no workspace folders")
    return
  end

  select.open({
    items = folders,
    title = "Remove workspace folder",
    -- The client names are the point: removing a folder two servers share is
    -- a different decision from removing one only `gopls` holds.
    format_item = function(folder)
      return ("%s  (%s)"):format(folder.path, table.concat(folder.clients, ", "))
    end,
    on_select = function(folder)
      if type(folder) ~= "table" or type(folder.path) ~= "string" then
        return
      end
      local _, removed, skipped = workspace.remove(folder.path, bufnr)
      announce("Removed", folder.path, removed, skipped)
    end,
  })
end

return M
