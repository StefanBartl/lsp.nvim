# Custom Astro Commands

## keymaps (Astro)

| Modus | Tastenkombination | Beschreibung                                                            |
| ----- | ----------------- | ----------------------------------------------------------------------- |
| n     | gC                | Öffnet Telescope zur Suche nach Astro-Komponenten in src/components     |
| n     | gL                | Öffnet Telescope zur Suche nach Astro-Layouts in src/layouts            |
| n     | gP                | Öffnet Telescope zur Suche nach Astro-Pages in src/pages                |
| n     | <leader>as        | Springt zum nächsten <script>-Block                                     |
| n     | <leader>ay        | Springt zum nächsten <style>-Block                                      |
| n     | <leader>at        | Springt zum Template-Bereich (nach dem Frontmatter)                     |
| n     | <leader>af        | Springt zum Frontmatter-Anfang                                          |
| n     | <leader>an        | Wechselt zyklisch zur nächsten Astro-Sektion (script/style/frontmatter) |
| n     | <leader>ai        | Springt zum nächsten Import-Statement                                   |
| n     | <leader>aI        | Fügt ein Import-Statement für eine Astro-Komponente ein                 |
| v     | <leader>ax        | Extrahiert die visuelle Auswahl in eine neue Astro-Komponente           |
| n     | <leader>ap        | Öffnet die aktuelle Astro-Page im Browser (Dev-Server)                  |
| n     | <leader>aF        | Formatiert die aktuelle Astro-Datei                                     |

---

## autocmds (AstroQoL)

| Event        | Pattern | Beschreibung                                                  |
| ------------ | ------- | ------------------------------------------------------------- |
| BufWritePre  | *.astro | Formatiert Astro-Dateien vor dem Speichern                    |
| BufWritePre  | *.astro | Führt LSP-Code-Action zum Organisieren von Imports aus        |
| FileType     | astro   | Setzt buffer-lokale Optionen (Indent, Tabs, Commentstring)    |
| FileType     | astro   | Definiert Syntax-Highlighting für Astro-Frontmatter           |
| VimLeavePre  | *.astro | Beendet laufende astro dev Prozesse beim Verlassen von Neovim |
| BufWritePost | *.astro | Prüft verwendete Komponenten auf fehlende Import-Statements   |

---

## user commands

| Command             | Argumente | Beschreibung                                         |
| ------------------- | --------- | ---------------------------------------------------- |
| AstroDevStart       | –         | Startet den Astro-Dev-Server in einem Terminal-Split |
| AstroDevStop        | –         | Stoppt den laufenden Astro-Dev-Server                |
| AstroBuild          | –         | Baut das Astro-Projekt                               |
| AstroPreview        | –         | Startet die Vorschau des Produktions-Builds          |
| AstroNewComponent   | [Name]    | Erstellt eine neue Astro-Komponente                  |
| AstroNewPage        | [Name]    | Erstellt eine neue Astro-Seite                       |
| AstroListComponents | –         | Listet alle Astro-Komponenten via Telescope          |
| AstroFindUsage      | –         | Sucht Verwendungen der aktuellen Komponente          |
| AstroCheckStructure | –         | Prüft die Projektstruktur auf fehlende Verzeichnisse |

---

## augroup

| Name     | Beschreibung                                                   |
| -------- | -------------------------------------------------------------- |
| AstroQoL | Gruppiert alle Astro-bezogenen Autocommands für QoL-Funktionen |

---

## implizite abhängigkeiten / voraussetzungen

| Komponente      | Zweck                                    |
| --------------- | ---------------------------------------- |
| telescope.nvim  | Datei- und Usage-Suche                   |
| conform.nvim    | Formatter-Integration (Fallback auf LSP) |
| Astro LSP       | Code-Actions, Formatierung               |
| astro CLI       | Dev-Server, Build, Preview               |
| pkill           | Prozessbeendigung (Linux/macOS)          |
| xdg-open / open | Browser-Preview (Linux/macOS)            |

---

## anmerkungen zur struktur

* alle keymaps sind buffer-lokal und nur für Astro-Dateien aktiv
* keine globalen Side-Effects außerhalb des Astro-Kontexts
* Commands sind idempotent und explizit nutzergetriggert
* Autocmds sind sauber über eine eigene augroup gekapselt

wenn gewünscht, kann man daraus auch:

* eine README-Dokumentation generieren
* eine automatisch erzeugte Help-Datei (:h astro-qol)
* oder eine maschinenlesbare Übersicht (z. B. JSON / Lua-Tabelle) ableiten

