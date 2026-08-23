---@module 'lsp.languages.app.java'
--- Java QoL: 4-space indent on FileType, plus organizing imports
--- (`source.organizeImports` code action) on every BufWritePre.

local M = {}

local api = vim.api
local Autocmd = require("lib.nvim.autocmd")

---@return nil
function M.enable()
  local grp = api.nvim_create_augroup("LangJava", { clear = true })

  Autocmd.create("FileType", function(ev)
    local bufnr = ev.buf

    -- Set reasonable defaults
    vim.bo[bufnr].shiftwidth = 4
    vim.bo[bufnr].tabstop = 4
    vim.bo[bufnr].expandtab = true

    -- Organize imports on save
    Autocmd.create("BufWritePre", function()
      vim.lsp.buf.code_action({
        context = { only = { "source.organizeImports" } },
        apply = true,
      })
    end, {
      buffer = bufnr,
    })
  end, {
    group = grp,
    pattern = { "java" },
  })
end

---@type Lsp.Languages.ConfiguredLangs.Java.Module
return M
