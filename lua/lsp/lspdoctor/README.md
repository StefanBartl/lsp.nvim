# LSP Doctor

Small, dependency-free helper to inspect Neovim’s LSP state for the current buffer and the overall session. It provides a quick summary, a deep report, a scratch-buffer export, and a health-style output inspired by `:checkhealth`.

Linux/macOS focused. Neovim 0.9+ (0.10+ recommended).

---

## Table of content

- [LSP Doctor](#lsp-doctor)
  - [Features](#features)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Commands](#commands)
  - [Usage Examples](#usage-examples)
  - [Configuration](#configuration)
  - [What the reports show](#what-the-reports-show)
  - [Formatter policy](#formatter-policy)
  - [Offset encoding mismatch](#offset-encoding-mismatch)
  - [Scratch export](#scratch-export)
  - [Health-style output](#health-style-output)
  - [API](#api)
  - [Troubleshooting](#troubleshooting)
  - [FAQ](#faq)
  - [Development](#development)

---

## Features

* Quick and deep LSP reports (on-demand, non-blocking)
* Detects offset-encoding mismatches (e.g., mixed `utf-8` / `utf-16`)
* Summarizes diagnostics per severity for the current buffer
* Displays capabilities: formatting, code actions, semantic tokens, CodeLens, inlay hints, etc.
* Workspace inspection: `root_dir`, workspace folders, buffer-under-root check
* Formatter policy with a clear winner selection (priority list → alphabetical fallback)
* Optional probes:

  * CodeLens/InlayHints support and best-effort “enabled” status
  * Semantic Tokens request probe with short timeout
  * External tools check (rg, fd, jq, eslint, prettier, stylua, lua-language-server)
* Export renderer that writes the report to a scratch buffer (read-only) with helpful mappings
* Health-style summary via `:LspDoctor health`
* Print vs. notify output (configurable)

---

## Requirements

* Neovim 0.9 or newer (0.10+ recommended for inlay hint APIs)
* Linux/macOS (Windows not actively supported)

No hard runtime dependencies. Optional integrations (only if installed): `trouble.nvim`, `fidget.nvim`, `nvim-navic`.

---

## Installation

Example with Lazy.nvim using a local module:

```lua
{
  dir = vim.fn.stdpath("config") .. "/nvim/usrcmds/lspdoctor",
  name = "lspdoctor",
  lazy = true,
  config = function()
    require("usrcmds.lspdoctor").setup({
      use_notify = false,
      list_limit = 8,
      show_capabilities = true,
      show_workspace = true,
      show_tools = true,
      show_conflicts = true,
      formatter_priority = { "eslint", "null-ls", "lua_ls" },
      semantic_tokens_timeout = 300,
      scratch_filetype = "markdown",
    })
    require("usrcmds.lspdoctor").enable_usercmd()
  end,
  cmd = { "LspDoctor" },
}
```

---

## Commands

```
:LspDoctor          quick report (message area)
:LspDoctor!         deep report (message area)
:LspDoctor export   quick report → scratch buffer (read-only)
:LspDoctor! export  deep report → scratch buffer (read-only)
:LspDoctor health   health-style summary (message area)
```

Notes:

* `!` (bang) selects “deep” mode.
* `export` opens a scratch buffer at the bottom with helpful keymaps:

  * `q` close buffer
  * `y` yank all
  * `gw` write the report to a timestamped file under `stdpath('cache')`

---

## Usage Examples

Minimal usage in a running session:

```vim
:LspDoctor
:LspDoctor! export
:LspDoctor health
```

Programmatic usage:

```lua
-- quick report, returns a structured report object
local rep = require("usrcmds.lspdoctor").run("quick", 0)

-- deep report exported to a scratch buffer, returns bufnr
local bufnr = require("usrcmds.lspdoctor").export("deep", 0)

-- print a health-style summary
require("usrcmds.lspdoctor").health()
```

Suggested mappings:

```lua
vim.keymap.set("n", "<leader>ld", function()
  require("usrcmds.lspdoctor").run("quick", 0)
end, { desc = "LSP Doctor: quick" })

vim.keymap.set("n", "<leader>lD", function()
  require("usrcmds.lspdoctor").run("deep", 0)
end, { desc = "LSP Doctor: deep" })

vim.keymap.set("n", "<leader>le", function()
  require("usrcmds.lspdoctor").export("deep", 0)
end, { desc = "LSP Doctor: export deep" })
```

---

## Configuration

`setup(options)` accepts the following keys (all optional):

| Name                      | Type         | Default      | Description                                                          |
| ------------------------- | ------------ | ------------ | -------------------------------------------------------------------- |
| `use_notify`              | boolean      | `false`      | Render via `vim.notify` instead of `print`.                          |
| `list_limit`              | integer      | `10`         | Max items per section in quick mode.                                 |
| `show_capabilities`       | boolean      | `true`       | Include per-client capability subset in deep mode.                   |
| `show_workspace`          | boolean      | `true`       | Include workspace folders, `root_dir`, and buffer-under-root checks. |
| `show_tools`              | boolean      | `true`       | Show external tools summary.                                         |
| `show_conflicts`          | boolean      | `true`       | Detect overlapping providers (formatting/diagnostics).               |
| `formatter_priority`      | string[]     | `{}`         | Preferred order of formatting providers; first match wins.           |
| `semantic_tokens_timeout` | integer (ms) | `300`        | Timeout for semantic tokens probe.                                   |
| `scratch_filetype`        | string       | `"markdown"` | Filetype for the scratch export buffer.                              |

Example:

```lua
require("usrcmds.lspdoctor").setup({
  use_notify = true,
  formatter_priority = { "eslint", "null-ls", "lua_ls" },
  semantic_tokens_timeout = 250,
})
```

---

## What the reports show

* Clients: attached LSP clients for the current buffer (names)
* Diagnostics: totals per severity (ERROR/WARN/INFO/HINT)
* Provider conflicts: overlapping formatters/diagnostics (if any)
* Offset encodings: unified or mismatched `offset_encoding` across clients
* Formatter policy: candidates + selected winner (priority list → alphabetical)
* Deep-only sections:

  * Workspace: `root_dir`, workspace folders, buffer-under-root status
  * Capabilities: common capability flags per client
  * CodeLens & InlayHints: supported flags and best-effort “enabled” status
  * Semantic tokens: per-client request probe (ok/error/timeout)
  * Tools & optional integrations: tool presence and optional plugins status

---

## Formatter policy

The policy determines which client is considered the “winner” for `textDocument/formatting`:

1. If `formatter_priority` is set, the first name in that list that matches an attached formatting-capable client wins.
2. Otherwise, the first candidate alphabetically is chosen.

The report shows all candidates and the chosen winner, plus the policy reason (“priority list” or “alphabetical fallback”).

---

## Offset encoding mismatch

If different clients attached to the same buffer use different `offset_encoding` values (e.g., `utf-8` vs. `utf-16`), the report warns about it and lists which client uses which encoding. Mixed encodings can cause subtle issues with positions and edits.

---

## Scratch export

`LspDoctor export` opens a read-only scratch buffer containing the full report:

* `q` closes the buffer
* `y` yanks the entire content
* `gw` writes the report to `stdpath('cache')/lspdoctor_YYYYMMDD_HHMMSS.md`

The buffer filetype defaults to `markdown` and can be changed via `scratch_filetype`.

---

## Health-style output

`LspDoctor health` prints a compact, `:checkhealth`-like summary to the message area. It does not depend on or hook into Neovim’s health providers; it only mimics the style for convenience.

---

## API

```lua
-- Configure behavior (call once)
require("usrcmds.lspdoctor").setup(opts)

-- Generate and render a report to the message area
-- mode: "quick" | "deep", bufnr: integer (0 = current)
-- returns: Lsp.Doctor.Report
require("usrcmds.lspdoctor").run(mode, bufnr)

-- Generate and export a report to a scratch buffer
-- returns: bufnr of the scratch buffer
require("usrcmds.lspdoctor").export(mode, bufnr)

-- Print a health-style summary
require("usrcmds.lspdoctor").health()

-- Create :LspDoctor user command with subcommands (export|health) and bang
require("usrcmds.lspdoctor").enable_usercmd()
```

`Lsp.Doctor.Report` (returned by `run`):

```lua
---@class Lsp.Doctor.Report
---@field mode '"quick"'|'"deep"'
---@field ok boolean
---@field summary string
---@field sections { title: string, lines: string[] }[]
---@field extras table<string, any>  -- e.g. formatter_winner, offset_encodings, etc.
```

---

## Troubleshooting

* No clients shown
  Ensure an LSP is configured and attached to the current buffer (check filetype and root detection).

* Unexpected file order or missing diagnostics
  Some servers require project markers (`package.json`, `.git`, etc.) to detect roots correctly. Verify `root_dir`, workspace folders, and that the current buffer is under the root.

* Mixed `offset_encoding` warning
  Prefer aligning clients (e.g., configure `offset_encoding` consistently or reduce the set of attached clients).

* Formatting does not use the expected provider
  Use `formatter_priority` to select the winner deterministically.

* `semantic tokens probe` times out
  Some servers do not implement the full semantic tokens method or require specific initialization. The probe is best-effort.

---

## FAQ

* Why quick vs. deep?
  Quick offers instant insight (clients, diagnostics, conflicts) without noise. Deep adds capabilities, workspace details, and probes for thorough debugging.

* Does it modify editor state?
  No. Reports are read-only. The export opens a scratch buffer but does not modify files or settings.

* Can the export be captured programmatically?
  Yes. Use `export("deep", 0)` to get the buffer number and then read the lines or write the buffer as needed.

---

## Development

* Pure core collection functions without UI side effects
* Defensive guards and `pcall` around optional dependencies
* Minimal allocations and simple data structures
* Clear separation between data collection and rendering
* Linux/macOS only by design; Windows PRs are welcome but not guaranteed

---

