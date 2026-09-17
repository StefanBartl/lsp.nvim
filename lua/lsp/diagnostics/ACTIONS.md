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

Severity arguments (optional) on the four commands spelled `[severity]` above.
`:DiagNextQF` and `:DiagPrevQF` take none: they step the quickfix list itself,
which `:DiagQF` has already filtered, and a trailing word there is `E488`.

* `error`
* `warn`
* `info`
* `hint`
* `all` or empty = no filter

Those five are what `<Tab>` offers. The short forms are typeable too — `err`,
`e`; `warning`, `w`; `i`; `h` — they just do not clutter a five-item list with
eleven entries. Anything else is refused by name rather than widened to every
severity: `:DiagLoc eror` answers
`unknown severity 'eror' (expected one of: all, error, warn, info, hint)`,
because listing everything would look like it had worked.

---

## Keymaps

* `<leader>wq` → same as `:DiagQF`
* `<leader>lq` → same as `:DiagLoc`

Loclist / buffer navigation:

* `]d`, `[d` — **not** aliases for `:DiagNextLoc`/`:DiagPrevLoc`. They route
  through `diagnostics.ui`: with Trouble installed and `ui` left at `"auto"`
  (or set to `"trouble"`) they open and move inside Trouble's diagnostics list;
  only `"native"`, or an absent Trouble, falls through to the same buffer jump
  the commands make. They take a count instead of a severity — `3]d` moves
  three diagnostics on — where `:DiagNextLoc [severity]` takes a severity and
  moves one.

Quickfix navigation:

* `]q` → same as `:DiagNextQF`
* `[q` → same as `:DiagPrevQF`

---
