---@module 'lsp.tools.eslint_prettier.core.check_config'
--- Helpers to check if project has eslint/prettier config in root.
local fn = vim.fn

-- The `eslint.config.*` names are flat config, which has been ESLint's default
-- since v9 and is the only format v10 reads. Without them a project that never
-- had an `.eslintrc` -- every project scaffolded in the last two years -- was
-- told "No eslint config found in project root; skipping", and `:EslintFix`
-- did nothing at all.
local eslint_patterns = {
  "eslint.config.js",
  "eslint.config.mjs",
  "eslint.config.cjs",
  "eslint.config.ts",
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

--- True when package.json declares `key` at the top level.
---
--- This used to be a substring search for `"eslintConfig"` **or** `"prettier"`,
--- run for both tools -- so one key answered for the other. Measured on a
--- package.json whose only extra key was `"eslintConfig"`: `has_eslint` true
--- (right) and `has_prettier` true as well (wrong), and the mirror image for a
--- prettier-only one. In a live `:w` on a project holding nothing but
--- `.prettierrc` and `{ "prettier": {} }`, that spawned `eslint_d`, which
--- answered "Could not find config file."
---
--- A substring search also cannot tell a declaration from a dependency:
--- `"prettier": "^3.3.3"` under `devDependencies` matched too. Decoding the
--- file answers both questions at once, and package.json is JSON by
--- definition -- a file too broken to decode is a file we should not be
--- reading tool configuration out of either.
---@param path string
---@param key string
---@return boolean
local function package_json_declares(path, key)
  local ok, lines = pcall(fn.readfile, path)
  if not ok or not lines then
    return false
  end
  local decoded_ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not decoded_ok or type(decoded) ~= "table" then
    return false
  end
  return decoded[key] ~= nil
end

---@param root string|nil  # `find_root` answers nil for an unnamed buffer
---@param patterns string[]
---@param package_key string  # the top-level package.json key that counts for this tool
local function has_any_config(root, patterns, package_key)
  if not root then
    return false
  end
  for _, p in ipairs(patterns) do
    local path = root .. "/" .. p
    if fn.filereadable(path) == 1 then
      if p ~= "package.json" then
        return true
      end
      -- package.json only counts when it actually declares this tool's own
      -- key; otherwise keep checking the remaining patterns.
      if package_json_declares(path, package_key) then
        return true
      end
    end
  end
  return false
end

---@param root string|nil
function M.has_eslint(root)
  return has_any_config(root, eslint_patterns, "eslintConfig")
end
---@param root string|nil
function M.has_prettier(root)
  return has_any_config(root, prettier_patterns, "prettier")
end

return M
