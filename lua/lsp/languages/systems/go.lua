---@module 'lsp.languages.systems.go'
--- Go QoL: registers the `go` FileType group but the callback is a no-op --
--- the same stub shape as c.lua/zig.lua next to it.
---@class LangGoQoL

local Autocmd = require("lib.nvim.autocmd")

local M = {}

---@return nil
function M.enable()
  local grp = Autocmd.group("LangGo", true)
  Autocmd.create("FileType", function(_) end, {
    group = grp,
    pattern = "go",
  })
end

---@type Lsp.Languages.ConfiguredLangs.Go.Module
return M
