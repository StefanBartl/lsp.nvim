# Lua Language Server (lua_ls) Setup für Neovim

Diese Lua-Module konfigurieren den Lua Language Server (lua_ls) für Neovim mit intelligenter Root-Erkennung, präziser Workspace-Library-Verwaltung und optimierter Performance.

## 📋 Übersicht

Das Setup besteht aus mehreren zusammenhängenden Modulen, die eine robuste und performante lua_ls-Integration bieten:

```
lsp/servers/lua_ls/
├── init.lua              # Hauptmodul: LSP-Server-Konfiguration
├── rootresolver.lua      # Projekt-Root-Erkennung
├── build_library.lua     # Workspace-Library-Konstruktion
├── find_type_dirs.lua    # Scanner für Type-Verzeichnisse
├── ignore.lua            # Zentrale Ignore-Konfiguration
└── debug.lua             # Debugging-Utilities
```

## 🎯 Hauptfunktionen

### 1. **Intelligente Root-Erkennung**
Das System erkennt automatisch die Projektgrenzen anhand mehrerer Kriterien:

- **VCS-Marker**: `.git`, `.hg`, `.svn` (höchste Priorität)
- **Lua-Konfigurationsdateien**: `.luarc.json`, `.neoconf.json`, `selene.toml`, `stylua.toml`
- **Neovim-Config-Verzeichnis**: Spezialbehandlung für `stdpath("config")`
- **Fallback**: Aktuelles Verzeichnis für Single-File-Support

### 2. **Präzise Library-Verwaltung**
Die Workspace-Libraries werden pro Projekt-Root dynamisch aufgebaut:

#### **Enthaltene Libraries:**
- **Third-Party Definitions** (`${3rd}/...`):
  - `${3rd}/luv/library` - Typdefinitionen für vim.uv/vim.loop
  - `${3rd}/busted/library` - Typdefinitionen für Busted Test-Framework

- **Neovim Runtime**: Alle Neovim-Laufzeitpfade für `vim.*` API-Erkennung

- **Projekt-Type-Verzeichnisse**: Automatische Erkennung von `types/` und `@types/` Ordnern

- **LuaRocks**: Unterstützung für global und lokal installierte Rocks

- **Lokale Dependencies**: `lua_modules/`, `deps/`, `vendor/`

### 3. **Optimierte Performance**
Das System ist auf Performance optimiert:

- **Intelligente Ignore-Listen**: Überspringt `node_modules`, `.git`, `build` etc.
- **Konfigurierbare Limits**:
  - `maxPreload = 3000` - Maximale Anzahl vorgeladener Dateien
  - `preloadFileSize = 500` - Maximale Dateigröße (KB)
- **BFS-Scanning**: Breadth-First-Search mit konfigurierbarer Tiefe (`max_depth = 12`)

### 4. **Git-Integration**
- Respektiert `.gitignore` Dateien (`useGitIgnore = true`)
- Überspringt Git-Verzeichnisse automatisch

## 📦 Module im Detail

### `init.lua` - Hauptmodul

Das Herzstück der Konfiguration. Registriert den lua_ls Server mit:

```lua
require("lsp.servers.lua_ls").setup({
  capabilities = capabilities,
  on_attach = on_attach,
  on_init = on_init,
}, {
  enable = true  -- Automatisch aktivieren
})
```

**Wichtige Features:**
- Verwendet die native `vim.lsp.config()` API (Neovim 0.10+)
- Dynamische Library-Konfiguration via `on_new_config` Hook
- LuaJIT-Runtime für Neovim-Optimierung
- Inlay Hints aktiviert
- Semantic Tokens deaktiviert (TreeSitter wird bevorzugt)

### `rootresolver.lua` - Root-Erkennung

Polymorphe Resolver-Funktion, die sowohl mit Buffer-Nummern als auch Dateinamen funktioniert:

```lua
local root = require("lsp.servers.lua_ls.rootresolver")
local project_root = root(bufnr)  -- Oder: root(filename)
```

**Algorithmus:**
1. Prüfe ob innerhalb von `stdpath("config")` → Nutze Config-Dir
2. Suche VCS-Root (`.git`, etc.) aufwärts
3. Suche Lua-Marker (`.luarc.json`, etc.) aufwärts
4. Fallback auf Start-Verzeichnis

### `build_library.lua` - Library-Konstruktion

Baut die Workspace-Libraries pro Projekt-Root:

```lua
local library = require("lsp.servers.lua_ls.build_library")(root)
-- Returns: { [path] = true, [path2] = true, ... }
```

**Library-Quellen:**
- `${3rd}/luv/library` - luv Typen
- `${3rd}/busted/library` - Busted Typen
- Projekt-Type-Verzeichnisse via Scanner
- LuaRocks global & lokal
- Lokale Dependencies (`lua_modules`, etc.)

### `find_type_dirs.lua` - Type-Scanner

Durchsucht das Projekt nach Type-Verzeichnissen:

```lua
local scanner = require("lsp.servers.lua_ls.find_type_dirs")
local type_dirs = scanner(root, {
  max_results = 100,
  max_depth = 10
})
```

**Features:**
- Breadth-First-Search (BFS) Algorithmus
- Findet `types/` und `@types/` Verzeichnisse
- Respektiert Ignore-Listen
- Konfigurierbare Limits für Performance

### `ignore.lua` - Zentrale Ignore-Konfiguration

Zentralisierte Ignore-Listen für konsistente Behandlung:

```lua
local ignore = require("lsp.servers.lua_ls.ignore")

-- Drei Export-Formate:
local names = ignore.names()              -- ["node_modules", ...]
local set = ignore.as_set()               -- {node_modules=true, ...}
local patterns = ignore.as_luals_patterns() -- ["**/node_modules", ...]
```

**Ignorierte Verzeichnisse (Beispiele):**
- `node_modules`, `bower_components`
- `.git`, `.svn`, `.hg`
- `build`, `dist`, `target`, `out`
- `.vscode`, `.idea`
- `__pycache__`, `.pytest_cache`

### `debug.lua` - Debugging-Utilities

Hilfsfunktionen zum Troubleshooting:

```lua
local debug = require("lsp.servers.lua_ls.debug")

-- Root für aktuellen Buffer
local root = debug.root_for_buf(bufnr)

-- Library-Paths für Root
local libs = debug.debug_library(root)

-- Debug-Info ausgeben
debug.print_debug_info(bufnr)
```

**Ausgabe-Beispiel:**
```
LuaLS Debug Info:
Root: /home/user/projects/my-plugin
Library paths: /home/user/.config/nvim, /home/user/projects/my-plugin/types, ...
```

## 🔧 Installation & Setup

### 1. Dateien platzieren

```
~/.config/nvim/lua/lsp/servers/lua_ls/
├── init.lua
├── rootresolver.lua
├── build_library.lua
├── find_type_dirs.lua
├── ignore.lua
└── debug.lua
```

### 2. Abhängigkeiten

Stelle sicher, dass diese Helper-Module existieren:
- `lib.fs.is_subpath`
- `lib.fs.find_upward_dir`
- `lib.fs.ignore.list`

### 3. LSP Setup

In deiner `init.lua` oder LSP-Konfiguration:

```lua
-- LSP Capabilities und Handlers
local capabilities = require('cmp_nvim_lsp').default_capabilities()
local on_attach = function(client, bufnr)
  -- Deine on_attach Logik
end

-- Lua Language Server Setup
require("lsp.servers.lua_ls").setup({
  capabilities = capabilities,
  on_attach = on_attach,
}, {
  enable = true
})
```

## 🐛 Debugging

### Problem: Server erkennt vim.* APIs nicht

```lua
:lua require("lsp.servers.lua_ls.debug").print_debug_info()
```

Prüfe ob:
- Root korrekt erkannt wurde
- Neovim Runtime-Paths in Library enthalten sind

### Problem: Types nicht gefunden

```lua
:lua vim.print(require("lsp.servers.lua_ls.find_type_dirs")(vim.fn.getcwd()))
```

Prüfe ob:
- Type-Verzeichnisse existieren
- Ignore-Liste sie nicht ausblendet

### Problem: Performance-Issues

Reduziere Limits in `init.lua`:
```lua
workspace = {
  maxPreload = 2000,      -- Weniger Dateien vorladen
  preloadFileSize = 300,  -- Kleinere Dateien
}
```

## 🎨 Anpassungen

### Weitere ${3rd} Libraries hinzufügen

In `build_library.lua`:
```lua
library["${3rd}/luasocket/library"] = true
library["${3rd}/lfs/library"] = true
```

### Ignore-Liste erweitern

In `lib.fs.ignore.list`:
```lua
return {
  "node_modules",
  "custom_build_dir",  -- Dein Custom-Verzeichnis
  -- ...
}
```

### Root-Erkennung anpassen

In `rootresolver.lua`:
```lua
-- Weitere Marker hinzufügen:
local lua_markers = vim.fs.find(
  { ".luarc.json", ".neoconf.json", "my_custom_marker.toml" },
  { path = dir, upward = true }
)
```

## 📊 Architektur-Diagramm

```
┌─────────────────────────────────────────┐
│         init.lua (Main Setup)           │
│  ┌────────────────────────────────────┐ │
│  │ vim.lsp.config("lua_ls", {         │ │
│  │   root_dir = rootresolver(),       │ │
│  │   settings = { ... },              │ │
│  │   on_new_config = ...              │ │
│  │ })                                 │ │
│  └────────────────────────────────────┘ │
└──────────────┬──────────────────────────┘
               │
               ├─────────────────────┐
               │                     │
               ▼                     ▼
    ┌──────────────────┐  ┌──────────────────┐
    │  rootresolver()  │  │  on_new_config   │
    │                  │  │      Hook        │
    │ • VCS markers    │  └────────┬─────────┘
    │ • Lua configs    │           │
    │ • stdpath check  │           ▼
    └──────────────────┘  ┌──────────────────┐
                          │ build_library()  │
                          │                  │
                          │ • ${3rd} libs    │
                          │ • Runtime paths  │
                          │ • Type dirs ──┐  │
                          │ • LuaRocks    │  │
                          └───────────────┼──┘
                                          │
                                          ▼
                          ┌──────────────────────┐
                          │  find_type_dirs()    │
                          │                      │
                          │  • BFS scan          │
                          │  • Ignore check ───┐ │
                          │  • Collect types   │ │
                          └────────────────────┼─┘
                                               │
                                               ▼
                                    ┌─────────────────┐
                                    │    ignore()     │
                                    │                 │
                                    │ • Shared list   │
                                    │ • as_set()      │
                                    │ • as_patterns() │
                                    └─────────────────┘
```

## 🔍 Wichtige Konzepte

### Per-Root Library Configuration

Jeder Projekt-Root erhält seine eigene Library-Konfiguration. Dies verhindert:
- ❌ Cross-Contamination zwischen Projekten
- ❌ Falsche Typ-Inferenz aus anderen Projekten
- ❌ Performance-Degradation durch zu große Workspaces

### ${3rd} Placeholder System

lua_ls shipped mit eingebauten Type-Definitionen für populäre Libraries. Der `${3rd}` Prefix wird vom Server zur Laufzeit aufgelöst:

```lua
library["${3rd}/luv/library"] = true
-- Resolves to: /path/to/lua-language-server/meta/3rd/luv/library
```

### Dynamic on_new_config Hook

Der `on_new_config` Hook wird bei jedem Root-Wechsel aufgerufen. Das ermöglicht:
- ✅ Root-spezifische Libraries
- ✅ Dynamische Anpassung an Projekt-Struktur
- ✅ Keine globale State-Pollution

## 📚 Weiterführende Ressourcen

- [lua_ls Dokumentation](https://luals.github.io/)
- [Neovim LSP Guide](https://neovim.io/doc/user/lsp.html)
- [lua_ls Settings](https://luals.github.io/wiki/settings/)

## 🤝 Contributing

Bei Problemen oder Verbesserungsvorschlägen:
1. Debugging-Info sammeln: `:lua require("lsp.servers.lua_ls.debug").print_debug_info()`
2. Issue erstellen mit Debug-Output
3. Relevante Projekt-Struktur beschreiben

## 📝 Lizenz

Dieses Setup ist Teil deiner Neovim-Konfiguration und kann frei angepasst werden.

---

**Hinweis:** Diese Dokumentation beschreibt das System im Gesamtbild. Für Implementierungsdetails siehe die inline-Kommentare in den jeweiligen Modulen.
