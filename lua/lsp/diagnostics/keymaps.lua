---@module 'lsp.diagnostics.keymaps'
--- Keymap setup for diagnostics navigation.

local loclist = require("lsp.diagnostics.loclist")
local quickfix = require("lsp.diagnostics.quickfix")

local M = {}

---@param map function|nil
---@return nil
function M.enable(map)
  map = map or vim.keymap.set

  -- Leader mappings (mirrored by user commands)
  map("n", "<leader>wq", function()
    quickfix.to_qf({ open = true })
  end, { desc = "Diagnostics → Quickfix (workspace)" })

  map("n", "<leader>lq", function()
    loclist.to_loc({ open = true, win_id = 0 })
  end, { desc = "Diagnostics → Loclist (buffer)" })

  -- Loclist navigation
  map({ "n", "x", "o" }, "]d", function()
    loclist.next_loc(nil)
  end, { desc = "Next diagnostic (buffer)" })

  map({ "n", "x", "o" }, "[d", function()
    loclist.prev_loc(nil)
  end, { desc = "Prev diagnostic (buffer)" })

  -- Quickfix navigation
  map("n", "]q", function()
    quickfix.next_qf()
  end, { desc = "Next quickfix diagnostic" })

  map("n", "[q", function()
    quickfix.prev_qf()
  end, { desc = "Prev quickfix diagnostic" })
end

return M
