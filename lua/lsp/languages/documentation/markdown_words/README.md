# md_words.nvim (`markdown_words.lua`)

Ein maßgeschneidertes **nvim-cmp** Source-Modul für Neovim, das **projektweite** Wortvervollständigungen für Markdown- und MDX-Dateien bereitstellt.

Während Language Server wie `marksman` hervorragend für projektübergreifende Link- und Überschriften-Completions sorgen, fehlt ihnen oft die Fähigkeit, normale Wörter aus *anderen* Dateien des Projekts als Vervollständigung vorzuschlagen. Dieses Modul schließt diese Lücke, indem es das Projektverzeichnis im Hintergrund scannt, tokenisiert und als flüssige Completion bereitstellt.

---

## Table of content

- [md_words.nvim (`markdown_words.lua`)](#md_wordsnvim-markdown_wordslua)
  - [Features](#features)
  - [🚀 Installation & Integration](#installation-integration)
    - [1. Datei ablegen](#1-datei-ablegen)
    - [2. In den Markdown-Setup einbinden](#2-in-den-markdown-setup-einbinden)
  - [⚙️ Konfiguration](#konfiguration)
  - [🎮 User Commands (Befehle)](#user-commands-befehle)
  - [🛠️ Funktionsweise im Hintergrund](#funktionsweise-im-hintergrund)

---

## Features

* **Projektweiter Scan:** Analysiert asynchron alle `.md` und `.mdx` Dateien unterhalb des Projekt-Wurzelverzeichnisses (Root).
* **Asynchron & Non-blocking:** Nutzt `libuv` (`vim.uv`) im Hintergrund. Große Verzeichnisse blockieren niemals die UI von Neovim.
* **Intelligenter Cache:** Der Scan läuft genau einmal (lazy) beim Öffnen der ersten Markdown-Datei und cached das Ergebnis für die restliche Session.
* **Verzeichnis-Awareness:** Wechselst du im Editor das Verzeichnis (`DirChanged`), baut sich der Cache nach 3 Sekunden automatisch im Hintergrund neu auf (debounced).
* **Schutzmechanismen:** Ignoriert automatisch typische Ordner (wie `.git`, `node_modules`, `dist`, `target`) und überspringt Dateien, die zu groß sind.

---

## 🚀 Installation & Integration

### 1. Datei ablegen

Speichere den Code des Moduls in deinem Neovim-Konfigurationsordner unter:
`lua/lsp/languages/documentation/markdown_words.lua`

### 2. In den Markdown-Setup einbinden

Rufe einfach die `.setup()`-Methode in deiner bestehenden Konfiguration auf – am besten dort, wo dein Markdown-LSP initialisiert wird (z. B. am Ende deiner `M.enable()`-Funktion in `lua/lsp/languages/documentation/markdown.lua`):

```lua
function M.enable()
  -- ... dein bestehender Code (z.B. marksman /lspconfig setup) ...

  -- Projektweite Wort-Completions aktivieren
  require("lsp.languages.documentation.markdown_words").setup()
end

```

---

## ⚙️ Konfiguration

Das Modul funktioniert *Out of the Box* mit sinnvollen Standardwerten. Bei Bedarf kannst du der `setup()`-Funktion jedoch eine Tabelle mit eigenen Optionen übergeben:

```lua
require("lsp.languages.documentation.markdown_words").setup({
  max_files    = 500,           -- Maximale Anzahl zu scannender Dateien
  max_filesize = 204800,        -- Dateien über 200 KB werden ignoriert
  min_word_len = 3,             -- Wörter müssen mindestens 3 Zeichen lang sein
  max_word_len = 60,            -- Wörter über 60 Zeichen werden ignoriert
  filetypes    = { "md", "mdx" },-- Dateiendungen, die gescannt werden
  debounce_ms  = 3000,          -- Wartezeit für Auto-Rebuild nach ':cd'
})

```

---

## 🎮 User Commands (Befehle)

Das Modul registriert automatisch drei nützliche Befehle in Neovim:

| Befehl | Auswirkung |
| --- | --- |
| `:MdSetRoot ~/mein/projekt` | Setzt das Scan-Verzeichnis explizit manuell und erzwingt einen Rebuild. |
| `:MdSetRoot` *(ohne Pfad)* | Setzt den Root wieder zurück auf das aktuelle Arbeitsverzeichnis (`cwd`). |
| `:MdRebuildWords` | Invalidiert den aktuellen Cache und scannt das aktuelle Verzeichnis sofort neu. |
| `:MdWordStats` | Zeigt in der Statuszeile Statistiken an (Aktueller Pfad, Anzahl geladener Wörter, Cache-Status). |

> 💡 **Hinweis zum Verhalten:** Wenn du den Root-Pfad einmal explizit mit `:MdSetRoot /pfad` festlegst, wird der automatische Rebuild durch den Wechsel des Verzeichnisses (`DirChanged`) blockiert, damit deine Arbeit nicht überschrieben wird.

---

## 🛠️ Funktionsweise im Hintergrund

1. **Trigger:** Sobald ein Buffer mit dem Filetype `markdown` oder `mdx` geöffnet wird, erwacht das Modul.
2. **Scan:** Es sammelt rekursiv alle relevanten Dateien, bereinigt sie von Markdown-Syntaxzeichen (wie `*`, `#`, `_`) und extrahiert pure Text-Token.
3. **Injektion:** Die Wörter werden stabil sortiert und als Quelle `md_words` mit einer niedrigen Priorität (`priority = 100`) an `nvim-cmp` übergeben, damit sie normale LSP-Vorschläge (wie Links) nicht überlagern.
