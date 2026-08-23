---@module 'lsp.tools.lsp_signature'
--- Provides Insert- and Normal-mode mapping for LSP signature help / hover preview.
--- Toggle: <C-b>
--- - Normalmodus: Popup öffnet, Fokus direkt auf Floating-Window für Scroll/Copy
--- - Insertmodus: Popup öffnet, Fokus bleibt im Hauptbuffer, Insertmodus aktiv
--- - Popup persistent, Toggle zum Schließen

local M = {}

local map = require("lib.nvim.map")
local schedule = vim.schedule
local request_and_show = require("lsp.tools.lsp_signature.request_and_show")

function M.setup()
  map({ "i", "n" }, "<C-b>", function()
    schedule(function()
      request_and_show()
    end)
  end, { desc = "[LSP] Show signature or hover (floating toggle)", silent = true, noremap = true })
end

return M
