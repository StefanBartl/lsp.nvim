# LSP Diagnostic Actions

## Table of content

  - [User Commands](#user-commands)
    - [Quickfix (workspace)](#quickfix-workspace)
    - [Loclist (buffer-local)](#loclist-buffer-local)
  - [Keymaps](#keymaps)

---

## User Commands

### Quickfix (workspace)

* `:DiagQF [severity]`
  Builds the quickfix list from workspace diagnostics and opens it.
  Equivalent to `<leader>wq`.

* `:DiagNextQF`
  Jumps to the next entry in the quickfix list.

* `:DiagPrevQF`
  Jumps to the previous entry in the quickfix list.

* `:DiagNextQF!`
  Forces navigation in the workspace (quickfix), even when the loclist is active.

* `:DiagPrevQF!`
  Forces navigation in the workspace (quickfix), even when the loclist is active.

### Loclist (buffer-local)

* `:DiagLoc [severity]`
  Builds the location list from buffer diagnostics and opens it.
  Equivalent to `<leader>lq`.

* `:DiagNextLoc [severity]`
  Jumps to the next diagnostic in the current buffer (loclist-oriented).

* `:DiagPrevLoc [severity]`
  Jumps to the previous diagnostic in the current buffer.

* `:DiagNextLoc! [severity]`
  Forces buffer-local navigation (loclist), independently of the quickfix list.

* `:DiagPrevLoc! [severity]`
  Forces buffer-local navigation (loclist), independently of the quickfix list.

Severity arguments (optional, the same everywhere):

* `error`
* `warn`
* `info`
* `hint`
* `all` or empty = no filter

---

## Keymaps

* `<leader>wq` → `:DiagQF`
* `<leader>lq` → `:DiagLoc`

Loclist / buffer navigation:

* `]d` → `:DiagNextLoc`
* `[d` → `:DiagPrevLoc`

Quickfix navigation:

* `]q` → `:DiagNextQF`
* `[q` → `:DiagPrevQF`

---
