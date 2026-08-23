---@module 'lsp.languages.webdev.astro.autocmds'
--- Astro QoL autocmds: format-on-save (conform, falling back to
--- `vim.lsp.buf.format`), organize-imports-on-save, 2-space indent plus
--- `{/* %s */}` commentstring, and frontmatter (`---`) syntax highlighting.

local Autocmd = require("lib.nvim.autocmd")

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
  Autocmd.create("BufWritePre", function(_)
    vim.lsp.buf.code_action({
      context = { only = { "source.organizeImports.astro" } },
      apply = true,
    })
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
