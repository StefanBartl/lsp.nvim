# NEW_PROJECT — abgehakt für `lsp.nvim`

Durchlauf des Gates
`WKDBooks/Development/wkdbook-Lua/Checklists/gates/NEW_PROJECT.md`
(`NEW-01` … `NEW-35`). Erstmals durchgegangen am 2026-08-23, als das Repo noch
ein Gerüst war; nach der Migration am selben Tag nachgeführt — mehrere Punkte
waren damals mit „noch leer“ oder „noch nicht zutreffend“ begründet und sind
es nicht mehr.

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
- [x] `NEW-10` `:checkhealth lsp` — fünf Sektionen (Umgebung, Plugin, Server,
      Ökosystem, Verweis auf `:LspDoctor`), liest `require("lsp").status()`,
      damit Health und `:Lsp status` nicht auseinanderlaufen können. Die
      Plugin-Liste kommt aus der Adapter-Registry, nicht aus einer zweiten
      handgepflegten Tabelle.

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
- [x] `NEW-14` Roadmap/Konzeptpapier angelegt, deutsch.
- [x] `NEW-15` `docs/BINDINGS.md` — 42 Keymaps, 15 `:Lsp`-Routen samt
      Alias-Zuordnung, Autocommands. Die Keymap-Tabellen werden von
      `scripts/gen_bindings.lua` aus dem Katalog **generiert**, CI prüft mit
      `--check`; Doku und Code können nicht mehr auseinanderlaufen.
      Zusätzlich die sechs Seiten aus §12 des Konzepts (`installation`,
      `configuration`, `features`, `commands`, `architecture`, `health`).

## 4. Abhängigkeiten und Bibliothek

- [x] `NEW-16` `lib.nvim` als Dependency in allen Installations-Specs und im
      CI-Checkout. **Hart** im Sinne von `LUA-01`: nacktes `require`, kein
      Fallback, und in der Doku nirgends als optional dargestellt.
- [x] `NEW-17` lib.nvim-Module statt Eigenbauten: `map`, `notify`,
      `usercmd`, `usercmd.composer`, `autocmd`, `window.open_scratch_split`,
      `fs.polymorphic_rootresolver`, `fs.is_subpath`. Der Durchgang nach der
      Migration hat 21 direkte `nvim_create_user_command`-Aufrufe, die
      Autocommand-Registrierung, ein `vim.keymap.set` und ein `vim.notify`
      ersetzt — `LUA-01` verlangt Konsistenz, und lib.nvim ist hier hart.
- [x] `NEW-18` Funktionen nach `lib.nvim` transferieren — erledigt 2026-08-23,
      nach der Migration. `lib.nvim.fs.polymorphic_rootresolver` hat einen
      `resolve`-Hook bekommen, damit beide Root-Resolver dieses Plugins sich das
      Argument-Plumbing teilen statt es zu kopieren (B8). Beim selben Durchgang
      ist ein Bug **oben** behoben statt hier umgangen (LUA-02):
      `lib.nvim.bindings.autocmd.group` cachte Augroup-IDs und prüfte sie nie wieder
      (B19).
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
      (alles), `keymaps.preset` (`default`/`minimal`/`none`),
      `keymaps.map.<action>` (einzeln — String ersetzt das lhs, `false`
      entfernt die Map). Der Katalog hat 42 Einträge; Specs prüfen, dass keine
      zwei dieselbe Taste im selben Mode beanspruchen und dass `minimal`
      Teilmenge von `default` bleibt.
- [x] `NEW-22` which-key-Unterstützung, v2- und v3-API, weiche Abhängigkeit.
      Gruppen werden aus den tatsächlich gebundenen Keymaps abgeleitet, nicht
      aus einer zweiten handgepflegten Liste.
- [x] `NEW-23` Compound-Usercommand `:Lsp <subcommand>` über
      `lib.nvim.bindings.usercmd.composer`, mit `<Tab>`-Completion.
  - [x] Range (`v`, `v-line`, `v-block`): geprüft, auch für die inzwischen
        vorhandenen Routen aus §8.2 — **keine** bekommt eine. `status`,
        `servers`, `info`, `health`, `doctor`, `log`, `root`, `workspace` und
        die Lifecycle-Routen betreffen den Buffer oder globalen Zustand, den
        eine Zeilen-Range nicht einschränkt. `format` wäre der plausibelste
        Kandidat, aber conform formatiert über `formatter.format(bufnr)` den
        ganzen Buffer; eine Range-Variante wäre eine andere Operation, kein
        Argument — sie gehört in §14, nicht in eine stillschweigend ignorierte
        `range = true`-Flagge.
- [x] `NEW-24` Default-aktiv: `require("lsp").setup()` ohne Argumente ergibt
      ein vollständiges Setup, alle Schalter stehen auf `true`.
- [x] `NEW-25` Count-Support — erledigt 2026-08-23, nachdem der Katalog
      existierte. `v:count1` wirkt auf genau die acht Tasten, die eine Bewegung
      sind: `]d`/`[d`, `]q`/`[q`, `]l`/`[l`, `]w`/`[w`. `3]q` springt drei
      Quickfix-Einträge weiter.

      Kein naives `for i = 1, count`: `:{count}cnext` und
      `vim.diagnostic.jump({ count = N })` können das nativ, feuern die
      Autocommands einmal statt N-mal und laufen so weit wie möglich, statt am
      ersten E553 stehenzubleiben. Nur Troubles `next`/`prev` brauchen eine
      Schleife, weil sie keinen Count kennen.

      **Keinen** Count bekommen die leader-präfixierten Aktionen: eine Liste
      füllen oder eine Einstellung umschalten hat kein geordnetes Ziel, in das
      ein Count indizieren könnte. Die `:Lsp diag next|prev`-Routen übergeben
      explizit `1`, weil `v:count` dort den Rest eines früheren Tastendrucks
      enthielte — ein Command ist kein Tastendruck.
- [x] `NEW-26` Completion für Ex-Argumente: jede geschlossene Menge completet
      (`format`, `diag`, `workspace`, `root`, `doctor`, `log level`).
      Server-Namen laufen über einen eigenen Composer-Argumenttyp und kommen
      aus dem **lebenden** Satz — attachte Clients zuerst, dann alles aus
      `servers` — weil ein bei der Registrierung eingefrorenes Enum veraltet,
      sobald ein Server dazukommt. Genau der Fall, den `NEW-26` mit „live aus
      dem aktuellen Zustand“ meint.

## 6. Konfigurierbarkeit

- [x] `NEW-27` Defaults in `config/DEFAULTS.lua`, Einstieg `config/init.lua`,
      Zugriff ausschließlich über `config.get()`.
- [x] `NEW-28` Jeder Konfigurations-Key hat einen Typ (`lsp/@types/init.lua`:
      `LspNvim.Config`, `LspNvim.KeymapsOpts`, `LspNvim.KeymapPreset`, …).
- [x] `NEW-29` Abgeklopft, zuletzt nach Phase 5. Vorhanden sind `servers`,
      `diagnostics`, `formatter`, `attach`, `mason`, `lspdoctor`, `tools`,
      `languages`, `rename`, `keymaps`, `usrcmds`, `which_key` — jeder Key wird
      von Code gelesen. `completion` und `integrations` aus §9 fehlen weiterhin
      **bewusst**: ein Default, den kein Code liest, ist ein Versprechen, das
      das Plugin nicht hält. Die Engine-Wahl liegt aus Timing-Gründen in
      `vim.g.lsp_nvim.pack.completion`, nicht in `opts`.

## 7. Cross-Plattform

- [x] `NEW-30` Kein OS-spezifischer Code; Pfade laufen über `vim.fn`/`vim.fs`,
      `.gitattributes` erzwingt LF.
- [x] `NEW-31` Alternative bereitstellen — die plattformabhängigen Stellen
      kamen mit dem Kern und behandeln Windows bereits:
      `formatter/conform.lua` verzweigt auf PATH-Separator, `.cmd`-Suffix und
      Mason-Bin-Pfad. B6 war nur ein veralteter Kopfkommentar in
      `formatter/init.lua`, der das als Einschränkung des Moduls las.

## 8. Abschluss

- [x] `NEW-32` Aufgefallene Features gleich umgesetzt: `:Lsp log open` und
      `:Lsp log level` aus Roadmap §14 — sie brauchen nichts aus der Migration
      und lösen genau das Problem, dass Server-Abstürze bisher nur über die
      rohe Log-Datei sichtbar waren.
- [x] `NEW-33` Größere Ideen stehen in der Roadmap, nicht im Code.
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
   geprüft (`TESTS/smoke.lua` prependet deshalb mit `rtp^=`, nicht `rtp+=`).
   Konsequenz für die Migration: Config-Ordner löschen und Plugin installieren
   müssen **derselbe** Schritt sein. Das ist kein Nachteil der Namenswahl aus
   Roadmap §5, aber eine Bedingung, die dort noch nicht steht.
2. **`doc/lsp.txt` kollidiert mit Neovims Runtime-Doku.** Siehe `NEW-13`.
3. **`NEW-20` widerspricht der jüngeren Map-Entscheidung.** Siehe dort.
4. **Das Gate nennt zwei veraltete Pfade** — `e:\repos\` in `NEW-01` und
   `C:\Users\bartl\…` in `NEW-35`. Beide sind heute anders.

Punkt 3 und 4 gehören zurück ins Gate; sie sind hier nur festgehalten, nicht
entschieden.
