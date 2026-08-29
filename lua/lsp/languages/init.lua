---@module 'lsp.languages'
--- Entry point: `M.enable_all()` calls each app/documentation/scripting/
--- systems/webdev language module's own `enable()`, pcall-guarded so one
--- missing module never stops the rest.

local M = {}

---@type Lsp.Languages.ConfiguredLangs.Literal.App[]
local app_langs = { "csharp", "java", "dart" }
---@type Lsp.Languages.ConfiguredLangs.Literal.Doc[]
local documentation_langs = { "markdown" }
-- "shell" is deliberately not in this list. Its module was a byte-for-byte
-- copy of `lsp.servers.bashls` -- same `vim.lsp.config("bashls", ...)`, same
-- `vim.lsp.enable`, same `vim.fn.exepath("shellcheck")` -- and this loop calls
-- `enable()` with no arguments, so it registered bashls *without* capabilities
-- moments before the registry registered it properly. Server configuration
-- belongs to `lsp.servers.*`; a language module is for filetype QoL, which
-- shell had none of.
---@type Lsp.Languages.ConfiguredLangs.Literal.Scripting[]
local scripting_langs = { "lua" }
---@type Lsp.Languages.ConfiguredLangs.Literal.Systems[]
local system_langs = { "c", "go", "zig" }
---@type Lsp.Languages.ConfiguredLangs.Literal.Web[]
local webdev_langs = { "astro", "typescript", "html" }

---@return nil
local function enable_app()
  for _, name in ipairs(app_langs) do
    local ok, mod = pcall(require, "lsp.languages.app." .. name)
    if ok and type(mod.enable) == "function" then
      pcall(mod.enable)
    end
  end
end

---@return nil
local function enable_documentation()
  for _, name in ipairs(documentation_langs) do
    local ok, mod = pcall(require, "lsp.languages.documentation." .. name)
    if ok and type(mod.enable) == "function" then
      pcall(mod.enable)
    end
  end
end

---@return nil
local function enable_scripting()
  for _, name in ipairs(scripting_langs) do
    local ok, mod = pcall(require, "lsp.languages.scripting." .. name)
    if ok and type(mod.enable) == "function" then
      pcall(mod.enable)
    end
  end
end

---@return nil
local function enable_systems()
  for _, name in ipairs(system_langs) do
    local ok, mod = pcall(require, "lsp.languages.systems." .. name)
    if ok and type(mod.enable) == "function" then
      pcall(mod.enable)
    end
  end
end

---@return nil
local function enable_webdev()
  for _, name in ipairs(webdev_langs) do
    local ok, mod = pcall(require, "lsp.languages.webdev." .. name)
    if ok and type(mod.enable) == "function" then
      pcall(mod.enable)
    end
  end

  vim.filetype.add({
    extension = {
      wasm = "wasm",
      wat = "wasm",
      astro = "astro",
    },
  })
end

---@return nil
function M.enable_all()
  enable_app()
  enable_documentation()
  enable_scripting()
  enable_systems()
  enable_webdev()
end

return M
