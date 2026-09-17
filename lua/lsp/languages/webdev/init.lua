---@module 'lsp.languages.webdev'
--- Alternate webdev entry point -- `M.enable_all()` here is NOT called from
--- anywhere in this config; `lsp.languages.init`'s own `enable_webdev()`
--- (a different, overlapping language list) is what actually runs.

local M = {}

function M.enable_all()
  local langs = { "astro", "htmx", "tailwind", "typescript", "html" }

  for _, name in ipairs(langs) do
    local ok, mod = pcall(require, "lsp.languages.webdev." .. name)
    if ok and type(mod.enable) == "function" then
      pcall(mod.enable)
    end
  end

  -- No `wat = "wasm"`: it would override Neovim's own `wat` filetype, which
  -- has syntax/ftplugin/indent where `wasm` has none. See the measurement at
  -- the same table in `lsp/languages/init.lua`.
  vim.filetype.add({
    extension = {
      wasm = "wasm",
      astro = "astro",
    },
  })
end

return M
