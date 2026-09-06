---@module 'lsp.languages.webdev.astro.autocmds'
--- Astro QoL autocmds: format-on-save (conform, falling back to
--- `vim.lsp.buf.format`), organize-imports-on-save, 2-space indent plus
--- `{/* %s */}` commentstring, and frontmatter (`---`) syntax highlighting.
---
--- The organize-imports request runs through `lsp.core.util.organize_imports_sync`
--- rather than `vim.lsp.buf.code_action({ apply = true })`: that call is
--- asynchronous, so on `BufWritePre` it returned before the server's response
--- (and the edit it carries) ever arrived -- the file was written to disk
--- first, and the import reorganization landed one save late, against
--- whatever the buffer had become by the time the response showed up. See
--- that function's docstring for the full explanation.

local Autocmd = require("lib.nvim.bindings.autocmd")
local util = require("lsp.core.util")

local M = {}

---@return nil
function M.setup()
  local grp = Autocmd.group("AstroQoL", true)

  -- Auto-format on save
  Autocmd.create("BufWritePre", function(ev)
    local ok, conform = pcall(require, "conform")
    if ok then
      conform.format({ bufnr = ev.buf, timeout_ms = 2000 })
    else
      vim.lsp.buf.format({ bufnr = ev.buf, timeout_ms = 2000 })
    end
  end, {
    group = grp,
    pattern = "*.astro",
    desc = "Format Astro file on save",
  })

  -- Auto-organize imports on save
  Autocmd.create("BufWritePre", function(ev)
    pcall(util.organize_imports_sync, ev.buf, "source.organizeImports.astro")
  end, {
    group = grp,
    pattern = "*.astro",
    desc = "Organize imports on save",
  })

  -- Set local options
  Autocmd.create("FileType", function(ev)
    vim.bo[ev.buf].shiftwidth = 2
    vim.bo[ev.buf].tabstop = 2
    vim.bo[ev.buf].expandtab = true
    vim.bo[ev.buf].commentstring = "{/* %s */}"
  end, {
    group = grp,
    pattern = "astro",
    desc = "Set Astro buffer options",
  })

  -- Highlight Astro sections differently
  Autocmd.create("FileType", function()
    -- Custom highlight for frontmatter
    vim.cmd([[syntax region astroFrontmatter start=/^---$/ end=/^---$/]])
    vim.cmd([[highlight link astroFrontmatter Comment]])
  end, {
    group = grp,
    pattern = "astro",
    desc = "Custom Astro syntax highlighting",
  })

  -- Dev-server kill on exit and the missing-component-import check are not
  -- here: both live in insights.nvim (`devserver` / `unimported`),
  -- generalized past Astro and configured via its setup() spec.
end

return M
