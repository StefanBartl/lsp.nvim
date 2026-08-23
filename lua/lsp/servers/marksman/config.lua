---@module 'lsp.servers.marksman.config'
--- Per-LSP configuration values for marksman diagnostics filtering and optional server init options.

local M = {
  suppress_missing_doc_links = true,
  missing_doc_links_pattern = "^Link to non%-existent document",

  -- list of additional message patterns (Lua patterns) to suppress.
  -- Each pattern is matched against the diagnostic message. Use anchored patterns
  -- or partial substrings. Example: "^Link to non%-existent link" will match
  -- messages starting with that text.
  suppressed_message_patterns = {
    "^Link to non%-existent link", -- suppress "Link to non-existent link definition ..."
    "^Ambiguous link to heading", -- suppress "Ambiguous link to heading '...' "
    -- Add further patterns
  },

  -- list of substrings (plain string matching) for quick filters
  -- Useful when the diagnostic message contains variable parts (IDs, headings).
  suppressed_message_substrings = {
    "TOC", -- suppress messages that mention TOC (table of contents)
    "table of contents", -- case-sensitive; add lower/upper variants if needed
    -- Add more substrings
  },

  -- boolean to disable TOC-specific checks heuristically by filtering any diag
  -- that mentions 'TOC' / 'table of contents'. This is client-side only.
  suppress_toc_checks = true,

  -- allow suppression by diagnostic 'code' if server emits numeric/string codes.
  -- Example: { "MD001", "MD002", 1001 }  -- mixed types supported (string or number)
  suppressed_codes = {
    -- Add known marksman diagnostic codes here if available.
    -- Example entries (placeholders): "TOC001", "LINK002"
  },

  -- Existing fallbacks and filetypes
  root_dir_fallbacks = { ".marksman.toml", ".git", "mkdocs.yml" },
  filetypes = { "markdown", "markdown.mdx" },
}

return M
