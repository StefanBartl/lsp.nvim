---@module 'lsp.tools.lsp_signature.split_lines'

-- Safely split a string into lines.
--@param s string
--@return string[] lines
return function(s)
  -- Use vim.split because vim.gsplit's parameter typing can trigger diagnostics.
  if not s or s == "" then
    ---@type string[]
    local empty = {}
    return empty
  end
  ---@type string[]
  local t = vim.split(s, "\n", { plain = true })
  return t
end
