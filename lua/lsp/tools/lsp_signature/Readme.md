# lsp_signature – Entwickler-README

## Table of content

  - [Übersicht](#bersicht)
  - [Funktionsweise](#funktionsweise)
  - [Parameter-Highlighting](#parameter-highlighting)
    - [Logik](#logik)
    - [Beispiel Highlight-Gruppen](#beispiel-highlight-gruppen)
  - [Einbindung ins Projekt](#einbindung-ins-projekt)
  - [Signatur-Formatierung](#signatur-formatierung)
  - [Erweiterungen für andere Sprachen / Bibliotheken](#erweiterungen-fr-andere-sprachen-bibliotheken)
    - [Proof-of-Concept: zusätzliche Signaturen](#proof-of-concept-zustzliche-signaturen)
    - [Anwendung auf andere Sprachen / Bibliotheken](#anwendung-auf-andere-sprachen-bibliotheken)
  - [Tipps für Entwickler](#tipps-fr-entwickler)
  - [Erweiterungsmöglichkeiten](#erweiterungsmglichkeiten)
  - [After-FT Erweiterung](#after-ft-erweiterung)
    - [Projektstruktur](#projektstruktur)
    - [Beispiel `after/plugin/lsp_signature.lua`](#beispiel-afterpluginlsp_signaturelua)
    - [Hinweise](#hinweise)
    - [Demo](#demo)

---

## Übersicht

`lsp_signature` ist ein Neovim-Modul, das ein **komfortables Floating-Popup für Funktionssignaturen und Hover-Informationen** bereitstellt. Es bietet:

* Ein **Toggle für Insert- und Normalmodus** (`<C-b>`), um Signaturen und Hover-Infos anzuzeigen.
* **Persistente Floating-Popups**, die sichtbar bleiben, bis `<C-b>` erneut gedrückt wird.
* **Parameter-Highlighting**, das alle Parameter farblich unterscheidet und den **aktiven Parameter** besonders markiert.
* **Fallback auf Hover**, falls keine Signaturen vom LSP bereitgestellt werden.
* Erweiterbarkeit für **nicht-LSP-Signaturen**, z. B. eigene Typinformationen, Bibliotheksfunktionen oder Sprachen ohne vollständige LSP-Unterstützung.

---

## Funktionsweise

1. **Keymap/Toggle**:
   * `<C-b>` öffnet das Floating-Popup.
   * Popup bleibt offen, Insertmodus wird beibehalten.
   * `<C-b>` erneut schließt das Popup.
   * `<Esc>` innerhalb des Popups schließt das Fenster sofort.

2. **LSP-Integration**:
   * Verwendet `textDocument/signatureHelp` bevorzugt.
   * Falls Signaturen nicht verfügbar sind, wird `textDocument/hover` abgefragt.
   * Berücksichtigt moderne Neovim-APIs (`client.server_capabilities`) für LSP-Feature-Erkennung.

1. **Floating-Popup**:
   * Fokusierbares Fenster, kann für Scrollen oder Kopieren verwendet werden.
   * Maximale Breite: 60% der Bildschirmbreite.
   * Automatisches Positionieren über oder unter dem Cursor, abhängig vom verfügbaren Platz.
   * Rahmendesign: `rounded`.

---

## Parameter-Highlighting

### Logik

* Alle Parameter einer Signatur werden erkannt (`signatureHelp.signatures[].parameters`).
* **Aktiver Parameter**: eigene Highlight-Gruppe `LspSignatureActiveParam`.
* **Andere Parameter**: zyklisch durch Highlight-Gruppen `LspSignatureParam1..N`.
* Temporäre Highlights werden über `vim.hl.range()` erstellt, verschwinden beim Schließen des Popups.
* Für komplexe Signaturen (mehrere Zeilen) kann die Logik erweitert werden, um Zeilen korrekt zu berücksichtigen.

### Beispiel Highlight-Gruppen

```vim
highlight LspSignatureParam1 guifg=#ff8800 gui=bold
highlight LspSignatureParam2 guifg=#88ff00 gui=bold
highlight LspSignatureParam3 guifg=#0088ff gui=bold
highlight LspSignatureParam4 guifg=#ff0088 gui=bold
highlight LspSignatureActiveParam guifg=#ffffff guibg=#005f87 gui=bold
```

-

## Einbindung ins Projekt

```lua
require("mappings.lsp_signature").setup()
```

* `<C-b>` wird für **Insert- und Normalmodus** gebunden.
* Optional kann man die Highlight-Gruppen in der eigenen Colorscheme-Datei anpassen.

---

## Signatur-Formatierung

* LSP-Signaturen werden via `format_signature_help.lua` in **String-Arrays** zerlegt.
* Dokumentation (`sig.documentation`) wird an die Signatur angehängt.
* Label-Parsing für Parameter:
  * Entweder **0-basierte Spalten** `[start, end]` vom LSP.
  * Oder **String-Matching** für LSPs, die keine Positionsangaben liefern.

---

## Erweiterungen für andere Sprachen / Bibliotheken

Nicht alle Sprachen oder Bibliotheken liefern über LSP vollständige Signaturen (z. B. Rust, C, Go, Node.js/libuv). Hier kann man **eigene Signaturen und Typinformationen definieren**, die dann wie normale Signaturen im Popup angezeigt werden.

### Proof-of-Concept: zusätzliche Signaturen

```lua
local custom_signatures = {
  ["uv_loop_new"] = {
    label = "uv_loop_new() -> uv_loop_t*",
    parameters = {},
    documentation = "Erstellt einen neuen libuv Event-Loop."
  },
  ["uv_timer_init"] = {
    label = "uv_timer_init(loop: uv_loop_t*, handle: uv_timer_t*)",
    parameters = {
      {label = {13, 23}},  -- Start/End-Position innerhalb des Labels
      {label = {32, 44}}
    },
    documentation = "Initialisiert einen Timer in libuv."
  },
  ["my_rust_func"] = {
    label = "my_rust_func(a: i32, b: String) -> Result<()>",
    parameters = {
      {label = {14, 18}},  -- "a: i32"
      {label = {20, 28}}   -- "b: String"
    },
    documentation = "Beispiel-Funktion für Rust mit zwei Parametern."
  }
}

-- Lookup innerhalb des Handlers vor LSP-Aufruf
local name = vim.fn.expand("<cword>")
local sig = custom_signatures[name]
if sig then
  local format_signature_help = require("mappings.lsp_signature.format_signature_help")
  local open_floating_preview = require("mappings.lsp_signature.open_floating_preview")
  local lines, hl = format_signature_help(sig)
  local buf, win = open_floating_preview(lines)

  -- Highlighting für benutzerdefinierte Signatur
  if hl and buf and api.nvim_buf_is_valid(buf) then
    local ns = api.nvim_create_namespace("LspSignatureCustom")
    vim.hl.range(buf, ns, "LspSignatureActiveParam",
                 {hl.line-1, hl.col_start-1},
                 {hl.line-1, hl.col_end},
                 {inclusive = false})
  end
end
```

### Anwendung auf andere Sprachen / Bibliotheken

* **Rust**: Funktionen aus Crates, die kein LSP liefern.
* **C**: Standardbibliotheken, eigene Header.
* **Go**: interne Tools oder Bibliotheken ohne gopls-Unterstützung.
* **TypeScript/Node.js**: libuv, fs, net, etc.

Mit dieser Struktur kann man **beliebige Signaturen und Typinformationen** in das Popup einspeisen, sodass `<C-b>` universell funktioniert.

---

## Tipps für Entwickler

1. **Highlight-Gruppen anpassen**: Für konsistente Farben im eigenen Colorscheme.
2. **Namespace wiederverwenden**: `api.nvim_create_namespace` nur einmal pro Session erzeugen.
3. **Popup-Optionen anpassen**: Größe, Position, Rahmenstil.
4. **Weitere Signaturen einbinden**: Lookup-Tabellen oder automatische Parsers (z. B. aus Docstrings oder Header-Files).
5. **Insertmodus**: Popup ist focusable, man kann scrollen oder kopieren, Insertmodus bleibt erhalten.

-

## Erweiterungsmöglichkeiten

* Mehrzeilige Parameter-Highlighting über `vim.hl.range` oder Extmarks.
* Dynamisches Highlighting basierend auf Parametertypen (z. B. int = grün, string = blau).
* Inline-Tipps, z. B. `@deprecated`, `experimental`.
* Integration weiterer Sprachen ohne LSP-Unterstützung.

---

Damit hast du ein **vollständig erweiterbares, modernes LSP-Signaturmodul**, das sowohl LSP-Daten als auch benutzerdefinierte Signaturen unterstützt, mit Toggle, persistenten Popups und farbigem Parameter-Highlighting.

---

## After-FT Erweiterung

* LSP-Signaturen aus Rust, Go, TypeScript
* Libuv-Funktionen als benutzerdefinierte Signaturen
* Farbliches Highlighting für alle Parameter, aktiver Parameter hervorgehoben
* Persistentes Popup mit Scroll-/Copy-Funktion

---

### Projektstruktur

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
│     └─ lsp_signature.lua   -- Setup Keymap und Toggle
└─ README.md
```

---

### Beispiel `after/plugin/lsp_signature.lua`

```lua
local lsp_sig = require("lsp.tools.lsp_signature")
lsp_sig.setup()

-- Optional: zusätzliche Signaturen für Rust, Go, TypeScript, libuv
_G.custom_signatures = {
  -- Rust
  ["my_rust_func"] = {
    label = "my_rust_func(a: i32, b: String) -> Result<()>",
    parameters = {
      {label = {14, 18}},
      {label = {20, 28}}
    },
    documentation = "Beispiel-Funktion für Rust."
  },
  -- Go
  ["fmt_Println"] = {
    label = "Println(a ...interface{}) (n int, err error)",
    parameters = {{label={9, 20}}},
    documentation = "Go fmt.Println Funktion."
  },
  -- TypeScript / Node.js
  ["uv_loop_new"] = {
    label = "uv_loop_new() -> uv_loop_t*",
    parameters = {},
    documentation = "Erstellt einen neuen libuv Event-Loop."
  }
}

-- Hook in request_and_show.lua:
-- Vor LSP-Aufruf prüfen: if _G.custom_signatures[vim.fn.expand("<cword>")] then ...
```

---

### Hinweise

1. **Toggle** `<C-b>` in Insert- und Normalmodus.
2. **Persistent Popup**: bleibt offen, Insertmodus bleibt erhalten.
3. **Parameter-Highlighting**: unterschiedliche Farben + aktiver Parameter.
4. **Fallback auf Hover**, falls LSP keine Signaturen liefert.
5. **Benutzerdefinierte Signaturen**: beliebige Sprache/Bibliothek integrierbar.

---

### Demo

* Rust: `my_rust_func` → `<C-b>` zeigt Signatur + Parameter-Highlighting.
* Go: `fmt_Println` → `<C-b>` zeigt Signatur.
* Node.js/libuv: `uv_loop_new` → `<C-b>` zeigt Signatur.
* LSP unterstützt zusätzliche Funktionen, z. B. TypeScript, Lua, Python.

---
