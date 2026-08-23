---@module 'lsp.languages.systems.zig'
--- Zig QoL: registers the `zig` FileType group but the callback is a
--- no-op -- the same stub shape as c.lua/go.lua next to it.
---@class LangZigQoL

local Autocmd = require("lib.nvim.autocmd")

local M = {}

---@return nil
function M.enable()
  local grp = Autocmd.group("LangZig", true)
  Autocmd.create("FileType", function(_) end, {
    group = grp,
    pattern = "zig",
  })
end

---@type Lsp.Languages.ConfiguredLangs.Zig.Module
return M
