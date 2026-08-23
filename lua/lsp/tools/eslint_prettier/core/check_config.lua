---@module 'lsp.tools.eslint_prettier.core.check_config'
--- Helpers to check if project has eslint/prettier config in root.
local fn = vim.fn

local eslint_patterns = {
  ".eslintrc",
  ".eslintrc.js",
  ".eslintrc.cjs",
  ".eslintrc.json",
  ".eslintrc.yml",
  ".eslintrc.yaml",
  "package.json",
}
local prettier_patterns = {
  ".prettierrc",
  ".prettierrc.js",
  ".prettierrc.cjs",
  ".prettierrc.json",
  ".prettierrc.yml",
  ".prettierrc.yaml",
  "prettier.config.js",
  "package.json",
}

local M = {}

---@param path string
---@param pattern string
local function file_contains(path, pattern)
  local ok, lines = pcall(fn.readfile, path)
  if not ok or not lines then
    return false
  end
  local txt = table.concat(lines, "\n")
  return txt:match(pattern) ~= nil
end

---@param root string
---@param patterns string[]
local function has_any_config(root, patterns)
  if not root then
    return false
  end
  for _, p in ipairs(patterns) do
    local path = root .. "/" .. p
    if fn.filereadable(path) == 1 then
      if p == "package.json" then
        -- package.json may declare `"eslintConfig"` or `"prettier"`
        if file_contains(path, '"eslintConfig"') or file_contains(path, '"prettier"') then
          return true
        else
          -- continue checking other patterns
        end
      else
        return true
      end
    end
  end
  return false
end

---@param root string
function M.has_eslint(root)
  return has_any_config(root, eslint_patterns)
end
---@param root string
function M.has_prettier(root)
  return has_any_config(root, prettier_patterns)
end

return M
