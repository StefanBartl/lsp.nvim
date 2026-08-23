# Roadmap — `lsp.nvim`

> Dieses Dokument ist die Spiegelung des Konzeptpapiers aus der nvim-Config
> (`~/AppData/Local/nvim/docs/ROADMAP/personal/lsp.nvim.md`). **Dort liegt die
> Source of Truth**; hier steht die Kopie, damit das Repo nicht ohne Roadmap
> dasteht. Relative Links in die Config wurden zu reinem Text reduziert.
>
> Stand 2026-08-23: Phasen 0, 1 und 2 (§13) sind abgeschlossen — der LSP-Kern
> liegt in diesem Repo und konfiguriert die Server. Offen sind Phase 3
> (Keymaps), Phase 4 (Integrations-Adapter) und Phase 5 (Pack).

# `lsp.nvim` — Konzept (Dachplugin)

Auslagerung von `nvim/lua/lsp/**` **und des gesamten LSP-Ökosystems der Config**
in ein eigenständiges Plugin, analog zu `dap.nvim` (`C:\repos\dap.nvim`,
Modulwurzel `wkddap`) und den anderen extrahierten `*.nvim`-Plugins
(`filetree.nvim`, `sessions.nvim`, `pickers.nvim`, ...).

> **Stand 2026-08-23.** Alle Repos liegen inzwischen unter `C:\repos\` — die
> `E:\repos\…`-Pfade in diesem Dokument sind entsprechend nachgezogen.
>
> `C:\repos\lsp.nvim` (GitHub: `StefanBartl/lsp.nvim`) ist auf Branch `main`.
> **Phasen 0, 1 und 2 sind abgeschlossen.**
>
> - Phase 0: B1, B2, B4, B6 erledigt (siehe die Befund-Tabelle).
> - Phase 1: `gates/NEW_PROJECT.md` durchgegangen, Protokoll in
>   `docs/CHECKLISTS/NEW_PROJECT.md`; Gerüst, Tooling, CI, README, vimdoc,
>   Smoke-Test.
> - Phase 2: der Kern ist umgezogen — 164 Dateien, `core/`, `servers/`,
>   `languages/`, `formatter/`, `diagnostics/`, `lspdoctor/`, `tools/`,
>   `usercmds/`, `completion/`, `integrations/mason/`. Die Config lädt das
>   Plugin; `lua/lsp/**` heißt dort jetzt `lua/lsp_legacy/**` und liegt auf
>   keinem require-Pfad mehr.
>
> Offen sind Phase 3 (Keymap-Konsolidierung), Phase 4 (Integrations-Adapter),
> Phase 5 (Pack) und aus Phase 6 der Umzug von `debug_adapters/**` nach
> `dap.nvim` — die stecken noch in `lsp_legacy`.

Die Grundsatzentscheidung ist in nvim.nvim.md (Abschnitt
„`lsp.nvim` vs. `options.nvim`“, 2026-07-17) getroffen: `lua/lsp/` ist
strukturell dasselbe wie `dap.nvim` — ein **stateful Subsystem** (Registry,
Capabilities, Attach-Handler, Formatter-Toggle, Workspace-Diagnostics-Toggle),
keine deklarativen Settings. Gehört daher **nicht** in `options.nvim`.

**Neu gegenüber der ersten Konzeptfassung (2026-07-26):** `lsp.nvim` wird nicht
nur ein Umzug von `lua/lsp/**`, sondern ein **Dachplugin**, unter dem *alles*
LSP-Bezogene zusammenläuft — inklusive der Fremdplugins (`trouble.nvim`,
`conform.nvim`, `lazydev.nvim`, `nvim-cmp`/`blink.cmp`, `mason.nvim`,
`lspsaga.nvim`, `inc-rename.nvim`, `lensline.nvim`,
`workspace-diagnostics.nvim`) und *aller* LSP-/Diagnostics-Keymaps, die heute
über `lua/bindings/mappings/**` und `lua/config/**` verstreut sind
(z. B. `<leader>wq`, `<leader>x*`, `<leader>rn`).

---

## Table of Content

- [1. Ist-Zustand](#1-ist-zustand)
- [2. Befunde aus der Analyse (Bugs & Altlasten)](#2-befunde-aus-der-analyse-bugs--altlasten)
- [3. Zielbild: Dachplugin in drei Schichten](#3-zielbild-dachplugin-in-drei-schichten)
- [4. Scope-Abgrenzung](#4-scope-abgrenzung)
- [5. Architektur / Verzeichnisbaum](#5-architektur--verzeichnisbaum)
- [6. Das Pack-System (LazySpec-Export)](#6-das-pack-system-lazyspec-export)
- [7. Integrations-Adapter im Detail](#7-integrations-adapter-im-detail)
- [8. Bindings: Keymaps, Usercmds, Autocmds](#8-bindings-keymaps-usercmds-autocmds)
- [9. Öffentliche API & Defaults](#9-öffentliche-api--defaults)
- [10. lib.nvim-Integration](#10-libnvim-integration)
- [11. checkhealth & LspDoctor](#11-checkhealth--lspdoctor)
- [12. Dokumentationspflichten](#12-dokumentationspflichten)
- [13. Migrationsplan](#13-migrationsplan)
- [14. Roadmap: neue Features](#14-roadmap-neue-features)
- [15. Offene Fragen / Entscheidungen](#15-offene-fragen--entscheidungen)

---

## 1. Ist-Zustand

### 1.1 `lua/lsp/**` — 130 Dateien, 11.645 LOC

| Bereich | Pfad | LOC | Verantwortung |
|---|---|---:|---|
| Core | `core/{registry,attach,capabilities,handlers,filter,diagnostics,treesitter,util}.lua` | 668 | Server-Registry (`ACTIVE`-Liste), `on_attach`/`on_init`, Capabilities-Merge (cmp/blink/NvChad), publishDiagnostics-Dedup, Treesitter-Wiring |
| Core (Sonderfälle) | `core/workspace_diagnostics.lua`, `core/root_scope.lua`, `core/root_scope_picker.lua` | (in 668) | Laufzeit-Toggle für `workspace-diagnostics.nvim` (Startup-Freeze-Fix), Multi-Root-Handling |
| Formatter | `formatter/{init,conform}.lua` | 408 | Conform-first, LSP-Fallback, View-preserving Format-on-Save mit Toggle |
| Diagnostics | `diagnostics/**` | 415 | Commands (`:Diag*`), Keymaps (`<leader>wq`, `]d`/`[d`, `]q`/`[q`), Quickfix/Loclist, Navigation |
| Server-Configs | `servers/**` (bashls, lua_ls, gopls, marksman, csharp, clangd, zig, webdev/*, mobiledev/*) | 3012 | Pro-Server-Setup; `lua_ls` mit eigenem Library-Resolver/Reload/Rootresolver, `marksman` mit eigenen Handlern |
| Sprachen | `languages/**` (app, documentation, scripting, systems, webdev) | 1477 | Filetype-spezifische QoL (Astro-Autocmds/Keymaps/Usercmds, Markdown-Words, ...) |
| Debug-Doctor | `lspdoctor/**` | 948 | `:LspDoctor {health,debug,quick,deep,all}` — **nicht** an `:checkhealth` angebunden |
| Tools | `tools/{eslint_prettier,lsp_signature,ts_type_lookup,deprecated_help}/**` | 2909 | Eigenständige Zusatz-Werkzeuge, jeweils mit eigenem `setup()`/`attach()` |
| Usercmds | `usercmds/**` | 1170 | `:LspFormat*`, `:LspStart/Stop/RestartHere`, `:LspRecover`, `:LspWorkspaceDiagnostics*`, `:LspMobileDiagnostics`, Command-Completion |
| Debug Adapters | `debug_adapters/**` | 183 | **Fehlplatziert** — DAP ist ein eigenes Protokoll, gehört zu `dap.nvim` |
| Types | `@types/**` + verteilte `@types`-Unterordner | 202 | Bereits gut nach Leitfaden strukturiert |

Einstiegspunkt `lsp/init.lua` verdrahtet alles synchron in `M.setup(cfg)`,
inkl. Host-Spezifika (`machine.is("workstation")`,
`require("config.mason.ensure_install")`, `nvchad.config.lspconfig`).
Aufruf erfolgt in init.lua:162: `require("lsp").setup({ ensure_installing = false })`.

### 1.2 LSP-nahe Fremdplugins in `lua/plugins/**`

Das ist der Teil, der im alten Konzept fehlte. Alle folgenden Plugins gehören
fachlich unter das Dach `lsp.nvim`:

| Plugin | Spec-Ort | Rolle | Kopplung an `lua/lsp/**` |
|---|---|---|---|
| `folke/trouble.nvim` | `plugins/trouble.lua` (+ `config/trouble/numbering.lua`) | Diagnostics-/Quickfix-/Loclist-/LSP-Listen-UI, `lazy = false` | keine direkte, aber **Keymap-Konflikt** bei `]q`/`[q` (s. §2) |
| `stevearc/conform.nvim` | `plugins/lsp.lua` | Formatter-Engine | `lsp/formatter/{init,conform}.lua` baut darauf auf — **zwei Setups parallel** |
| `folke/lazydev.nvim` | `plugins/lsp.lua` | lua_ls-Library für `require` | `lsp/core/attach.lua:62` lädt es per `pcall` bei ft=lua |
| `hrsh7th/nvim-cmp` | `plugins/lsp.lua`, `config/copilot/cmp.lua` | Completion-Engine | `lsp/core/capabilities.lua:36` liest `cmp_nvim_lsp` |
| `saghen/blink.cmp` | `plugins/lsp.lua` (**auskommentiert**) | Alternative Completion-Engine | `lsp/core/capabilities.lua:53` unterstützt es bereits |
| `williamboman/mason.nvim` | `plugins/*` + `config/mason/ensure_install/**` | Paketverwaltung LSP/DAP/Linter/Formatter | `lsp/init.lua:199` ruft `config.mason.ensure_install` |
| `artemave/workspace-diagnostics.nvim` | `plugins/lsp.lua` | Workspace-weite Diagnostics | `lsp/core/workspace_diagnostics.lua` + `usercmds` |
| `nvimdev/lspsaga.nvim` | `plugins/lsp.lua` | Breadcrumb/LSP-UI (fast alles deaktiviert) | keine |
| `smjonas/inc-rename.nvim` | `plugins/lsp.lua` + `config/inc_rename/init.lua` | Inkrementelles Rename + Auto-Save | eigener Keymap `<leader>rn`, redundant zu `grn` |
| `oribarilan/lensline.nvim` | `plugins/lsp.lua` | Codelens-artige Inline-Infos | keine |
| `nvim-treesitter` | `plugins/treesitter.lua` | Syntax | `lsp/core/treesitter.lua` verdrahtet mit LSP |
| `mrbjarksen/neo-tree-diagnostics.nvim` | `plugins/neotree.lua` | Diagnostics-Quelle im Filetree | Grenzfall → bleibt bei `filetree.nvim` |
| `kevinhwang91/nvim-bqf` | `plugins/*` | Bessere Quickfix-UI | Grenzfall, Quickfix ist Diagnostics-Senke |
| `folke/todo-comments.nvim` | `config/todo_comments/**` | TODO-Liste → Trouble/Quickfix | Grenzfall, kein LSP |

### 1.3 Verstreute LSP-Keymaps (Ist-Zustand)

Heute an **fünf** verschiedenen Orten. Vollständige Inventur:

| Keymap | Aktion | Quelle |
|---|---|---|
| `grn` | Rename | `bindings/mappings/lsp.lua:21` |
| `grt` | Type Definition | `bindings/mappings/lsp.lua:35` |
| `lsr` / `lsi` / `lss` | References / Implementations / Doc-Symbols | `bindings/mappings/lsp.lua:27-29` |
| `lsd` / `lsD` / `lst` / `lsa` | Definition / Declaration / Type-Def / Code-Action | `bindings/mappings/lsp.lua:30-33` |
| `<M-s>` (insert) | Signature Help | `bindings/mappings/lsp.lua:37` |
| `<leader>gtt` | Lua-Table-Root — **ruft `mylsp.nav.lua_root` auf, Modul existiert nicht** | `bindings/mappings/lsp.lua:8` |
| `<leader>lsp` | Root-Scope-Picker | `bindings/mappings/lsp.lua:12` |
| `<leader>lb` | Marksman-Hints-Toggle | `bindings/mappings/lsp.lua:16` |
| `<leader>tft` / `<leader>ft` / `<leader>fl` | Format-on-Save-Toggle / Format once / LSP-Format | `bindings/mappings/lsp.lua:42-71` |
| `<leader>tq` | Diagnostics → Quickfix | `bindings/mappings/lsp.lua:78` |
| `<leader>wq` | Diagnostics → Quickfix (workspace) | `lsp/diagnostics/keymaps.lua:15` |
| `<leader>lq` | Diagnostics → Loclist (buffer) | `lsp/diagnostics/keymaps.lua:19` |
| `]d` / `[d` | Nächste/vorige Diagnostic (Buffer) | `lsp/diagnostics/keymaps.lua:24-30` |
| `]q` / `[q` | Nächster/voriger Quickfix-Eintrag | `lsp/diagnostics/keymaps.lua:33-39` |
| `<leader>xt` / `xx` / `xw` / `xd` | Trouble Diagnostics (toggle/all/workspace/buffer) | `bindings/mappings/trouble.lua:11-29` |
| `<leader>xlr` / `xld` / `xlt` / `xli` / `xls` | Trouble LSP-Views | `bindings/mappings/trouble.lua:32-46` |
| `<leader>xl` / `<leader>xq` | Trouble Loclist / Quickfix | `bindings/mappings/trouble.lua:49-50` |
| `]q` / `[q` / `]l` / `[l` | **Überschreiben** die Diagnostics-Variante | `bindings/mappings/trouble.lua:53-56` |
| `]w` / `[w` | Nächste/vorige Workspace-Diagnostic (Trouble) | `bindings/mappings/trouble.lua:101-102` |
| `<leader>rn` | Incremental Rename | `config/inc_rename/init.lua:173` |
| `<leader>dos` / `<leader>wos` | FzfLua Document-/Workspace-Symbols | `bindings/mappings/fzf.lua:13-14` |
| `<leader>do` / `<leader>wo` | FzfLua Document-/Workspace-Diagnostics | `bindings/mappings/fzf.lua:16-17` |
| `<leader>fq` | FzfLua Quickfix | `bindings/mappings/fzf.lua:19` |

### 1.4 Verstreute `lua/config/**`-Module mit LSP-Bezug

`config/mason/**`, `config/inc_rename/**`, `config/trouble/**`,
`config/copilot/cmp.lua` — alle vier gehören unter das Dach.

---

## 2. Befunde aus der Analyse (Bugs & Altlasten)

Beim Durchgehen der Module gefunden — **vor** oder **während** der Migration zu
beheben, nicht 1:1 mitschleppen:

| # | Befund | Ort | Bewertung |
|---|---|---|---|
| B1 | **Unaufgelöste Git-Merge-Konflikt-Marker** (`<<<<<<< HEAD` / `=======` / `>>>>>>>`) im Sourcecode | `lsp/core/capabilities.lua:61-71, 106-113` | 🔴 **Kritisch — ✅ ERLEDIGT (2026-07-26).** Datei war syntaktisch kaputt → `pcall(require, "lsp.core.capabilities")` schlug fehl → `lsp/init.lua:53` fiel still auf `make_client_capabilities()` zurück; **Completion-Capabilities von cmp/blink/NvChad wurden gar nicht angewandt.** Aufgelöst zugunsten der `8b6135fd`-Seite (String-Level `"error"`/`"warn"`), weil `lsp/init.lua:44` genau darauf vergleicht — mit `vim.log.levels.ERROR` (Zahl) wäre jeder Fehler still zur Warnung degradiert. Zusätzlich die doppelte `local warnings = {}`-Deklaration entfernt. |
| B2 | Keymap auf nicht existierendes Modul `mylsp.nav.lua_root` | `bindings/mappings/lsp.lua:8` | ✅ **ERLEDIGT (2026-08-23).** `mylsp` existiert nirgends — nicht in `lua/`, nicht in einem installierten Plugin — die Taste warf bei jedem Druck. Keymap entfernt, mit Kommentar an ihrer Stelle. Das Feature selbst („zum umschließenden Lua-Table-/Funktions-Root springen") ist zu schade zum Wegwerfen und steht jetzt in §14, statt als kaputte Taste am Leben gehalten zu werden. |
| B3 | `]q`/`[q` **doppelt** gebunden (diagnostics + trouble); trouble gewinnt durch spätere Registrierung in `bindings/mappings/init.lua` | `lsp/diagnostics/keymaps.lua:33` vs. `bindings/mappings/trouble.lua:53` | Genau der Fall, den das Dachplugin auflöst: eine Quelle, eine Entscheidung |
| B4 | `require("lsp.lspdoctor").setup()` wird **zweimal hintereinander** mit widersprüchlichen `formatter_priority` aufgerufen | `lsp/init.lua:223-235` | ✅ **ERLEDIGT (2026-08-23)** — mit korrigierter Diagnose: „erster ist toter Code" stimmte **nicht**. `lspdoctor.setup()` merged Key für Key in ein persistentes `Opts` (`lspdoctor/init.lua:115`), also wirkten *alle* Keys aus beiden Aufrufen; überschrieben wurde nur `formatter_priority`. `list_limit`, `semantic_tokens_timeout` und `scratch_filetype` waren nie verloren. Zu einem Aufruf zusammengezogen, der exakt den bisherigen Effektivzustand trägt — sichtbar am Aufrufort statt aus der Merge-Semantik erschlossen. Nebenbefund: `null-ls` in der Prioritätsliste ist wirkungslos, es ist nirgends installiert (conform formatiert); bewusst stehen gelassen, weil das eine Entscheidung ist und kein Aufräumen. |
| B5 | Conform wird **zweimal** konfiguriert: `plugins/lsp.lua:126` (`format_on_save = {…}`) und `lsp/formatter/conform.lua` + `lsp/formatter/init.lua` (`format_on_save = false`, eigener Autocmd) | beide | Zwei konkurrierende Format-on-Save-Pfade. Muss im Dachplugin **eine** Wahrheit werden |
| B6 | `formatter/init.lua` dokumentiert sich als „Linux/macOS only; no Windows-specific branches“ — Workstation läuft auf Windows | `lsp/formatter/init.lua:3` | ✅ **ERLEDIGT (2026-08-23).** Veralteter Kommentar, keine reale Einschränkung. `formatter/init.lua` braucht selbst nichts Plattformabhängiges (Autocmds + View-Erhaltung); die Stellen, die es tun, liegen in `formatter/conform.lua` und verzweigen dort korrekt auf Windows (PATH-Separator `;`, `.cmd`-Suffix, Mason-Bin-Pfad — `conform.lua:20,40`). Kopfkommentar entsprechend richtiggestellt. |
| B7 | `ACTIVE`-Serverliste hart im Sourcecode, Server an/aus = Code-Edit | `lsp/core/registry.lua:10-33` | ✅ **ERLEDIGT (2026-08-23).** Liste nach `config/DEFAULTS.lua` als `servers`, `registry.setup_all(shared, servers)` bekommt sie übergeben. Leere oder kaputte Liste fällt auf die Defaults zurück statt „gar kein Sprachserver" zu ergeben — das sieht aus wie eine kaputte Installation und darf nie das Ergebnis eines Tippfehlers sein. |
| B8 | Drei eigene Root-Resolver (`core/root_scope.lua`, `servers/lua_ls/rootresolver.lua`, `servers/marksman/rootresolver.lua`) trotz `lib.nvim.fs` | siehe §10 | Dedup-Kandidat |
| B9 | `<leader>rn` (inc-rename) und `grn` (`vim.lsp.buf.rename`) machen dasselbe, unterschiedlich | `config/inc_rename` vs. `bindings/mappings/lsp.lua` | Im Dachplugin: **ein** Rename-Keymap, Backend konfigurierbar (`rename.provider = "inc_rename"\|"native"`) |
| B10 | `lsr`/`lsi`/`lss`/`lsd`/`lsD`/`lst`/`lsa` sind **prefixlose** 3-Zeichen-Maps im Normal-Mode | `bindings/mappings/lsp.lua:27-33` | Blockieren `ls…`-Sequenzen und verzögern `l`-Bewegungen nicht, aber kollidieren mit Neovim-0.11-Defaults (`grr`, `gri`, `grn`, `gO`). Bei der Preset-Definition neu bewerten |
| B11 | `blink.cmp` vollständig auskommentiert, `nvim-cmp` aktiv — Capabilities-Modul unterstützt beide | `plugins/lsp.lua:96-118` | Dachplugin macht Engine-Wahl zur Option (`completion.engine = "cmp"\|"blink"\|"auto"`) |

---

## 3. Zielbild: Dachplugin in drei Schichten

**Grundsatzentscheidung (2026-07-26): harte Abhängigkeiten sind erwünscht, nicht
zu vermeiden.** Ein LSP-Dachplugin, das `trouble.nvim`, `conform.nvim`,
`mason.nvim` & Co. nur „falls vorhanden“ anfasst, müsste deren Funktionalität
im Zweifel selbst nachbauen — das bringt nichts und wäre 10.000 Zeilen
schlechterer Code. `lsp.nvim` hängt ohnehin hart von `lib.nvim` ab; das
Ökosystem kommt genauso dazu. Der Dachplugin-Anspruch ist explizit: **wer
`lsp.nvim` installiert, bekommt das komplette LSP-Setup inklusive der
Fremdplugins.**

Die Dreiteilung bleibt trotzdem — nicht als Abhängigkeits-Abstufung, sondern als
**Zuständigkeits-Trennung**, damit die Codebasis navigierbar und einzeln testbar
bleibt:

```
┌──────────────────────────────────────────────────────────────────┐
│ Schicht 3 — PACK   lua/lsp/pack/**                               │
│   LazySpec-Export: WAS installiert wird, in welcher Version, mit │
│   welchen Presets. `{ “StefanBartl/lsp.nvim”, import=”lsp.pack”} │
│   Enthält KEINE Logik, nur Specs + opts.                         │
├──────────────────────────────────────────────────────────────────┤
│ Schicht 2 — INTEGRATIONS   lua/lsp/integrations/**               │
│   WIE die Fremdplugins verdrahtet werden: Config, Keymaps,       │
│   Handler-Bridges, Capabilities. Ein Modul pro Plugin.           │
├──────────────────────────────────────────────────────────────────┤
│ Schicht 1 — CORE   lua/lsp/{core,servers,languages,formatter,…}  │
│   Eigencode auf `vim.lsp.*`: Registry, Attach, Server-Configs,   │
│   Formatter-Kern, Diagnostics-Kern, LspDoctor, Tools.            │
└──────────────────────────────────────────────────────────────────┘
```

**Regeln:**

- Schicht 1 kennt Schicht 2 nicht (`core/attach.lua` ruft nie direkt
  `require(“lazydev”)` — das macht der Adapter). Nicht wegen Optionalität,
  sondern damit der Kern für sich testbar bleibt und Fremdplugin-Wechsel
  (cmp → blink) genau eine Datei berühren.
- Schicht 2 kennt Schicht 1 und darf voraussetzen, dass „ihr“ Plugin da ist.
- Schicht 3 kennt beide, wird aber von keiner geladen.

**`pcall` bleibt trotzdem überall** — aber mit anderer Begründung als vorher:
nicht „das Plugin ist optional“, sondern **Blast-Radius-Begrenzung**. Wenn
`lensline.nvim` nach einem Update kaputt ist, darf das nicht die Server-Registry
mitreißen. Ein fehlgeschlagener Adapter meldet sich in `:checkhealth lsp` als
`error` (nicht als beiläufiges `info` wie bei einem optionalen Feature) und der
Rest läuft weiter.

**Deklarierte harte Dependencies** (im Spec von `lsp.nvim`):
`lib.nvim`, `conform.nvim`, `trouble.nvim`, `mason.nvim`, `lazydev.nvim`,
`workspace-diagnostics.nvim` + die gewählte Completion-Engine.
**Weich** bleiben nur solche, die echte *Alternativen* sind oder reine
Zusatz-UI: `lspsaga`, `lensline`, `inc-rename`, `noice`, `which-key`, der
Picker (fzf-lua/telescope/snacks/`pickers.nvim`) und `nvchad`.

---

## 4. Scope-Abgrenzung

### Geht mit nach `lsp.nvim`

- Alles aus `lua/lsp/**` **außer** `debug_adapters/**`
- `lua/bindings/mappings/lsp.lua` (vollständig)
- `lua/bindings/mappings/trouble.lua` (vollständig — Trouble ist reine
  Diagnostics-/LSP-UI)
- `lua/config/inc_rename/**`
- `lua/config/trouble/**`
- `lua/config/mason/**` (als optionale `integrations/mason` + Pack-Spec)
- `lua/config/copilot/cmp.lua` (Completion-Menü-Interaktion → `integrations/cmp`)
- Die LSP-bezogenen Zeilen aus `lua/bindings/mappings/fzf.lua`
  (`<leader>dos`, `<leader>wos`, `<leader>do`, `<leader>wo`) — als
  `integrations/picker` mit Backend-Wahl (fzf-lua / telescope / snacks /
  `pickers.nvim`), damit nicht fzf-lua hart verdrahtet ist
- Die Plugin-Specs aus `lua/plugins/lsp.lua` und `lua/plugins/trouble.lua`
  → `lua/lsp/pack/**`

### Geht NICHT mit, sondern zu `dap.nvim`

`lua/lsp/debug_adapters/**` (bash, node, go, dotnet, webdev/browser). DAP ist
fachlich unabhängig vom LSP — die einzige Gemeinsamkeit ist „Mason installiert
beides“. `lsp/debug_adapters/init.lua` ist ohnehin nur eine Sammlung
auskommentierter `require`s, also faktisch inaktiv. Reines Verschieben ohne
Funktionsverlust; `dap.nvim` hat mit `lua/wkddap/adapters/` bereits den
passenden Platz.

**Mason (entschieden 2026-07-26): `ensure_install` zieht vollständig nach
`lsp.nvim`.** Nicht nach `lib.nvim` — es ist kein generischer Baustein, sondern
Paketverwaltung für Sprachwerkzeuge und damit fachlich genau das, was ein
LSP-Dachplugin verantwortet. `mason.nvim` wird harte Dependency.

Konkret zieht `config/mason/**` (Fassade + `defaults/{lsp,linter,formatter}.lua`,
Session-Aggregation, Dedup über Kategorien, externe Dependency-Guards) nach
`lua/lsp/integrations/mason/`. Zwei Folgerungen:

- `defaults/dap.lua` gehört inhaltlich zu `dap.nvim`. `lsp.nvim` bietet dafür
  eine Registrierungs-API, damit `dap.nvim` keine eigene Mason-Fassade braucht
  und beide sich nicht gegenseitig „Package is already installing“ produzieren:

  ```lua
  require("lsp.integrations.mason").register("dap", {
    ["js-debug-adapter"] = true, ["netcoredbg"] = true, …
  })
  ```

  Damit bleibt die Dedup-Logik an **einer** Stelle. `dap.nvim` bekommt dadurch
  eine weiche Abhängigkeit auf `lsp.nvim` (pcall-geschützt: fehlt es, macht
  `dap.nvim` seine Installs wie bisher selbst).
- Der heutige Aufruf `lsp/init.lua:198-220` (`cfg.ensure_installing`) wird zu
  `opts.mason` (s. §9), inklusive der `overrides`-Tabelle.

### Bleibt im Host (`nvim/`)

- `machine.is("workstation")`-Gating → als Opt an `setup()` übergeben, nie
  intern referenzieren
- NvChad-Kopplung (`nvchad.config.lspconfig.on_attach/on_init/capabilities`) →
  optionaler Adapter `integrations/nvchad`, kein impliziter Fallback-Pfad
- `neo-tree-diagnostics.nvim` → bleibt bei `filetree.nvim`/neotree-Config
- `todo-comments.nvim`, `nvim-bqf` → bleiben im Host (kein LSP), aber
  `nvim-bqf` wird in `docs/` als empfohlene Ergänzung erwähnt

---

## 5. Architektur / Verzeichnisbaum

Modulwurzel bleibt `lsp` (nicht `wkdlsp` wie bei `dap.nvim`): Neovim belegt nur
`vim.lsp`, `nvim-lspconfig` belegt `lspconfig` — der Top-Level-Name `lsp` ist
frei. Vorteil: **alle bestehenden `require("lsp.…")`-Pfade in der Config
bleiben gültig** (z. B. `autocmds/events/utils/filetype.lua:46-106`).

```
lsp.nvim/
├── lua/lsp/
│   ├── init.lua                    -- M.setup(opts): nur Orchestrierung
│   ├── health.lua                  -- :checkhealth lsp  (Pflicht)
│   ├── @types/
│   │   ├── init.lua                -- LspNvim.Config, LspNvim.Opts, …
│   │   ├── servers.lua
│   │   ├── formatter.lua
│   │   ├── languages.lua
│   │   ├── keymaps.lua             -- NEU: LspNvim.KeymapSpec / KeymapName
│   │   └── integrations.lua        -- NEU
│   ├── config/
│   │   ├── init.lua                -- Merge user-opts über DEFAULTS, Validierung
│   │   └── DEFAULTS.lua            -- EINE Quelle aller Defaults
│   ├── core/                       -- Schicht 1
│   │   ├── registry.lua            -- ACTIVE-Liste aus opts.servers statt hart codiert
│   │   ├── attach.lua              -- ohne NvChad-Direktzugriff
│   │   ├── capabilities.lua        -- Konflikt-Marker raus (B1), Engine per opts
│   │   ├── handlers.lua
│   │   ├── filter.lua
│   │   ├── diagnostics.lua
│   │   ├── treesitter.lua
│   │   ├── workspace_diagnostics.lua
│   │   ├── root_scope.lua          -- ggf. auf lib.nvim.fs reduzieren
│   │   └── util.lua
│   ├── formatter/                  -- Schicht 1, Conform als Integration
│   ├── diagnostics/                -- Schicht 1 (Kern), UI über Integrations
│   ├── servers/                    -- 1:1 Umzug
│   ├── languages/                  -- 1:1 Umzug
│   ├── lspdoctor/                  -- + Brücke nach health.lua
│   ├── tools/
│   │   ├── eslint_prettier/
│   │   ├── lsp_signature/
│   │   ├── ts_type_lookup/
│   │   ├── deprecated_help/
│   │   └── _test/                  -- NEU: Test-Entrypoint (Leitlinie §6)
│   ├── integrations/               -- Schicht 2 — pcall = Blast-Radius, nicht Optionalität
│   │   ├── init.lua                -- Registry + Reihenfolge + available()-Report
│   │   ├── trouble.lua             -- [hart]
│   │   ├── conform.lua             -- [hart]
│   │   ├── lazydev.lua             -- [hart]
│   │   ├── cmp.lua                 -- nvim-cmp + Copilot-Menü-Bridge  [hart, alternativ]
│   │   ├── blink.lua               -- [hart, alternativ]
│   │   ├── mason/                  -- [hart] ehem. config/mason/**
│   │   │   ├── init.lua            -- Fassade + register(kind, pkgs) für dap.nvim
│   │   │   ├── ensure_install.lua  -- Session-Aggregation, Dedup, Dependency-Guards
│   │   │   └── defaults/{lsp,linter,formatter}.lua
│   │   ├── workspace_diagnostics.lua  -- [hart]
│   │   ├── lspsaga.lua
│   │   ├── inc_rename.lua
│   │   ├── lensline.lua
│   │   ├── picker.lua              -- fzf-lua | telescope | snacks | pickers.nvim
│   │   ├── which_key.lua
│   │   ├── noice.lua
│   │   └── nvchad.lua
│   ├── pack/                       -- Schicht 3 — reine LazySpecs
│   │   ├── init.lua                -- importiert core/ui/completion je nach vim.g
│   │   ├── core.lua                -- conform, mason, workspace-diagnostics
│   │   ├── ui.lua                  -- trouble, lspsaga, lensline, inc-rename
│   │   └── completion.lua          -- lazydev + (cmp | blink)
│   └── bindings/
│       ├── init.lua
│       ├── keymaps.lua             -- ALLE LSP-/Diagnostics-Keymaps, user-überschreibbar
│       ├── usercmds.lua            -- :Lsp-Composer + Legacy-Aliase
│       ├── autocmds.lua
│       └── which_key.lua           -- Gruppenlabels, soft dependency
├── plugin/lsp_nvim.lua             -- nur falls ein Command vor setup() nötig ist
├── doc/lsp.txt                     -- englisch, `:h lsp.nvim`
├── docs/
│   ├── BINDINGS.md                 -- Pflicht: alle Keymaps/Usercmds/Autocmds
│   ├── ROADMAP.md
│   ├── installation.md
│   ├── configuration.md
│   ├── features.md
│   ├── commands.md
│   ├── architecture.md
│   ├── health.md
│   └── UMBRELLA.md                 -- NEU: wie das Pack-System funktioniert
├── .luarc.json
├── stylua.toml
└── README.md                       -- englisch, ASCII-Art + Badges + ToC (nur H2)
```

Die interne Struktur von Schicht 1 bleibt weitgehend 1:1 — sie ist bereits nach
[Arch&Coding-Regeln.md](file:///C:/repos/WKDBooks/Development/wkdbook-Lua/Checklists/archiv/Arch&Coding-Regeln.md) organisiert
(SRP pro Modul, `@types`-Unterordner, `pcall`-Disziplin). Die Extraktion ist
überwiegend **Verschieben + Entkopplung von Host-Spezifika**, kein Rewrite.
Neu gebaut werden im Wesentlichen `config/`, `integrations/`, `pack/`,
`bindings/`, `health.lua`.

---

## 6. Das Pack-System (LazySpec-Export)

Das ist der Mechanismus, der `lsp.nvim` zum Dachplugin macht.

### 6.1 Funktionsweise

lazy.nvim kann Specs aus dem `lua/`-Verzeichnis eines Plugins importieren, wenn
der Import am Spec des Plugins selbst hängt (dasselbe Verfahren nutzt LazyVim
mit `{ "LazyVim/LazyVim", import = "lazyvim.plugins" }`). Damit reicht **ein
Eintrag** in der User-Config:

```lua
-- lua/plugins/personal/init.lua
{
  "StefanBartl/lsp.nvim",
  import = "lsp.pack",                     -- ← installiert das ganze Ökosystem
  dependencies = { "StefanBartl/lib.nvim" },
  event = { "BufReadPre", "BufNewFile" },
  opts = {
    -- alles Weitere: siehe §9
  },
}
```

Ohne `import = "lsp.pack"` bekommt man nur Schicht 1+2 — `lsp.nvim` verdrahtet
dann, was ohnehin installiert ist, und ignoriert den Rest.

### 6.2 Timing-Problem und Lösung

`import` wird von lazy.nvim beim **Sammeln** der Specs ausgewertet — lange
bevor `require("lsp").setup(opts)` läuft. Der Pack kann also nicht aus `opts`
lesen. Zwei Kanäle, absichtlich getrennt:

| Kanal | Zeitpunkt | Steuert |
|---|---|---|
| `vim.g.lsp_nvim` (Tabelle, vor `require("lazy").setup()` gesetzt) | Spec-Sammelzeit | **Ob** ein Fremdplugin installiert wird, Versions-Pins, Engine-Wahl (`cmp` vs. `blink`) |
| `opts` in der Plugin-Spec | Setup-Zeit | **Wie** alles konfiguriert wird: Server, Keymaps, Formatter, Tools |

```lua
-- vor require("lazy").setup(...)
vim.g.lsp_nvim = {
  pack = {
    core       = true,             -- conform, mason, workspace-diagnostics
    ui         = true,             -- trouble, lspsaga, lensline, inc-rename
    completion = "cmp",            -- "cmp" | "blink" | false
    -- Feingranular: einzelne Plugins abwählen
    disable    = { "lspsaga.nvim" },
  },
}
```

`require("lsp").setup(opts)` liest `vim.g.lsp_nvim` als Basis und merged `opts`
darüber, damit es zur Laufzeit trotzdem **eine** aufgelöste Config gibt
(`require("lsp.config").get()`). Widersprüche (z. B. `pack.completion = false`,
aber `opts.completion.engine = "blink"`) meldet `:checkhealth lsp` als Warnung.

### 6.3 Nutzung ohne Pack

Der Pack ist der **empfohlene Weg** — er ist der Grund, warum das Plugin ein
Dach ist. Wer die Specs trotzdem selbst verwalten will (z. B. weil er eine
andere Trouble-Version pinnt), lässt `import` weg und behält eigene
`plugins/*.lua`; Schicht 2 findet die Plugins per `require` und verdrahtet sie
identisch. Fehlt dann eine **harte** Dependency (§3), meldet
`:checkhealth lsp` das als `error` mit dem fehlenden Plugin-Namen — statt
stillschweigend ein halbes Setup zu liefern.

Das ist gleichzeitig der Migrationsweg (§13): erst ohne Pack umziehen (die
heutigen `plugins/lsp.lua` / `plugins/trouble.lua` bleiben stehen), dann die
Specs in Phase 5 in den Pack verschieben.

---

## 7. Integrations-Adapter im Detail

Jeder Adapter hat dieselbe Signatur:

```lua
---@class LspNvim.Integration
---@field name string
---@field available fun(): boolean          # ist das Fremdplugin da?
---@field setup fun(cfg: LspNvim.Config): boolean, string?   # verdrahten
---@field health fun(report: LspNvim.HealthReport): nil      # für :checkhealth
```

`integrations/init.lua` hält die Registry und ruft sie in definierter Reihenfolge
auf. Ein Adapter, dessen Plugin fehlt oder dessen `setup()` scheitert, reißt
nichts mit (§3, Blast-Radius) — er meldet sich im Health-Report, nie per
`notify()` (Regel: kein `notify()` in Low-Level-Code). Der Schweregrad richtet
sich nach der Dependency-Härte aus §3: **harte** Dependency fehlt → `error`,
**weiche** fehlt → `info`.

| Adapter | Was `lsp.nvim` übernimmt |
|---|---|
| `trouble` | Kompletter Setup-Block (Preview-Split rechts 30 %, Index-Formatter aus `config/trouble/numbering.lua`, Modi `diagnostics`/`qflist`/`loclist`) **plus alle `<leader>x*`-Keymaps**. Der Neovim-0.12-Patch für `TSHighlighter._on_win/_on_line` (`plugins/trouble.lua:86-114`) zieht mit um — mit Versions-Guard statt bedingungslos. Trouble wird zur **Standard-Senke** für Diagnostics: ist es da, gehen `]d`/`[d`/`]q`/`[q` durch Trouble, sonst durch die Kern-Loclist/Quickfix-Implementierung. Damit ist B3 strukturell gelöst |
| `conform` | **Eine** Conform-Konfiguration (heute zwei, B5): `formatters_by_ft` aus `opts.formatter.by_ft`, `format_on_save` **immer** über den eigenen View-preserving Toggle in `lsp/formatter/init.lua`, nie über Conforms `format_on_save` |
| `lazydev` | Library-Liste (heute `plugins/lsp.lua:34-44`) als Default in `DEFAULTS.lua`, ergänzbar per `opts.lua.lazydev.library`. Der `pcall(require, "lazydev")` aus `core/attach.lua:62` wandert hierher |
| `cmp` | `cmp_nvim_lsp`-Capabilities, `lazydev`-Source (`group_index = 0`), Copilot-Menü-Bridge (`config/copilot/cmp.lua`) |
| `blink` | `get_lsp_capabilities()`, `lazydev`-Provider (`score_offset = 100`), `signature.enabled`. Der auskommentierte Block aus `plugins/lsp.lua:96-118` wird hier zur echten, wählbaren Alternative |
| `mason` | `ensure_install`-Fassade (heute `config/mason/ensure_install/**`), Paketlisten aus `opts.mason.ensure` mit `overrides` |
| `workspace_diagnostics` | Populate-on-attach hinter dem Laufzeit-Toggle (`core/workspace_diagnostics.lua`) — bleibt unverändert, nur Adapter-Wrapper |
| `lspsaga` | Der heutige Setup-Block (nur Breadcrumb aktiv), als Default-Preset |
| `inc_rename` | `setup()` + `post_hook` (Auto-Save der berührten Buffer, `config/inc_rename/init.lua`). Löst B9: `opts.rename.provider = "auto"` nimmt inc-rename wenn da, sonst `vim.lsp.buf.rename` — **ein** Keymap für beides |
| `lensline` | Profil `minimal`, `render = "focused"` |
| `picker` | Abstraktion für Symbol-/Diagnostics-Picker: `fzf-lua` \| `telescope` \| `snacks` \| `pickers.nvim` \| `auto`. Ersetzt die vier hart auf FzfLua verdrahteten Keymaps aus `bindings/mappings/fzf.lua` und die Ad-hoc-Telescope-Anbindung in `tools/ts_type_lookup/ts_telescope_picker.lua` |
| `which_key` | Gruppenlabels für alle Prefixe (`<leader>l`, `<leader>x`, `<leader>f`, …), v2- und v3-API, analog `dap.nvim/bindings/which_key/init.lua` |
| `noice` | `ts_type_lookup/noice_integration.lua` + inc-rename-Cmdline-Preset |
| `nvchad` | `on_attach`/`on_init`/`capabilities`-Bridge, **nur** wenn `opts.integrations.nvchad = true` |

---

## 8. Bindings: Keymaps, Usercmds, Autocmds

### 8.1 Keymaps — ein Preset, vollständig überschreibbar

Alle Keymaps aus §1.3 kommen nach `lua/lsp/bindings/keymaps.lua`. Vorgabe aus
[NEW_PROJECT.md](file:///C:/repos/WKDBooks/Development/wkdbook-Lua/Checklists/gates/NEW_PROJECT.md): *„alle Keymaps müssen vom User
einfach modifizierbar / deaktiviert werden können“* und *„eine which-key
Implementierung haben“*.

```lua
opts = {
  keymaps = {
    enabled = true,              -- false = gar keine Keymaps
    preset  = "default",         -- "default" | "minimal" | "none"

    -- Einzeln: string = neues lhs, false = deaktiviert, nil = Default
    goto_definition   = "lsd",
    goto_references   = "lsr",
    rename            = "grn",
    code_action       = "lsa",
    format_buffer     = "<leader>ft",
    format_toggle     = "<leader>tft",
    diag_next         = "]d",
    diag_prev         = "[d",
    diag_to_qflist    = "<leader>wq",
    diag_to_loclist   = "<leader>lq",
    trouble_toggle    = "<leader>xt",
    -- …
  },
}
```

Umsetzung: eine **deklarative Tabelle** `KEYMAPS = { <name> = { lhs, mode, rhs,
desc, requires? } }` in `config/DEFAULTS.lua`; `bindings/keymaps.lua` iteriert
darüber, wendet die User-Overrides an und registriert über `lib.nvim.map`.
`requires = "trouble"` sorgt dafür, dass ein Keymap nur gesetzt wird, wenn der
Adapter verfügbar ist — inklusive automatischem Fallback auf die Kern-Variante.
Nebeneffekt: `docs/BINDINGS.md` kann **aus dieser Tabelle generiert** werden
(kein Doku-Drift), und `:checkhealth lsp` kann Kollisionen mit bestehenden
Mappings melden.

**Entschieden (2026-07-26, B10): die `ls*`-Belegung bleibt.** `lsr`/`lsi`/`lss`/
`lsd`/`lsD`/`lst`/`lsa` werden als Preset `default` übernommen. Sie sind kein
Ersatz für die Neovim-0.11-Defaults, sondern liegen daneben: `grr`, `gri`,
`grn`, `grt`, `gO` funktionieren weiterhin, weil Neovim sie buffer-lokal bei
`LspAttach` setzt und die `ls*`-Maps global sind — kein Konflikt, nur zwei Wege
zum selben Ziel.

Zwei Punkte, die trotzdem in `docs/BINDINGS.md` gehören:

- `lsd`/`lsr`/… verzögern im Normal-Mode jede mit `l` beginnende Eingabe um
  `timeoutlen`, weil Neovim auf die Fortsetzung der Sequenz wartet. Das ist der
  Preis der prefixlosen Maps und heute schon so — nur bisher nirgends
  dokumentiert.
- `grn` ist doppelt belegt: einmal von Neovim (buffer-lokal, `LspAttach`) und
  einmal global in `bindings/mappings/lsp.lua:21`. Die globale gewinnt nicht —
  buffer-lokale Maps haben Vorrang. Beide zeigen auf `vim.lsp.buf.rename`, also
  folgenlos; mit `rename.provider = "inc_rename"` (B9) würden sie aber
  auseinanderlaufen. Der Adapter muss deshalb die **buffer-lokale** Map bei
  `LspAttach` überschreiben, nicht nur die globale setzen.

### 8.2 Usercmds — `:Lsp`-Composer

Vorgabe: ein Composite-Usercommand `:Cmd [options?]` mit Autocompletion über
`lib.nvim.usercmd.composer`.

```
:Lsp status                      :Lsp doctor [health|debug|quick|deep|all]
:Lsp start|stop|restart [here]   :Lsp format [on|off|toggle|status|which]
:Lsp diag [qf|loc|next|prev]     :Lsp workspace [on|off|toggle|status|now]
:Lsp servers                     :Lsp root [pick|show]
:Lsp log [open|level <lvl>]      :Lsp recover
```

Die heutigen ~30 Einzelcommands (`:LspFormat*`, `:LspWorkspaceDiagnostics*`,
`:LspStartHere`, `:DiagQF`, …) bleiben als **dünne Aliase** erhalten
(`opts.usercmds.legacy_aliases = true`, Default `true`) — Muskelgedächtnis
schlägt Reinheit, und die Aliase kosten nur je eine Zeile. `:LspDoctor` bleibt
zusätzlich eigenständig (begründete Ausnahme analog `:Surround` in
`replacer.nvim`): es ist ein Diagnosewerkzeug mit eigenem Renderer, kein
LSP-Steuerbefehl.

Server-spezifische Commands (`:AstroDevStart`, `:MdFormat`, `:LuaLsReloadLibrary`,
`:TypeDef*`, `:EslintFix`, …) bleiben wie sie sind — sie sind Filetype-gebunden
und gehören nicht in einen globalen Composer.

### 8.3 Autocmds

`bindings/autocmds.lua` bündelt: `LspAttach`-Wiring, Format-on-Save-Gruppe
(`LspFormatOnSave`), Diagnostics-Refresh, Astro-Autocmds. Alle über
`lib.nvim.autocmd` + `lib.nvim.augroup`, jede Gruppe löschbar/reloadbar
(Zentrale-Prinzipien §4).

---

## 9. Öffentliche API & Defaults

`config/DEFAULTS.lua` ist die einzige Quelle; `config/init.lua` merged und
validiert. Ziel laut Vorgabe: **maximale Nutzererfahrung bei minimaler
Initial-Config** — `require("lsp").setup()` ohne Argumente muss ein
vollständiges, sinnvolles Setup ergeben.

```lua
require("lsp").setup({
  ---@type string[]  ersetzt die hart codierte ACTIVE-Liste (B7)
  servers = { "lua_ls", "gopls", "bashls", "marksman", "html", "ts_ls",
              "tailwindcss", "csharp" },
  server_opts = { lua_ls = { … } },       -- pro-Server-Overrides

  diagnostics = {
    virtual_text = { spacing = 2, prefix = "●" },
    severity_sort = true,
    update_in_insert = false,
    float = { border = "rounded", source = "if_many" },
    ui = "trouble",                       -- "trouble" | "native" | "auto"
  },

  formatter = {
    on_save = false,                      -- View-preserving Toggle
    timeout_ms = 1500,
    engine = "conform",                   -- "conform" | "lsp" | "auto"
    by_ft = { lua = { "stylua" }, … },
  },

  completion = { engine = "auto" },       -- "cmp" | "blink" | "auto" | false
  rename     = { provider = "auto" },     -- "inc_rename" | "native" | "auto"

  workspace_diagnostics = { enabled = false },   -- Host übergibt Machine-Rolle
  inlay_hints           = { enabled = false, filetypes = {} },   -- NEU

  tools = {
    eslint_prettier = { enabled = true, filetypes = { "javascript", … } },
    lsp_signature   = { enabled = true },
    ts_type_lookup  = { enabled = true },
    deprecated_help = { enabled = true },
  },

  integrations = {
    trouble = true, conform = true, lazydev = true, mason = false,
    lspsaga = true, inc_rename = true, lensline = true,
    picker = "auto", which_key = true, noice = true,
    nvchad = false,                       -- Default AUS: Wiederverwendbarkeit
  },

  mason = { ensure_install = false, packages = { … }, overrides = { … } },
  keymaps = { … },                        -- s. §8.1
  usercmds = { legacy_aliases = true },
  lspdoctor = { use_notify = false, list_limit = 8, … },
})
```

Jeder Key bekommt einen Typ in `@types/` (Vorgabe: „für ein gutes
LSP-Erlebnis: jeder Key braucht einen Typ“), z. B.:

```lua
---@alias LspNvim.CompletionEngine "cmp"|"blink"|"auto"|false
---@alias LspNvim.DiagnosticsUi   "trouble"|"native"|"auto"
---@alias LspNvim.RenameProvider  "inc_rename"|"native"|"auto"
```

Host-seitig sieht der Aufruf dann so aus (ersetzt `init.lua:156` **und** die
Specs in `plugins/lsp.lua` / `plugins/trouble.lua`):

```lua
{
  "StefanBartl/lsp.nvim",
  import = "lsp.pack",
  dependencies = { "StefanBartl/lib.nvim" },
  event = { "BufReadPre", "BufNewFile" },
  opts = {
    integrations = { nvchad = true },
    workspace_diagnostics = { enabled = not require("machine").is("workstation") },
    mason = { ensure_install = false },
  },
}
```

---

## 10. lib.nvim-Integration

Pflicht laut [Arch&Coding-Regeln.md §NVIM-Config spezifisch](file:///C:/repos/WKDBooks/Development/wkdbook-Lua/Checklists/archiv/Arch&Coding-Regeln.md)
und [Checklist.md](file:///C:/repos/WKDBooks/Development/wkdbook-Lua/Checklists/archiv/Checklist.md). Verfügbare Module in
`C:\repos\lib.nvim`: `autocmd, buf_win_tab, buffer, cache, core, cross,
debounce, docmap, dotrepeat, fs, git, harvest, logger, lua_ls, map, neotree,
net, normalize, notify, progress, require, safe_api, selection, store, system,
terminal, token, treesitter, ui, usercmd, window` sowie `lib.lua.{lazy, memo,
tables, strings, error, json, …}`.

| Aktuell in `lua/lsp/**` | Ersetzen durch | Anmerkung |
|---|---|---|
| `require("lib.nvim.notify").create(…)` | bereits verwendet ✅ | konsistent beibehalten |
| `vim.keymap.set` (`diagnostics/keymaps.lua`) | `lib.nvim.map` | derzeit uneinheitlich |
| eigene `nvim_create_user_command` (`usercmds/formatter.lua:5`) | `lib.nvim.usercmd` | teils schon (`usercmd.create` in `diagnostics/commands.lua`) |
| ~30 Einzelcommands | `lib.nvim.usercmd.composer` | existiert (`lua/lib/nvim/usercmd/composer`) → `:Lsp`-Composer, s. §8.2 |
| eigene `nvim_create_autocmd` (`formatter/init.lua`) | `lib.nvim.autocmd` / `lib.nvim.augroup` | teilweise schon |
| `core/root_scope.lua`, `servers/lua_ls/rootresolver.lua`, `servers/marksman/rootresolver.lua` | `lib.nvim.fs.find_root` / `polymorphic_rootresolver` | **Dedup-Kandidat B8**: drei Re-Implementierungen desselben Problems |
| Library-Profile-Caching (`servers/lua_ls`, `lspdoctor`) | `lib.nvim.cache` | prüfen ob `stdpath("cache")`-konform |
| Format-on-Save-Timing, Diagnostics-Refresh | `lib.nvim.debounce` / `debounce.buffer` | derzeit kein Debouncing → Perf-Kandidat |
| `get_installed_lsps()` (`usercmds/completion.lua`) fragt bei jedem Tab-Complete Mason neu ab | `lib.lua.memo` | klarer Kandidat |
| Alle Tools werden in `init.lua` synchron geladen, unabhängig vom Filetype | `lib.lua.lazy` | `ts_type_lookup`, `deprecated_help` sind selten gebraucht |
| `vim.ui.select` (`root_scope_picker`, LspDoctor-Modus) | `lib.nvim.selection` / `lib.nvim.ui` | vor Verwendung API prüfen — `hover_select` war im Repo nicht auffindbar |
| Windows-Pfad im Formatter (B6) | `lib.nvim.cross` | Cross-Plattform-Regel |
| `lspdoctor`-Renderer, Progress bei Mason-Installs | `lib.nvim.ui`, `lib.nvim.progress` | Vorgabe §10 NEW_Project |
| Strukturierte Fehler / `safe_call` | `lib.lua.error`, `lib.nvim.safe_api` | ersetzt die vielen Ad-hoc-`pcall`-Ketten in `lsp/init.lua` |
| Doku-Generierung `docs/BINDINGS.md` | `lib.nvim.docmap` | prüfen, ob es die Keymap-Tabelle rendern kann |

---

## 11. checkhealth & LspDoctor

Pflicht laut Vorgabe: *„Jedes Plugin soll eine `:checkhealth` Funktionalität
besitzen“*. Heute existiert nur `:LspDoctor health` — **kein**
`:checkhealth`-Provider.

`lua/lsp/health.lua` wird eine **dünne zweite Schnittstelle auf denselben Kern**
(`lspdoctor/health.lua`), kein Code-Duplikat. Berichtet über
`vim.health.{start,ok,warn,error,info}`:

1. **Umgebung**: Neovim-Version ≥ 0.11, `lib.nvim` vorhanden
2. **Config**: aufgelöste Opts valide, Widersprüche `vim.g.lsp_nvim` ↔ `opts` (§6.2)
3. **Server**: konfiguriert vs. tatsächlich attached vs. Executable im `$PATH`
4. **Integrations**: pro Adapter `available()` + ob `setup()` erfolgreich war
5. **Keymaps**: registrierte Maps, Kollisionen mit fremden Mappings
6. **Formatter**: welcher Formatter würde für den aktuellen Buffer greifen,
   Prioritätskonflikte (die `lspdoctor`-Option `formatter_priority` gegen das
   tatsächliche Verhalten von `formatter/conform.lua` verifizieren)
7. **Performance**: Workspace-Diagnostics-Zustand, Anzahl geladener Buffer
8. Optional: Ergebnisse aus `docs/TESTS/**` bzw. `tools/_test`

---

## 12. Dokumentationspflichten

Aus [NEW_PROJECT.md](file:///C:/repos/WKDBooks/Development/wkdbook-Lua/Checklists/gates/NEW_PROJECT.md):

- `README.md` — **englisch**, ASCII-Art + Badges am Anfang, Table of Content
  (nur H2). Direkt nach der ASCII-Art ein `>`-Absatz mit Link auf das am besten
  ergänzende Plugin → **`dap.nvim`** (Schwester-Subsystem, gleiche Architektur)
  oder `lib.nvim` (harte Dependency). Vorschlag: `dap.nvim`.
- `/doc/lsp.txt` — englisch, `:h lsp.nvim`-fähig, `doc/tags` generieren
- `/docs/ROADMAP.md` — künftige Features (s. §14)
- `/docs/BINDINGS.md` — **alle** Keymaps, Usercmds, Autocmds; generiert aus der
  Keymap-Tabelle (§8.1)
- `/docs/UMBRELLA.md` — das Pack-System erklärt (§6): was wird installiert, wie
  wählt man ab, wie nutzt man `lsp.nvim` ohne Pack
- Installations-Spec für mehrere Package-Manager, mit explizitem
  `event`/`cmd`/`ft`; **kein** `dir = vim.env…`, **keine** Lizenzverweise
- `.luarc.json` + `stylua.toml` im Projektroot
- Abschließend alle Usercmds/Keymaps/Autocmds in
  [NEW_PROJECT.md](file:///C:/repos/WKDBooks/Development/wkdbook-Lua/Checklists/gates/NEW_PROJECT.md) eintragen

---

## 13. Migrationsplan

Bewusst in Phasen, damit die Config zwischen den Phasen immer lauffähig bleibt.

### Phase 0 — Vorarbeiten im Host (vor jedem Umzug)

1. ✅ **B1 gefixt** (2026-07-26): Merge-Konflikt-Marker aus
   `lsp/core/capabilities.lua` aufgelöst, Modul lädt wieder, Warn-Level als
   String. Verbleibende Verifikation im laufenden Neovim: dass mit geladenem
   `cmp_nvim_lsp` keine Warnung mehr kommt und `caps.textDocument.completion`
   aus cmp statt aus dem Fallback stammt.
2. ✅ **B4 und B2 aufgeräumt** (2026-08-23): der doppelte `lspdoctor.setup`
   zu einem Aufruf zusammengezogen (Effektivzustand unverändert, siehe die
   korrigierte B4-Zeile), die tote Taste `<leader>gtt` entfernt.
3. ✅ **B6 entschieden** (2026-08-23): veralteter Kommentar, keine reale
   Einschränkung — die plattformabhängigen Stellen sitzen in
   `formatter/conform.lua` und behandeln Windows bereits.

Damit ist Phase 0 abgeschlossen — **einschließlich** der Laufzeit-Verifikation
aus Punkt 1. Sie lief beim Umschalten in Phase 2 gegen die echte Config mit:
`capabilities.get()` liefert **0 Warnungen**, `snippetSupport = true` und ein
`resolveSupport` mit den fünf Feldern von `cmp_nvim_lsp`
(`documentation`, `additionalTextEdits`, `insertTextFormat`, `insertTextMode`,
`command`) statt der nackten Fallback-Struktur. Der B1-Fix wirkt also in einer
geladenen Config, nicht nur auf dem Papier.

Nebenbefund: die Annahme „headless hängt die volle Config zu lange" war falsch.
`nvim --headless "+qa!"` lädt sie in **rund 1,0-1,2 s**. Der frühere Dreiminuten-
Hänger kam von einem `vim.defer_fn`, das Neovim am Leben hielt, nicht von der
Config. Verifikationen gegen die echte Config sind damit billig — das gilt für
alle weiteren Phasen.

### Phase 1 — Gerüst

4. `C:\repos\lsp.nvim` aufbauen: `lua/lsp/{init,health}.lua`, `config/`,
   `bindings/`, `integrations/`, `@types/`, `doc/`, `docs/`, `.luarc.json`,
   `stylua.toml`, README-Skelett — nach Vorlage von `dap.nvim`/`filetree.nvim`.

   *Erledigt 2026-08-23.* Branch `main` (aus `master` umbenannt, GitHub-Default
   umgestellt, `origin/master` gelöscht), Repo-Description und Topics gesetzt.
   Angelegt: `lua/lsp/{init,health}.lua`, `config/{init,DEFAULTS,KEYMAPS}.lua`,
   `bindings/{init,keymaps,usrcmds,autocmds,which_key}.lua`, `@types/` je Ebene,
   `.luarc.json`, `stylua.toml`, `.luacheckrc`, `.gitattributes`, `.gitignore`,
   `scripts/gen_map.lua`, `.github/workflows/ci.yml`, `tests/smoke.lua`,
   `README.md`, `doc/lsp.nvim.txt`, `docs/BINDINGS.md`,
   `docs/CHECKLISTS/NEW_PROJECT.md`.

   Drei Abweichungen, alle im Checklisten-Protokoll begründet: die vimdoc heißt
   `lsp.nvim.txt` statt `lsp.txt` (Neovims Runtime belegt den Namen bereits),
   der Keymap-Katalog liegt in `config/KEYMAPS.lua` statt in `DEFAULTS.lua`
   (§8.1), und `NEW-20`s `--check`-CI-Job fehlt, weil `docs/map/` hier — wie in
   `dap.nvim` und `cascade.nvim` — nicht eingecheckt wird.

### Phase 2 — Kern umziehen (Schicht 1) — ✅ erledigt 2026-08-23

5. ✅ 164 Dateien kopiert, `debug_adapters/**` bewusst nicht.
6. ✅ Host-Kopplungen aufgelöst — es waren weniger als gedacht:
   - `machine.*` war in `core/attach.lua` **schon vorher** entfernt worden (der
     Kommentar dort erklärt, warum die Maschinenrolle ein schlechter Proxy für
     „großes Repo" war). Nichts zu tun.
   - `config.mason.*` ist mitgezogen als `lsp/integrations/mason/` (E2), nicht
     als Adapter auf ein Host-Modul.
   - `nvchad.*` ist an drei Stellen `pcall`-geschützt und bleibt vorerst so;
     der Adapter aus Phase 4 kann das später aufräumen.
   - **Neu gefunden:** `lua/@types/lsp.lua` (nur vom LSP-Subsystem benutzt) ist
     als `lsp/@types/vim_lsp.lua` mitgezogen, und
     `completion/personal_names` greift nicht mehr auf `plugins.personal.list`
     zu — die Liste ist Config-Daten, das Plugin bekommt sie über
     `setup({ labels = fn })` gereicht.
7. ✅ `ACTIVE` → `servers` (B7). B8 (Root-Resolver gegen `lib.nvim.fs`) ist
   **nicht** erledigt und bleibt offen — reines Verschieben war hier die
   richtige Größe, Dedup ist eine eigene Änderung.
8. ✅ `config/DEFAULTS.lua` + `config/init.lua`: `servers`, `diagnostics`,
   `formatter`, `attach`, `mason`, `lspdoctor`, `tools`, `languages`. Jeder Key
   wird von Code gelesen; `completion`/`rename`/`integrations` aus §9 fehlen
   weiterhin bewusst.
9. ✅ `health.lua` erweitert (Servers-Sektion: konfiguriert vs. aufgesetzt vs.
   attached) und verweist für die Buffer-Diagnose auf `:LspDoctor`, statt sie
   nachzubauen.
10. ✅ Umgeschaltet — mit einer Abweichung vom Plan: `require("lsp").setup(...)`
    bleibt in `startup.now("lsp", ...)` stehen und wandert **nicht** in einen
    `opts`-Block. Der Schritt ist absichtlich synchron und geordnet
    (Capabilities müssen global gesetzt sein, bevor der erste Client attached);
    `opts` würde diese Ordnung dem Plugin-Manager überlassen. Die Spec ist
    deshalb `lazy = false, priority = 900` ohne `opts`/`config`.

    Der alte Ordner ist `lua/lsp_legacy/**` — umbenannt, nicht gelöscht, weil
    ein `lua/lsp/` in der Config das Plugin vollständig überschattet und das
    Umbenennen die Voraussetzung dafür ist, dass sich der Umbau überhaupt
    testen lässt. Er liegt auf keinem require-Pfad. Wegwerfen, sobald eine
    echte Sitzung den Umbau bestätigt hat.

    Verifiziert (headless, gegen die echte Config): `require("lsp")` löst nach
    `C:/repos/lsp.nvim/lua/lsp/init.lua` auf, alle 8 Server aufgesetzt, **0**
    Setup-Warnungen, `:Lsp`/`:LspDoctor`/`:LspStatus`/`:DiagQF` registriert,
    und die beiden Module, die die Config-eigenen Keymaps noch anfassen
    (`lsp.core.root_scope_picker`, `lsp.servers.marksman.hints`), lösen aus dem
    Plugin auf.

    Zu `autocmds/events/utils/filetype.lua`: die Datei referenziert
    `lsp.languages.*` heute gar nicht mehr — der Hinweis war veraltet.

### Phase 3 — Bindings zentralisieren

11. `bindings/mappings/lsp.lua` + `bindings/mappings/trouble.lua` +
    `config/inc_rename` (Keymap) + die vier FzfLua-LSP-Keymaps nach
    `lsp/bindings/keymaps.lua` überführen, als deklarative Tabelle.
12. `:Lsp`-Composer + Legacy-Aliase (`bindings/usercmds.lua`).
13. which-key-Gruppen, `docs/BINDINGS.md` generieren.
14. Im Host: die migrierten Keymap-Module aus `bindings/mappings/init.lua`
    austragen und löschen.

### Phase 4 — Integrationen (Schicht 2)

15. Adapter für trouble, conform, lazydev, cmp/blink, mason,
    workspace-diagnostics, lspsaga, inc-rename, lensline, picker, which-key,
    noice, nvchad — je einer, je einzeln testbar.
16. B5 auflösen: **eine** Conform-Wahrheit.
17. `config/{trouble,inc_rename,mason,copilot}` im Host löschen.

### Phase 5 — Pack (Schicht 3)

18. `pack/{init,core,ui,completion}.lua` aus den heutigen Specs in
    `plugins/lsp.lua` + `plugins/trouble.lua` bauen.
19. Host-Spec auf `import = "lsp.pack"` umstellen, `plugins/lsp.lua` und
    `plugins/trouble.lua` löschen.

### Phase 6 — Abschluss

20. `debug_adapters/**` nach `dap.nvim` verschieben (unabhängig terminierbar).
21. `docs/**`, `doc/lsp.txt`, README, ROADMAP finalisieren; `gh repo edit`
    (Description, Topics), committen & pushen.
    (Branch `main` ist seit 2026-08-23 erledigt — s. Phase 1.)
22. Diesen Roadmap-Eintrag auf „abgeschlossen“ setzen, Memory-Notiz analog zu
    `lib-nvim-extraction.md` anlegen.

---

## 14. Roadmap: neue Features

Für `docs/ROADMAP.md` des neuen Plugins — nicht alles sofort umsetzen:

| Feature | Nutzen | Aufwand |
|---|---|---|
| **Inlay-Hints-Toggle** (`vim.lsp.inlay_hint`, global + per Filetype) | Nirgends in `lua/lsp/` referenziert, obwohl seit Neovim 0.10 nativ | klein |
| **Code-Action-Indikator** (Sign/virtueller Text, wenn `textDocument/codeAction` etwas liefert) | Sichtbarkeit ohne blindes `lsa` | mittel |
| **`:Lsp log`** (Log-Level-Toggle + Tail-Viewer im Scratch-Buffer) | Server-Abstürze heute nur über rohes `vim.lsp.log`-File | klein (Renderer existiert in `lspdoctor`) |
| **Auto-Restart mit Backoff** bei Client-Crash | `core/attach.lua` hat keine Crash-Behandlung | mittel |
| **Formatter-Prioritäts-Audit** | `lspdoctor` hat `formatter_priority` + `show_conflicts` — unklar, ob das in `formatter/conform.lua` durchgesetzt wird | klein (Audit) |
| **Workspace-Symbol-/Call-Hierarchy-Picker** über den `picker`-Adapter | Konsistente Picker-UI statt Ad-hoc-Telescope in `ts_type_lookup` | mittel |
| **Per-Projekt-Override** (`.nvim-lsp.json` im Repo-Root) | Server X in Projekt Y deaktivieren ohne globale Config-Änderung | mittel-groß |
| **Multi-Root/Monorepo-Workspace-Switcher** als eigenes Feature | Formalisiert, was in `root_scope_picker` halb existiert | klein |
| **Hover-Cache** via `lib.lua.memo` | Wiederholtes Hover auf gleicher Position/Version spart einen Roundtrip | klein |
| **Sprung zum Lua-Table-/Funktions-Root** (ehem. `<leader>gtt`) | Aus B2 gerettet: aus einer tief verschachtelten Lua-Tabelle an den Kopf der umschließenden Struktur springen, optional zentriert. Die Taste war jahrelang auf ein Modul gemappt, das es nie gab — das Feature war also gewollt, nur nie gebaut | mittel |
| **Diagnostics-Debounce** bei `publishDiagnostics` | `core/handlers.lua` dedupliziert, debounced aber nicht (chatty Server wie `ts_ls`) | klein |
| **Test-Entry-Point** (`tools/_test`) | Fehlt komplett — widerspricht Testbarkeits-Leitlinie | mittel |
| **Signature-Help-Modul reduzieren** | `tools/lsp_signature/**` ist eine komplette Eigenimplementierung (~800 LOC) | groß (erstmal nur beobachten) |
| **Keymap-Kollisionsprüfer** in `:checkhealth lsp` | Fällt fast gratis ab, sobald Keymaps deklarativ sind (§8.1) | klein |
| **Profil-Presets** (`preset = "lean"\|"default"\|"full"`) | Ein Schalter statt 20 Einzeloptionen für „schlank auf schwacher Maschine“ | mittel |

---

## 15. Entscheidungen & offene Fragen

### Entschieden (2026-07-26)

| # | Frage | Entscheidung |
|---|---|---|
| E1 | **Abhängigkeitsmodell** | Harte Dependencies sind **by design** erwünscht. Fremdplugins nachbauen bringt nichts. `pcall` bleibt als Blast-Radius-Begrenzung, nicht als Optionalitäts-Versprechen. → §3 |
| E2 | **Mason-Zuständigkeit** | `ensure_install` zieht **vollständig nach `lsp.nvim`** (`integrations/mason/`), nicht nach `lib.nvim`. `dap.nvim` meldet seine DAP-Pakete per `register("dap", …)` an. → §4 |
| E3 | **Keymap-Preset** (B10) | `ls*`-Belegung **bleibt**. Die Neovim-0.11-Defaults (`grr`/`gri`/`grn`/`grt`/`gO`) laufen buffer-lokal parallel weiter — kein Konflikt. → §8.1 |
| E4 | **B1 (Merge-Konflikt in `capabilities.lua`)** | **Erledigt**, vor der Migration im Host gefixt. |

### Aus dem NEW_PROJECT-Durchlauf (2026-08-23)

- **Die Modulwurzel `lsp` überschattet sich selbst.** Solange die Config ihr
  eigenes `lua/lsp/**` hat, gewinnt sie auf der `runtimepath` und `require("lsp")`
  landet dort, nicht im Plugin. Der erste Testlauf hat genau das getan und
  stillschweigend den falschen Code geprüft. Das ist kein Argument gegen die
  Namenswahl aus §5 — der Vorteil (alle `require("lsp.…")`-Pfade bleiben gültig)
  ist derselbe —, aber eine Bedingung, die dort fehlte: **Config-Ordner löschen
  und Plugin installieren müssen derselbe Schritt sein.** Ein Übergangszustand
  „beides da" ist nicht neutral, er ist unsichtbar kaputt. Für Phase 2 (§13,
  Schritt 10) heißt das: die dort vorgesehene Reihenfolge „erst umstellen, alten
  Ordner später löschen, wenn getestet" funktioniert so nicht — getestet werden
  kann erst *nach* dem Löschen. Vorschlag: Config-Ordner nach
  `lua/lsp_legacy/**` umbenennen statt löschen, dann umstellen, testen, und erst
  danach wegwerfen.
- **`doc/lsp.txt` ist vergeben.** Neovims Runtime liefert selbst eines (`:h lsp`).
  Die vimdoc heißt deshalb `doc/lsp.nvim.txt`, alle Tags sind `lsp.nvim-…`
  präfixiert, `*lsp*` bleibt unangetastet. §5 nennt noch `doc/lsp.txt`.
- **`NEW-20` widerspricht der jüngeren Map-Entscheidung.** Das Gate verlangt
  `scripts/gen_map.lua` **plus** `--check` in CI; `--check` prüft aber die
  eingecheckte Map, und die wird seit `dap.nvim`/`cascade.nvim` bewusst nicht
  mehr committet. Beides zusammen geht nicht. Gehört im Gate entschieden, nicht
  pro Repo still in eine Richtung aufgelöst.
- **Das Gate nennt zwei veraltete Pfade**: `e:\repos\` in `NEW-01`,
  `C:\Users\bartl\…` in `NEW-35`.

### Offen

1. **Trouble als Default-Senke für `]d`/`[d`**: durch Trouble oder immer nativ?
   — *Vorschlag: `diagnostics.ui = "auto"` (Trouble, wenn geladen).*
2. **Completion-Engine**: bleibt `nvim-cmp`, oder ist der Umzug auf `blink.cmp`
   Teil dieser Migration? Der auskommentierte Block in `plugins/lsp.lua:96-118`
   deutet auf einen abgebrochenen Versuch hin. — *Vorschlag: nicht Teil der
   Migration; beide Adapter bauen, Default `auto` (cmp bevorzugt, weil heute
   aktiv), Wechsel später als eigener Schritt.*
3. **Modulwurzel `lsp`**: freier Name, aber generisch. `dap.nvim` musste wegen
   Kollision auf `wkddap` ausweichen; bei `lsp` besteht diese Kollision nicht.
   — *Vorschlag: `lsp` behalten* (spart das Umschreiben aller `require`-Pfade,
   u. a. `autocmds/events/utils/filetype.lua:46-106`).
4. **Windows-Kompatibilität des Formatters** (B6): bewusste Einschränkung oder
   nachzuziehen? Die Workstation läuft auf Windows.
5. **`lspdoctor` vs. `:checkhealth`**: bestätigen, dass beide denselben Kern
   nutzen und nicht divergieren.
6. **`dap.nvim` ↔ `lsp.nvim`**: die Mason-Registrierungs-API (E2) macht
   `dap.nvim` weich abhängig von `lsp.nvim`. Akzeptabel, oder soll `dap.nvim`
   seine DAP-Pakete weiterhin selbst installieren? — *Vorschlag: API nutzen,
   pcall-geschützt, damit `dap.nvim` standalone lauffähig bleibt.*
7. **Umfang von Phase 1**: Pack sofort oder erst nach bewährtem Kern-Umzug?
   — *Vorschlag: Pack erst in Phase 5, damit ein Fehler im Pack nicht die
   Kern-Migration blockiert.*

---

## Aus `MyPlugin-Notes/LSPDoctor/` (Analyse 2026-08-08)

Quelle: `MyPlugin-Notes/LSPDoctor/{lspdoctor,lsprelive}.md` — **existiert
nicht mehr**: unter `C:\repos\Notes\MyPlugin-Notes\` liegen heute nur noch
`README-TEMPLATES/`, `_archive/`, `cmdlog/` und `nvim_cfg_patches/`. Der für
`lsp.nvim` relevante Inhalt ist unten festgehalten, das Original ist weg.

**Befund: die Notiz ist überholt.** Sie entwirft eine ~30-zeilige `M.check()`
(Mason da? LSP attached? Diagnostics vorhanden? trouble geladen?). Der reale
Stand ist `lspdoctor/**` mit 948 Zeilen und fünf Modi
(`:LspDoctor {health,debug,quick,deep,all}`) — siehe §11 dieses Dokuments.

Aufgehoben, weil sie zwei Dinge enthält, die im Konzept noch nicht stehen:

### 1. Kennzahl „installiert vs. attached"

`lsprelive.md` hält fest, warum die häufige Sorge unbegründet ist: Ein
installierter Server kostet nichts, solange er an keinen Buffer attached ist.
Teuer wird erst „viele grosse Buffer × schwerer Server" (tsserver, pyright).

- [ ] Als Zeile im `:checkhealth lsp`-Report ausgeben: *installiert: N,
      aktuell attached: M, davon in diesem Buffer: K* — plus Warnung erst, wenn
      ein bekannt schwerer Server über vielen Buffern hängt.

Das beantwortet die Frage, die man tatsächlich stellt, statt nur zu listen.

**Aufwand:** Quick Win
**Nutzen:** mittel.

### 2. Fehlerprovokation als Testhilfe

Die Notiz enthält absichtlich kaputte Snippets (Go: fehlende Klammer, JS:
`const x =`), um zu prüfen, ob Diagnostics überhaupt ankommen.

- [ ] In die Testsuite bzw. in `:LspDoctor deep` übernehmen: einen Scratch-Buffer
      mit garantiert fehlerhaftem Inhalt anlegen und prüfen, ob binnen Timeout
      Diagnostics eintreffen. Das unterscheidet „keine Fehler" von „Diagnostics
      kommen gar nicht an" — genau der Fall, der sonst stundenlang Zeit kostet.

**Aufwand:** Mittel
**Nutzen:** hoch — der einzige Check, der die Kette End-to-End verifiziert
statt nur Zustände abzufragen.
