# Formatter

Conform-first with an LSP fallback, and a format-on-save toggle that preserves
every window's view across the write. `conform.setup()` is called in exactly one
place; the plugin's own autocommand owns format-on-save, never conform's option.

`:LspDoctor`'s formatter section asks conform itself what would run
(`list_formatters_to_run`) rather than deciding a second time, so the report
cannot disagree with a real format. `lspdoctor.formatter_priority` only ranks
the LSP clients listed beneath that — it chooses nothing, which is why it lives
in the reporting namespace.

- **Module:** `formatter/`, `integrations/conform.lua`, `lspdoctor/inspect.lua`
- **Config:** `formatter.on_save`, `formatter.timeout_ms`,
  `lspdoctor.formatter_priority` (report only)
- **Commands:** `:Lsp format [once|on|off|toggle|status|which]`
- **Keys:** `<leader>ft` (once), `<leader>fl` (via the language server),
  `<leader>tft` (toggle on-save)
