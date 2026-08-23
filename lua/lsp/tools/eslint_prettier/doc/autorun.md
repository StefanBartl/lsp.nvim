# Autorun (automatisches Lint+Format beim Speichern)

## Zweck
Diese Datei erklärt das Verhalten des automatischen Ausführens von `eslint_d` und `prettier` beim Speichern einer Datei, wie man es ein- und ausschaltet und wie man das Verhalten an Projektanforderungen anpasst.

## Standardverhalten
- Standardmäßig ist das automatische Ausführen beim Speichern aktiviert (`enabled = true`).
- Wenn eine Datei gespeichert wird (`BufWritePre`) prüft das Plugin:
  1. Ist der Dateityp einer der unterstützten (z. B. `javascript`, `typescript`, `vue`, `svelte`)?
  2. Befindet sich im Projekt-Root eine ESLint- bzw. Prettier-Konfiguration?
- Nur wenn die jeweilige Konfiguration vorhanden ist, wird `eslint_d --fix` bzw. `prettier --write` gestartet.
- Die Binärdateien werden automatisch aufgelöst:
  - zuerst per `executable(name)` (PATH),
  - danach im Mason-Bin-Ordner (`stdpath('data') .. '/mason/bin'`) (inkl. `.cmd`-Fallback auf Windows).
- Damit funktioniert Mason-Installation standardmäßig unter Linux/macOS/Windows ohne manuelles PATH-Tweaking.

## Toggle / Benutzersteuerung
- Es existiert ein Usercommand `:ToggleLintFormatOnSave`, das global das automatische Verhalten ein- bzw. ausschaltet.
- `:ToggleLintFormatOnSave` ändert direkt das globale Flag `require('lsp.tools.eslint_prettier')._enabled`.
- Nach Umschalten erhält man eine kurze Notification, die den aktuellen Zustand anzeigt.

## Beispiele
- De-/Aktivieren:
  - `:ToggleLintFormatOnSave` — toggelt global.
- Falls man die automatische Ausführung pro Session programmatisch ändern will:
  ```lua
  -- disable autorun for current session
  require("lsp.tools.eslint_prettier")._enabled = false

  -- enable autorun for current session
  require("lsp.tools.eslint_prettier")._enabled = true
