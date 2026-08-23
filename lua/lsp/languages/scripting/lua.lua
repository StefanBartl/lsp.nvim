---@module 'lsp.languages.scripting.lua'
--- Lua QoL: registers the `lua` FileType group but the callback is a
--- no-op -- the same stub shape as systems/{c,go,zig}.lua.
---@class LangLuaQoL

local Autocmd = require("lib.nvim.autocmd")

local M = {}

---@return nil
function M.enable()
  local grp = Autocmd.group("LangLua", true)
  Autocmd.create("FileType", function(_) end, {
    group = grp,
    pattern = "lua",
  })
end

---@type Lsp.Languages.ConfiguredLangs.Lua.Module
return M
