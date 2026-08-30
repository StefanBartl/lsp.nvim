# lsp_signature – developer README

## Table of content

  - [Overview](#overview)
  - [How it works](#how-it-works)
  - [The hover cache](#the-hover-cache)
  - [Parameter highlighting](#parameter-highlighting)
    - [Logic](#logic)
    - [Example highlight groups](#example-highlight-groups)
  - [Wiring it into the project](#wiring-it-into-the-project)
  - [Signature formatting](#signature-formatting)
  - [Extensions for other languages / libraries](#extensions-for-other-languages--libraries)
    - [Proof of concept: additional signatures](#proof-of-concept-additional-signatures)
    - [Applying it to other languages / libraries](#applying-it-to-other-languages--libraries)
  - [Tips for developers](#tips-for-developers)
  - [Possible extensions](#possible-extensions)
  - [After-FT extension](#after-ft-extension)
    - [Project structure](#project-structure)
    - [Example `after/plugin/lsp_signature.lua`](#example-afterpluginlsp_signaturelua)
    - [Notes](#notes)
    - [Demo](#demo)

---

## Overview

`lsp_signature` is a Neovim module that provides a **convenient floating popup for
function signatures and hover information**. It offers:

* A **toggle for insert and normal mode** (`<C-b>`) to show signatures and hover info.
* **Persistent floating popups** that stay visible until `<C-b>` is pressed again.
* **Parameter highlighting** that colours all parameters differently and marks the
  **active parameter** specially.
* **A fallback to hover** if the LSP provides no signatures.
* Extensibility for **non-LSP signatures**, e.g. your own type information, library
  functions, or languages without full LSP support.

---

## How it works

1. **Keymap/toggle**:
   * `<C-b>` opens the floating popup.
   * The popup stays open, insert mode is preserved.
   * `<C-b>` again closes the popup.
   * `<Esc>` inside the popup closes the window immediately.

2. **LSP integration**:
   * Uses `textDocument/signatureHelp` by preference.
   * If signatures are not available, `textDocument/hover` is queried.
   * Takes modern Neovim APIs (`client.server_capabilities`) into account for LSP
     feature detection.

1. **Floating popup**:
   * A focusable window, usable for scrolling or copying.
   * Maximum width: 60% of the screen width.
   * Automatic positioning above or below the cursor, depending on the available space.
   * Border style: `rounded`.

---

## The hover cache

`<C-b>` is a toggle, so looking at the same thing twice means close, open, and
wait for the server again. It does not have to: hover for a position is a
function of the buffer text, and the text is versioned by `changedtick`. The
**displayable lines** — past the request and past `format_hover` — are kept in
an LRU from `lib.lua.memo`, capacity 32, so a repeat on an unedited buffer
renders without a roundtrip.

The key is `(bufnr, changedtick, row, col, client ids)`.

The first four are what makes the answer what it is. The client ids are in
there because they are what makes it *stale* otherwise: restart a server and
the buffer has not changed, so `changedtick` still matches, but the new client
carries a new id — the key moves by itself and the old entry is simply never
asked for again. No invalidation autocmd, and so nothing that can drift out of
sync with one.

A request whose `params` carry no position is **not** cached at all. Guessing a
key there would collapse two different questions onto one answer, and a hover
popup that shows the wrong position is worse than the roundtrip it saved.

`show_hover.clear_cache()` empties it. Nothing in the plugin calls it — the key
retires its own entries — but a cache with no way to empty it is a cache one
cannot debug.

Covered by `TESTS/lsp/hover_cache_spec.lua`, which is mostly about the misses:
an edit, a different position and a replaced client each have to reach the
wire.

---

## Parameter highlighting

### Logic

* All parameters of a signature are detected (`signatureHelp.signatures[].parameters`).
* **Active parameter**: its own highlight group `LspSignatureActiveParam`.
* **Other parameters**: cycled through the highlight groups `LspSignatureParam1..N`.
* Temporary highlights are created via `vim.hl.range()` and disappear when the popup
  is closed.
* For complex signatures (several lines) the logic can be extended to handle lines
  correctly.

### Example highlight groups

```vim
highlight LspSignatureParam1 guifg=#ff8800 gui=bold
highlight LspSignatureParam2 guifg=#88ff00 gui=bold
highlight LspSignatureParam3 guifg=#0088ff gui=bold
highlight LspSignatureParam4 guifg=#ff0088 gui=bold
highlight LspSignatureActiveParam guifg=#ffffff guibg=#005f87 gui=bold
```

-

## Wiring it into the project

```lua
require("mappings.lsp_signature").setup()
```

* `<C-b>` is bound for **insert and normal mode**.
* Optionally, the highlight groups can be adjusted in your own colorscheme file.

---

## Signature formatting

* LSP signatures are broken down into **string arrays** via `format_signature_help.lua`.
* The documentation (`sig.documentation`) is appended to the signature.
* Label parsing for parameters:
  * Either **0-based columns** `[start, end]` from the LSP.
  * Or **string matching** for LSPs that provide no positions.

---

## Extensions for other languages / libraries

Not every language or library delivers full signatures over LSP (e.g. Rust, C, Go,
Node.js/libuv). Here you can **define your own signatures and type information**,
which are then shown in the popup like normal signatures.

### Proof of concept: additional signatures

```lua
local custom_signatures = {
  ["uv_loop_new"] = {
    label = "uv_loop_new() -> uv_loop_t*",
    parameters = {},
    documentation = "Creates a new libuv event loop."
  },
  ["uv_timer_init"] = {
    label = "uv_timer_init(loop: uv_loop_t*, handle: uv_timer_t*)",
    parameters = {
      {label = {13, 23}},  -- start/end position within the label
      {label = {32, 44}}
    },
    documentation = "Initialises a timer in libuv."
  },
  ["my_rust_func"] = {
    label = "my_rust_func(a: i32, b: String) -> Result<()>",
    parameters = {
      {label = {14, 18}},  -- "a: i32"
      {label = {20, 28}}   -- "b: String"
    },
    documentation = "Example function for Rust with two parameters."
  }
}

-- Lookup inside the handler before the LSP call
local name = vim.fn.expand("<cword>")
local sig = custom_signatures[name]
if sig then
  local format_signature_help = require("mappings.lsp_signature.format_signature_help")
  local open_floating_preview = require("mappings.lsp_signature.open_floating_preview")
  local lines, hl = format_signature_help(sig)
  local buf, win = open_floating_preview(lines)

  -- Highlighting for the custom signature
  if hl and buf and api.nvim_buf_is_valid(buf) then
    local ns = api.nvim_create_namespace("LspSignatureCustom")
    vim.hl.range(buf, ns, "LspSignatureActiveParam",
                 {hl.line-1, hl.col_start-1},
                 {hl.line-1, hl.col_end},
                 {inclusive = false})
  end
end
```

### Applying it to other languages / libraries

* **Rust**: functions from crates that ship no LSP.
* **C**: standard libraries, your own headers.
* **Go**: internal tools or libraries without gopls support.
* **TypeScript/Node.js**: libuv, fs, net, etc.

With this structure you can feed **arbitrary signatures and type information** into
the popup, so that `<C-b>` works universally.

---

## Tips for developers

1. **Adjust the highlight groups**: for consistent colours in your own colorscheme.
2. **Reuse the namespace**: create `api.nvim_create_namespace` only once per session.
3. **Adjust the popup options**: size, position, border style.
4. **Wire in further signatures**: lookup tables or automatic parsers (e.g. from
   docstrings or header files).
5. **Insert mode**: the popup is focusable, you can scroll or copy, and insert mode
   is preserved.

-

## Possible extensions

* Multi-line parameter highlighting via `vim.hl.range` or extmarks.
* Dynamic highlighting based on parameter types (e.g. int = green, string = blue).
* Inline hints, e.g. `@deprecated`, `experimental`.
* Integration of further languages without LSP support.

---

That gives you a **fully extensible, modern LSP signature module** that supports both
LSP data and user-defined signatures, with a toggle, persistent popups and coloured
parameter highlighting.

---

## After-FT extension

* LSP signatures from Rust, Go, TypeScript
* libuv functions as user-defined signatures
* Coloured highlighting for all parameters, the active parameter emphasised
* A persistent popup with scroll/copy support

---

### Project structure

```sh
nvim-lsp-signature-demo/
├─ lua/
│  └─ custom/
│     └─ lsp_signature/
│        ├─ init.lua
│        ├─ request_and_show.lua
│        ├─ open_floating_preview.lua
│        ├─ format_signature_help.lua
│        ├─ format_hover.lua
│        └─ split_lines.lua
├─ after/
│  └─ plugin/
│     └─ lsp_signature.lua   -- keymap and toggle setup
└─ README.md
```

---

### Example `after/plugin/lsp_signature.lua`

```lua
local lsp_sig = require("lsp.tools.lsp_signature")
lsp_sig.setup()

-- Optional: additional signatures for Rust, Go, TypeScript, libuv
_G.custom_signatures = {
  -- Rust
  ["my_rust_func"] = {
    label = "my_rust_func(a: i32, b: String) -> Result<()>",
    parameters = {
      {label = {14, 18}},
      {label = {20, 28}}
    },
    documentation = "Example function for Rust."
  },
  -- Go
  ["fmt_Println"] = {
    label = "Println(a ...interface{}) (n int, err error)",
    parameters = {{label={9, 20}}},
    documentation = "The Go fmt.Println function."
  },
  -- TypeScript / Node.js
  ["uv_loop_new"] = {
    label = "uv_loop_new() -> uv_loop_t*",
    parameters = {},
    documentation = "Creates a new libuv event loop."
  }
}

-- Hook in request_and_show.lua:
-- Check before the LSP call: if _G.custom_signatures[vim.fn.expand("<cword>")] then ...
```

---

### Notes

1. **Toggle** `<C-b>` in insert and normal mode.
2. **Persistent popup**: stays open, insert mode is preserved.
3. **Parameter highlighting**: different colours + the active parameter.
4. **Fallback to hover** if the LSP delivers no signatures.
5. **User-defined signatures**: any language/library can be integrated.

---

### Demo

* Rust: `my_rust_func` → `<C-b>` shows the signature + parameter highlighting.
* Go: `fmt_Println` → `<C-b>` shows the signature.
* Node.js/libuv: `uv_loop_new` → `<C-b>` shows the signature.
* The LSP supports further functions, e.g. TypeScript, Lua, Python.

---
