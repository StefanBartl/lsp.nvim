---@module 'lsp.integrations.trouble.numbering'
-- Adds visual numbering to Trouble entries (qflist and loclist)

local M = {}

---Create a formatter that prefixes each Trouble item with its index.
---@return table
function M.index_prefix()
  return {
    text = function(ctx)
      -- ctx.idx is 1-based and provided by Trouble
      -- formatted width keeps alignment stable
      return string.format("%3d. ", ctx.idx)
    end,
    hl = "Comment",
  }
end

return M
