---@module 'lsp.languages.webdev.html'
--- HTML language enablement helpers for autocommands and small QoL.

local Autocmd = require("lib.nvim.autocmd")

local M = {}

---@return nil
function M.enable()
  local grp = Autocmd.group("LangHtml", true)
  Autocmd.create("FileType", function(event)
    -- Example small QoL: ensure omnifunc is set for legacy completion fallback
    local bufnr = event.buf
    pcall(function()
      vim.api.nvim_set_option_value("omnifunc", "v:lua.vim.lsp.omnifunc", { buf = bufnr })
    end)
  end, {
    group = grp,
    pattern = { "html", "htmldjango", "djangohtml" },
  })
end

---@type Lsp.Languages.ConfiguredLangs.Webdev.HTML.Module
return M
