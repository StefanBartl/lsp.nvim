---@module 'lsp.tools.lsp_signature'
--- Provides Insert- and Normal-mode mapping for LSP signature help / hover preview.
--- Toggle: <C-b>
--- - Normal mode: the popup opens and takes focus, so it can be scrolled and
---   copied from.
--- - Insert mode: the popup opens but focus stays in the buffer, so typing
---   continues uninterrupted.
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
