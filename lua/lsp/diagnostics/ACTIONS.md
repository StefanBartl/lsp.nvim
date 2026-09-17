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

### Loclist (buffer-local)

* `:DiagLoc [severity]`
  Builds the location list from buffer diagnostics and opens it.
  Equivalent to `<leader>lq`.

* `:DiagNextLoc [severity]`
  Jumps to the next diagnostic in the current buffer (loclist-oriented).

* `:DiagPrevLoc [severity]`
  Jumps to the previous diagnostic in the current buffer.

None of these commands takes a `!`. This file used to list `:DiagNextQF!`,
`:DiagPrevQF!`, `:DiagNextLoc!` and `:DiagPrevLoc!` as ways to force one list
or the other; there is no mode to force. `:DiagNextLoc` always steps the
current buffer's diagnostics and `:DiagNextQF` always steps the quickfix list,
whatever else is open. The two QF commands did accept the bang and then ignored
it; the two Loc commands answered `E477: No ! allowed`.

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
