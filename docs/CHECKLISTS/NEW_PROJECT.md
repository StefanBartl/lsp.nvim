# NEW_PROJECT — abgehakt für `lsp.nvim`

Durchlauf des Gates
`WKDBooks/Development/wkdbook-Lua/Checklists/gates/NEW_PROJECT.md`
(`NEW-01` … `NEW-35`), Stand 2026-08-23.

Regel des Gates: was nicht zutrifft, wird abgehakt **mit** Notiz, warum nicht.
Entsprechend steht hinter jedem offenen oder abweichenden Punkt eine
Begründung, nicht nur ein leeres Kästchen.

Legende: `[x]` erledigt · `[~]` teilweise, mit Begründung · `[ ]` offen oder
nicht zutreffend, mit Begründung.

## 1. Repository

- [x] `NEW-01` Repo angelegt und gepusht — unter `C:\repos\lsp.nvim`. Das Gate
      nennt noch `e:\repos\`; alle Repos liegen inzwischen auf `C:`.
- [x] `NEW-02` Default-Branch `main` — aus `master` umbenannt, GitHub-Default
      umgestellt, `origin/master` gelöscht.
- [x] `NEW-03` `.luarc.json` im Projektroot.
- [x] `NEW-04` `gh repo edit --description` gesetzt. `--homepage` bewusst leer:
      es gibt keine Projektseite, und keines der Schwesterrepos setzt eine.
- [x] `NEW-05` Topics: `neovim, lua, plugin, neovim-plugin, lsp,
      nvim-lspconfig, diagnostics, language-server`.
- [x] `NEW-06` Keine Lizenzdatei, keine Lizenzverweise.

## 2. Verzeichnisstruktur

- [x] `NEW-07` `config/` mit `DEFAULTS.lua` und `init.lua`. Zusätzlich
      `config/KEYMAPS.lua` — der deklarative Keymap-Katalog. §8.1 der Roadmap
      legt ihn in `DEFAULTS.lua`; er steht in einer eigenen Datei, damit
      `DEFAULTS.lua` eine reine Konfigurationstabelle bleibt. Der Katalog ist
      Binding-Daten, die der User *über* `keymaps.map` überschreibt, kein Wert,
      den er direkt setzt.
- [x] `NEW-08` `bindings/` mit `keymaps.lua`, `usrcmds.lua`, `autocmds.lua` —
      dazu `which_key.lua` und ein `init.lua`, das die Reihenfolge festlegt.
- [x] `NEW-09` `@types`-Ordner je Ebene (`lsp/`, `lsp/config/`,
      `lsp/bindings/`), alle mit `return {}`.
- [x] `NEW-10` `:checkhealth lsp` — vier Sektionen, liest
      `require("lsp").status()`, damit Health und `:Lsp status` nicht
      auseinanderlaufen können.

## 3. Dokumentation

- [x] `NEW-11` `README.md` englisch, ASCII-Art und Badges am Anfang, Table of
      Content nur mit Level-2-Überschriften.
- [x] `NEW-12` `>`-Absatz nach der ASCII-Art mit Link auf `dap.nvim` — dasselbe
      Architekturmuster auf das jeweils andere Protokoll angewandt.
- [~] `NEW-13` vimdoc englisch — als **`doc/lsp.nvim.txt`**, nicht `doc/lsp.txt`.
      Neovims eigene Runtime liefert bereits ein `doc/lsp.txt` (`:h lsp`); eine
      zweite Datei gleichen Namens macht `:help lsp.txt` mehrdeutig. Aus
      demselben Grund ist jedes Tag `lsp.nvim-…` präfixiert und `*lsp*` bleibt
      unangetastet. Abweichung vom Gate-Wortlaut, dokumentiert.
- [x] `NEW-14` `docs/ROADMAP.md` — Spiegel des Konzeptpapiers aus der
      nvim-Config (dort die Source of Truth), deutsch.
- [x] `NEW-15` `docs/BINDINGS.md` — Keymaps (derzeit keine, mit Begründung),
      `:Lsp`-Routen, Autocommands (derzeit keine).

## 4. Abhängigkeiten und Bibliothek

- [x] `NEW-16` `lib.nvim` als Dependency in allen Installations-Specs und im
      CI-Checkout. **Hart** im Sinne von `LUA-01`: nacktes `require`, kein
      Fallback, und in der Doku nirgends als optional dargestellt.
- [x] `NEW-17` lib.nvim-Module statt Eigenbauten: `lib.nvim.map`,
      `lib.nvim.notify`, `lib.nvim.usercmd.composer`,
      `lib.nvim.window.open_scratch_split`.
- [ ] `NEW-18` Funktionen nach `lib.nvim` transferieren — nichts zu
      transferieren: das Gerüst enthält keine Funktion, die über dieses Plugin
      hinaus interessant wäre. Bei der Migration erneut prüfen; die Roadmap
      nennt in §10 bereits drei Root-Resolver, die dort landen sollen.
- [x] `NEW-19` `documentation.nvim` als Dev-Dependency eingerichtet
      (`scripts/gen_map.lua`, CI-Checkout nach `.deps/`).
- [~] `NEW-20` `scripts/gen_map.lua` übernommen, `--check` **nicht** in CI.
      Grund: `--check` verifiziert die *committete* Map. `docs/map/` ist hier
      gitignored — dieselbe Entscheidung wie in `dap.nvim` und in
      `cascade.nvim` (dortiger Commit „chore: stop committing the generated
      module map"). Beides zusammen geht nicht: entweder die Map wird
      eingecheckt und `--check` ist sinnvoll, oder sie bleibt Derivat und der
      Job prüft nichts. Der Konflikt zwischen `NEW-20` und der jüngeren
      Entscheidung ist offen und gehört ins Gate zurückentschieden, nicht hier
      still in eine Richtung aufgelöst. Die Layer-Regeln in `gen_map.lua` sind
      trotzdem schon deklariert, damit sie ab der ersten Kernzeile greifen.

## 5. Bedienung

- [x] `NEW-21` Keymaps modifizierbar und deaktivierbar: `keymaps.enable`
      (alles), `keymaps.preset` (Umfang), `keymaps.map.<action>` (einzeln —
      String ersetzt das lhs, `false` entfernt die Map). Der Mechanismus steht;
      der Katalog ist leer (siehe `docs/BINDINGS.md`).
- [x] `NEW-22` which-key-Unterstützung, v2- und v3-API, weiche Abhängigkeit.
      Gruppen werden aus den tatsächlich gebundenen Keymaps abgeleitet, nicht
      aus einer zweiten handgepflegten Liste.
- [x] `NEW-23` Compound-Usercommand `:Lsp <subcommand>` über
      `lib.nvim.usercmd.composer`, mit `<Tab>`-Completion.
  - [ ] Range (`v`, `v-line`, `v-block`): für die vorhandenen Routen nicht
        sinnvoll — `status`, `servers`, `health` und `log` berichten globalen
        Zustand, eine Zeilen-Range hat dort keine Bedeutung. Bei den Routen aus
        Roadmap §8.2 erneut prüfen: `format` und `diag` sind die Kandidaten,
        bei denen eine Range etwas heißt.
- [x] `NEW-24` Default-aktiv: `require("lsp").setup()` ohne Argumente ergibt
      ein vollständiges Setup, alle Schalter stehen auf `true`.
- [ ] `NEW-25` Count-Support — nicht zutreffend, solange keine Keymap
      existiert. Die Prüfung gehört an den Katalog aus Phase 3; Kandidaten sind
      dort `]d`/`[d` und `]q`/`[q` (natürliches „N mal weiter").
- [x] `NEW-26` Completion für Ex-Argumente: `:Lsp log level` completet über die
      geschlossene Menge der Log-Level. Andere Argumente gibt es noch nicht.

## 6. Konfigurierbarkeit

- [x] `NEW-27` Defaults in `config/DEFAULTS.lua`, Einstieg `config/init.lua`,
      Zugriff ausschließlich über `config.get()`.
- [x] `NEW-28` Jeder Konfigurations-Key hat einen Typ (`lsp/@types/init.lua`:
      `LspNvim.Config`, `LspNvim.KeymapsOpts`, `LspNvim.KeymapPreset`, …).
- [x] `NEW-29` Abgeklopft. Die großen Optionsgruppen aus Roadmap §9
      (`servers`, `diagnostics`, `formatter`, `completion`, `rename`, `tools`,
      `integrations`, `mason`) fehlen **bewusst**: ein Default, den kein Code
      liest, ist ein Versprechen, das das Plugin nicht hält. Sie kommen mit dem
      Code, der sie auswertet.

## 7. Cross-Plattform

- [x] `NEW-30` Kein OS-spezifischer Code; Pfade laufen über `vim.fn`/`vim.fs`,
      `.gitattributes` erzwingt LF.
- [ ] `NEW-31` Alternative bereitstellen — nicht nötig, es gibt keine
      plattformabhängige Stelle. Bei der Migration relevant: Roadmap-Befund B6
      (`formatter/init.lua` dokumentiert sich als „Linux/macOS only", die
      Workstation läuft auf Windows).

## 8. Abschluss

- [x] `NEW-32` Aufgefallene Features gleich umgesetzt: `:Lsp log open` und
      `:Lsp log level` aus Roadmap §14 — sie brauchen nichts aus der Migration
      und lösen genau das Problem, dass Server-Abstürze bisher nur über die
      rohe Log-Datei sichtbar waren.
- [x] `NEW-33` Größere Ideen stehen in `docs/ROADMAP.md`, nicht im Code.
- [x] `NEW-34` Committet und gepusht.
- [x] `NEW-35` In die zentrale Bindings-Sammlung eingetragen:
      `AppData\Local\nvim\docs\NOTES\PersonelPlugins\BINDINGS\` (Keymaps und
      Usercmds). Das Gate nennt dort noch `C:\Users\bartl\…` — der reale Pfad
      ist `C:\Users\StefanBartl\…`.

## Befunde aus dem Durchlauf

Vier Dinge, die erst beim Anwenden aufgefallen sind:

1. **Die Modulwurzel `lsp` kollidiert mit der Config.** Solange die nvim-Config
   ihr eigenes `lua/lsp/**` hat, gewinnt sie auf der `runtimepath` und
   überschattet das Plugin vollständig — `require("lsp")` landet in der Config.
   Der erste Testlauf hat genau das getan und stillschweigend den falschen Code
   geprüft (`tests/smoke.lua` prependet deshalb mit `rtp^=`, nicht `rtp+=`).
   Konsequenz für die Migration: Config-Ordner löschen und Plugin installieren
   müssen **derselbe** Schritt sein. Das ist kein Nachteil der Namenswahl aus
   Roadmap §5, aber eine Bedingung, die dort noch nicht steht.
2. **`doc/lsp.txt` kollidiert mit Neovims Runtime-Doku.** Siehe `NEW-13`.
3. **`NEW-20` widerspricht der jüngeren Map-Entscheidung.** Siehe dort.
4. **Das Gate nennt zwei veraltete Pfade** — `e:\repos\` in `NEW-01` und
   `C:\Users\bartl\…` in `NEW-35`. Beide sind heute anders.

Punkt 3 und 4 gehören zurück ins Gate; sie sind hier nur festgehalten, nicht
entschieden.
