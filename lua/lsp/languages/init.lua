---@module 'lsp.languages'
--- Entry point: `M.enable_all()` calls each app/documentation/webdev language
--- module's own `enable()`, pcall-guarded so one missing module never stops
--- the rest.

require("lsp.languages.@types")

local M = {}

---@type Lsp.Languages.ConfiguredLangs.Literal.App[]
local app_langs = { "java", "dart" }
---@type Lsp.Languages.ConfiguredLangs.Literal.Doc[]
local documentation_langs = { "markdown" }
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
local function enable_webdev()
  for _, name in ipairs(webdev_langs) do
    local ok, mod = pcall(require, "lsp.languages.webdev." .. name)
    if ok and type(mod.enable) == "function" then
      pcall(mod.enable)
    end
  end

  -- `wat` is deliberately NOT mapped to "wasm" here any more. Neovim detects
  -- `*.wat` as filetype `wat` by itself and ships `syntax/wat.vim`,
  -- `ftplugin/wat.vim` and `indent/wat.vim` for it; it ships nothing at all
  -- for `wasm`. Measured on this Neovim (0.12.2): a clean session answers
  -- `vim.filetype.match({ filename = "a.wat" }) == "wat"`, and after
  -- `enable_all()` the same call answered `"wasm"` -- so this plugin took the
  -- WebAssembly text format from a fully supported filetype to one with no
  -- syntax, no ftplugin and no indent, for nothing in return.
  --
  -- `wasm` (the binary form) has no native detection, so that entry still buys
  -- something; `astro` is native since 0.11 but is kept for older Neovim.
  vim.filetype.add({
    extension = {
      wasm = "wasm",
      astro = "astro",
    },
  })
end

-- A language belongs here only if it has filetype QoL to install. Server
-- configuration belongs to `lsp.servers.*`, and this loop calls `enable()` with
-- no arguments -- so a module that only wraps a server config registers it
-- *without* capabilities moments before the registry registers it properly.
-- That is what the `shell` module did (a byte-for-byte copy of
-- `lsp.servers.bashls`), and it is why it is gone. `c`, `cpp`, `go`, `lua`,
-- `zig` and `cs` are absent for the plain reason that they have no QoL yet;
-- their servers come from `lsp.servers.*`, and per-filetype options are what
-- `after/ftplugin/<ft>.lua` is for.
---@return nil
function M.enable_all()
  enable_app()
  enable_documentation()
  enable_webdev()
end

return M
