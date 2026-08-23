# LSP Diagnostic Actions

## Table of content

  - [User Commands](#user-commands)
    - [Quickfix (Workspace)](#quickfix-workspace)
    - [Loclist (Buffer-lokal)](#loclist-buffer-lokal)
  - [Keymaps](#keymaps)
  - [Aktualisiertes ASCII-Architekturdiagramm](#aktualisiertes-ascii-architekturdiagramm)

---

## User Commands

### Quickfix (Workspace)

* `:DiagQF [severity]`
  Baut die Quickfix-Liste aus Workspace-Diagnostics und öffnet sie.
  Entspricht `<leader>wq`.

* `:DiagNextQF`
  Springt zum nächsten Eintrag in der Quickfix-Liste.

* `:DiagPrevQF`
  Springt zum vorherigen Eintrag in der Quickfix-Liste.

* `:DiagNextQF!`
  Erzwingt Navigation im Workspace (Quickfix), auch wenn Loclist aktiv ist.

* `:DiagPrevQF!`
  Erzwingt Navigation im Workspace (Quickfix), auch wenn Loclist aktiv ist.

### Loclist (Buffer-lokal)

* `:DiagLoc [severity]`
  Baut die Location-List aus Buffer-Diagnostics und öffnet sie.
  Entspricht `<leader>lq`.

* `:DiagNextLoc [severity]`
  Springt zum nächsten Diagnostic im aktuellen Buffer (Loclist-orientiert).

* `:DiagPrevLoc [severity]`
  Springt zum vorherigen Diagnostic im aktuellen Buffer.

* `:DiagNextLoc! [severity]`
  Erzwingt Buffer-lokale Navigation (Loclist), unabhängig von Quickfix.

* `:DiagPrevLoc! [severity]`
  Erzwingt Buffer-lokale Navigation (Loclist), unabhängig von Quickfix.

Severity-Argumente (optional, überall gleich):

* `error`
* `warn`
* `info`
* `hint`
* `all` oder leer = kein Filter

---

## Keymaps

* `<leader>wq` → `:DiagQF`
* `<leader>lq` → `:DiagLoc`

Navigation Loclist / Buffer:

* `]d` → `:DiagNextLoc`
* `[d` → `:DiagPrevLoc`

Navigation Quickfix:

* `]q` → `:DiagNextQF`
* `[q` → `:DiagPrevQF`

---
