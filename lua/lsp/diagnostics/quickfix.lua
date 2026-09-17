---@module 'lsp.diagnostics.quickfix'
--- Workspace-wide diagnostics via quickfix list.

local util = require("lsp.diagnostics.util")

---@class Lsp.Diagnostics.Quickfix
local M = {}

--- The title Neovim's own `vim.diagnostic.setqflist` uses. Reusing it is what
--- keeps `:DiagQF` updating one list instead of pushing a new one onto the
--- ten-deep quickfix stack on every invocation.
local QF_TITLE = "Diagnostics"

--- Id of the existing diagnostics quickfix list, if there is one.
---@return integer|nil
local function diagnostics_qf_id()
  local last = vim.fn.getqflist({ nr = "$" })
  for i = 1, (last.nr or 0) do
    local list = vim.fn.getqflist({ nr = i, id = 0, title = 0 })
    if list.title == QF_TITLE then
      return list.id
    end
  end
  return nil
end

--- Populate quickfix list from diagnostics.
---@param opts Lsp.Diagnostics.ListOpts|nil
---@return nil
function M.to_qf(opts)
  opts = opts or {}
  local sev = util.to_severity(opts.severity)
  local open = (opts.open ~= false)

  if opts.bufnr == nil then
    vim.diagnostic.setqflist({ open = open, namespace = opts.namespace, severity = sev })
    return
  end

  -- `vim.diagnostic.setqflist` has no `bufnr` option. Its opts table is handed
  -- to `vim.diagnostic.get(nil, opts)`, which takes the buffer as a
  -- *positional* argument, so a `bufnr` key rides along unread and the list
  -- comes back workspace-wide. Passing it therefore looked like a filter and
  -- was not one: measured with two buffers holding 3 diagnostics between them,
  -- `to_qf({ bufnr = A })` produced all 3 entries, buffer B's included, while
  -- `@types` documents `bufnr` as "target buffer". Build the list here instead.
  local items = vim.diagnostic.toqflist(
    vim.diagnostic.get(opts.bufnr, { namespace = opts.namespace, severity = sev })
  )
  local qf_id = diagnostics_qf_id()
  vim.fn.setqflist({}, qf_id and "u" or " ", { title = QF_TITLE, items = items, id = qf_id })

  if open then
    local nr = vim.fn.getqflist({ id = qf_id or diagnostics_qf_id(), nr = 0 }).nr
    vim.cmd(("silent %dchistory"):format(nr))
    vim.cmd("botright cwindow")
  end
end

--- Jump to next quickfix entry.
---@return nil
function M.next_qf(count)
  -- `:{count}cnext` is native; no loop needed. Still pcall-wrapped, because
  -- Vim raises E553 at the end of the list and swallowing that is the
  -- friendlier behaviour for a key one holds down.
  pcall(function()
    vim.cmd((count or 1) .. "cnext")
  end)
end

--- Jump to previous quickfix entry.
---@return nil
function M.prev_qf(count)
  pcall(function()
    vim.cmd((count or 1) .. "cprev")
  end)
end

return M
