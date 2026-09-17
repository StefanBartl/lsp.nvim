---@module 'lsp.languages.documentation.markdown'
---@brief Markdown-filetype QoL: buffer options, highlights, format commands, md_words.

local api = vim.api
local lsp = vim.lsp
local desc_tag = "[lsp] "
local Autocmd = require("lib.nvim.bindings.autocmd")
local usercmd = require("lib.nvim.bindings.usercmd")
local map = require("lib.nvim.bindings.keymap")

local M = {}

-- ============================================================================
-- Highlight setup
-- ============================================================================

--- Define the LSP document-highlight groups.
---
--- These are **global** highlight groups (namespace 0), not markdown-scoped
--- ones -- the docstring here used to claim "for markdown buffers", which
--- namespace 0 cannot do. `enable()` calls this once and again on
--- `ColorScheme`, because it used to run inside the FileType callback:
--- measured, opening three markdown buffers rewrote the three groups nine
--- times, and each write replaced whatever the colourscheme had set for every
--- buffer in the session (a `LspReferenceText` of `fg = #123456` came back as
--- `fg = #FFFFFF, bg = #2b2b2b, italic`). Opening a markdown file is not a
--- reason to restyle references in the Go buffer next to it.
---@return nil
function M.setup_reference_hl()
  api.nvim_set_hl(0, "LspReferenceText", { fg = "#FFFFFF", bg = "#2b2b2b", italic = true })
  api.nvim_set_hl(0, "LspReferenceRead", { fg = "#FFFFFF", bg = "#2b2b2b" })
  api.nvim_set_hl(0, "LspReferenceWrite", { fg = "#FFFFFF", bg = "#3a2b2b", bold = true })
end

-- ============================================================================
-- Enable
-- ============================================================================

---@return nil
function M.enable()
  local grp = api.nvim_create_augroup("LangMarkdownQoL", { clear = true })

  -- Once, plus on every colourscheme change -- not once per markdown buffer.
  -- See `setup_reference_hl`.
  M.setup_reference_hl()
  Autocmd.create("ColorScheme", function()
    M.setup_reference_hl()
  end, {
    group = grp,
    pattern = "*",
    desc = desc_tag .. "Re-apply LSP reference highlights after a colourscheme change",
  })

  -- ------------------------------------------------------------------
  -- Per-buffer FileType setup
  -- ------------------------------------------------------------------
  Autocmd.create("FileType", function(ev)
    if not (ev and ev.buf) then
      return
    end

    local bo = vim.bo[ev.buf]
    local bt = bo.buftype or ""

    -- Only touch encoding on normal, modifiable files
    if bt == "" and bo.modifiable then
      bo.fileencoding = "utf-8"
      bo.bomb = false
    end

    bo.textwidth = 0
    bo.formatoptions = "jnql"

    -- Buffer-local format keymap
    map("n", "<leader>fm", function()
      local ok, conform = pcall(require, "conform")
      if ok and type(conform.format) == "function" then
        conform.format({ bufnr = ev.buf, timeout_ms = 2000, lsp_fallback = false })
      else
        lsp.buf.format({ bufnr = ev.buf, timeout_ms = 2000 })
      end
    end, { buffer = ev.buf, silent = true, desc = desc_tag .. "Format markdown buffer" })
  end, {
    group = grp,
    pattern = { "markdown", "mdx" },
    desc = desc_tag .. "Markdown QoL: UTF-8, soft defaults, format keymap",
  })

  -- ------------------------------------------------------------------
  -- User commands
  -- ------------------------------------------------------------------
  usercmd.create("MdFormat", function()
    local ft = vim.bo.filetype
    local ok, conform = pcall(require, "conform")
    if not ok or type(conform.format) ~= "function" then
      lsp.buf.format({ timeout_ms = 2000 })
      return
    end
    local formatters = ft == "markdown" and { "mdformat", "prettierd", "prettier" }
      or { "prettierd", "prettier" }
    conform.format({ formatters = formatters, timeout_ms = 2000, lsp_fallback = false })
  end, { desc = desc_tag .. "Format Markdown (prefer mdformat for .md)" })

  usercmd.create("MdFormatPrettier", function()
    local ok, conform = pcall(require, "conform")
    if ok and type(conform.format) == "function" then
      conform.format({
        formatters = { "prettierd", "prettier" },
        timeout_ms = 2000,
        lsp_fallback = false,
      })
    else
      lsp.buf.format({ timeout_ms = 2000 })
    end
  end, { desc = desc_tag .. "Format via Prettier" })

  -- ------------------------------------------------------------------
  -- Project-wide word completions for Markdown
  -- ------------------------------------------------------------------
  local ok_words, md_words = pcall(require, "lsp.languages.documentation.markdown_words")
  if ok_words then
    md_words.setup()
  end
end

return M
