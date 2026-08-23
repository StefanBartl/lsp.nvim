---@module 'lsp.languages.app.dart'
--- Dart QoL: 2-space indent on FileType, plus `<leader>fr` to run
--- `flutter run --hot-reload` in a shell.

local M = {}

local api = vim.api
local Autocmd = require("lib.nvim.autocmd")
local map = require("lib.nvim.map")
local notify = require("lib.nvim.notify").create("[lsp.languages.app.dart]")

---@return nil
function M.enable()
  local grp = api.nvim_create_augroup("LangDart", { clear = true })

  Autocmd.create("FileType", function(ev)
    local bufnr = ev.buf

    vim.bo[bufnr].shiftwidth = 2
    vim.bo[bufnr].tabstop = 2
    vim.bo[bufnr].expandtab = true

    -- Hot reload keybinding for Flutter
    map("n", "<leader>fr", function()
      notify.info("Flutter: Hot Reload")
      vim.cmd("!flutter run --hot-reload")
    end, { buffer = bufnr, desc = "Flutter: Hot Reload" })
  end, {
    group = grp,
    pattern = { "dart" },
  })
end

---@type Lsp.Languages.ConfiguredLangs.Dart.Module
return M
