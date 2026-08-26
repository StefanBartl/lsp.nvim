---@module 'lsp.usercmds.formatter'
--- `:LspFormat` -- `M.attach(formatter)` registers it against whichever
--- formatter module (conform, LSP native) the caller passes in.

local usercmd = require("lib.nvim.bindings.usercmd")
local notify = require("lib.nvim.notify").create("[lsp.usercmds.formatter]")

local M = {}

local desc_tag = "[lsp_conform] "

---@return nil
---@param formatter table
function M.attach(formatter)
  usercmd.create("LspFormat", function(_)
    formatter.format(0)
  end, { bang = true, desc = desc_tag .. "format current buffer once (silent)" })

  usercmd.create("LspFormatToggle", function()
    formatter.toggle()
  end, { desc = desc_tag .. "toggle format-on-save (silent)" })

  usercmd.create("LspFormatOn", function()
    formatter.enable()
  end, { desc = desc_tag .. "enable format-on-save (silent)" })

  usercmd.create("LspFormatOff", function()
    formatter.disable()
  end, { desc = desc_tag .. "disable format-on-save (silent)" })

  usercmd.create("LspFormatStatus", function()
    local state = formatter.is_enabled() and "true" or "false"
    notify.info("LSP/Conform state: " .. state)
  end, { desc = desc_tag .. "show state of formater" })

  usercmd.create("LspFormatWhich", function()
    local ok, mod = pcall(require, "lsp.formatter.conform")
    if ok and type(mod.which) == "function" then
      mod.which(0)
    else
      notify.warn("Conform helper unavailable")
    end
  end, { desc = "Show formatter chain & availability for current buffer" })
end

return M
