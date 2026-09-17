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

    -- Organize imports on save. In the group, and only once per buffer:
    -- FileType fires again every time the file is re-read (`:e`, `:e!`,
    -- `:set ft=java`), and a groupless nested autocmd has nothing to
    -- overwrite. Measured on one Probe.java: after the initial `:edit` plus
    -- two `:edit!` the buffer carried 3 buffer-local BufWritePre handlers and
    -- a single `:w` made 3 organize-imports round trips -- three blocking
    -- `textDocument/codeAction` requests of up to a second each, applying the
    -- same edit three times. `enable()` again did not clean them up either:
    -- clearing `LangJava` cannot touch an autocmd that is in no group. The
    -- flip side of the group is that a re-`enable()` now drops the handler
    -- from buffers that are already open too -- the same contract the FileType
    -- autocmd beside it has always had, and the next `:e` puts it back.
    local already = api.nvim_get_autocmds({
      event = "BufWritePre",
      group = grp,
      buffer = bufnr,
    })
    if #already == 0 then
      Autocmd.create("BufWritePre", function(bev)
        pcall(util.organize_imports_sync, bev.buf, "source.organizeImports")
      end, {
        group = grp,
        buffer = bufnr,
      })
    end
  end, {
    group = grp,
    pattern = { "java" },
  })
end

---@type Lsp.Languages.ConfiguredLangs.Java.Module
return M
