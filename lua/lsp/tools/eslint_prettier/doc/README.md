# lsp.tools.eslint_prettier — README / Quickstart

## Ziel
Dieses Modul ermöglicht es, `eslint_d` und `prettier` (via Mason) in Neovim einfach zu verwenden.
Man erhält Usercommands zum manuellen Ausführen und einen optionalen Autostart beim Speichern.

## Voraussetzungen
- Neovim (0.8+ empfohlen)
- Mason (für Binärinstallation)
  - `:MasonInstall eslint_d prettier`
- Projekt muss eine ESLint- und/oder Prettier-Konfigurationsdatei im Projekt-Root haben:
  - `.eslintrc`, `.eslintrc.json`, `.eslintrc.js`, `package.json` mit `eslintConfig`, usw.
  - `.prettierrc`, `prettier.config.js`, `package.json` mit `prettier`, usw.

## Beispiel: minimale Projekt-Konfiguration

### package.json (Beispielauszug)
```json
{
  "name": "example",
  "version": "1.0.0",
  "eslintConfig": {
    "env": { "browser": true, "es2021": true },
    "extends": "eslint:recommended",
    "parserOptions": { "ecmaVersion": 2021, "sourceType": "module" },
    "rules": {}
  },
  "prettier": {
    "printWidth": 80,
    "singleQuote": true,
    "trailingComma": "es5"
  }
}
````

### .eslintrc.json (Alternative)

```json
{
  "env": { "browser": true, "es2021": true },
  "extends": "eslint:recommended",
  "parserOptions": { "ecmaVersion": 2021, "sourceType": "module" },
  "rules": {}
}
```

### .prettierrc (Alternative)

```json
{
  "printWidth": 80,
  "singleQuote": true,
  "trailingComma": "es5"
}
```

## Neovim: Einbindung (init.lua)

```lua
-- Ensure plugin files are located under 'lua/lsp/tools/eslint_prettier'.
-- Then call setup from your Neovim config.

require("lsp.tools.eslint_prettier").setup({
  -- optional: provide custom binaries if Mason is not in the default location
  -- binaries = {
  --   eslint = "C:\\Users\\me\\AppData\\Local\\nvim-data\\mason\\bin\\eslint_d.cmd",
  --   prettier = "C:\\Users\\me\\AppData\\Local\\nvim-data\\mason\\bin\\prettier.cmd"
  -- },
  filetypes = { "javascript", "typescript", "javascriptreact", "typescriptreact" },
  enable_on_setup = true, -- initial autorun state
})
```

## Nutzung

* Manuell:

  * `:EslintFix` — führt `eslint_d --fix` für aktuelle Datei aus (falls ESLint config vorhanden)
  * `:PrettierFormat` — führt `prettier --write` für aktuelle Datei aus (falls Prettier config vorhanden)
  * `:LintAndFormat` — führt beide nacheinander aus (ESLint → Prettier)
* Automatisch beim Speichern:
  * Standardmäßig aktiv (sofern `enable_on_setup = true`)
  * `:ToggleLintFormatOnSave` — toggelt global das Autorun-Verhalten

## Hinweise & Troubleshooting

* Wenn Tools nicht gefunden werden:

  * Prüfen, ob Mason die Tools installiert hat: `:Mason` UI oder `:MasonInstall eslint_d prettier`.
  * Standard Mason-Bin-Ordner ist `stdpath('data') .. '/mason/bin'`. Das Plugin sucht dort automatisch nach den Binaries (auch auf Windows mit `.cmd`-Suffix).
  * Falls Mason an einem anderen Ort liegt, über `setup{ binaries = {...} }` explizit Pfade angeben.
* Performance:

  * Die meisten Aufrufe laufen asynchron; bei sehr großen Dateien kann es sinnvoll sein, Autorun zu deaktivieren und manuell zu formatieren.
* Weiterentwicklung:

  * Wer Diagnostics aus ESLint in Neovim sehen möchte, sollte `null-ls` oder eine native LSP-Integration verwenden.

## Lizenz / Sonstiges

* Das Modul ist als Neovim-Lua-Helper gedacht; man kann die Implementation an projekt- oder teamweite Bedürfnisse anpassen.

