---@module 'lsp.languages.app.java'
--- Java QoL: 4-space indent on FileType, plus organizing imports
--- (`source.organizeImports` code action) on every BufWritePre.
---
--- The organize-imports request runs through `lsp.core.util.organize_imports_sync`
--- rather than `vim.lsp.buf.code_action({ apply = true })`: that call is
--- asynchronous, so on `BufWritePre` it returned before the server's response
--- (and the edit it carries) ever arrived -- the file was written to disk
--- first, and the import reorganization landed one save late, against
--- whatever the buffer had become by the time the response showed up. See
--- that function's docstring for the full explanation.

local M = {}

local api = vim.api
local Autocmd = require("lib.nvim.bindings.autocmd")
local util = require("lsp.core.util")

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
    Autocmd.create("BufWritePre", function(bev)
      pcall(util.organize_imports_sync, bev.buf, "source.organizeImports")
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
