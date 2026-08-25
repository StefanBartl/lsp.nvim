# Autorun (automatic lint+format on save)

## Purpose
This file explains the behaviour of running `eslint_d` and `prettier` automatically when a file is saved, how to switch it on and off, and how to adapt the behaviour to project requirements.

## Default behaviour
- Running automatically on save is enabled by default (`enabled = true`).
- When a file is saved (`BufWritePre`) the plugin checks:
  1. Is the filetype one of the supported ones (e.g. `javascript`, `typescript`, `vue`, `svelte`)?
  2. Is there an ESLint or Prettier configuration in the project root?
- Only if the respective configuration is present does it start `eslint_d --fix` resp. `prettier --write`.
- The binaries are resolved automatically:
  - first via `executable(name)` (PATH),
  - then in the Mason bin folder (`stdpath('data') .. '/mason/bin'`) (including the `.cmd` fallback on Windows).
- A Mason installation therefore works out of the box on Linux/macOS/Windows without manual PATH tweaking.

## Toggle / user control
- There is a user command `:ToggleLintFormatOnSave` that switches the automatic behaviour on and off globally.
- `:ToggleLintFormatOnSave` directly changes the global flag `require('lsp.tools.eslint_prettier')._enabled`.
- After toggling you get a short notification showing the current state.

## Examples
- Enabling/disabling:
  - `:ToggleLintFormatOnSave` — toggles globally.
- If you want to change the automatic execution programmatically per session:
  ```lua
  -- disable autorun for current session
  require("lsp.tools.eslint_prettier")._enabled = false

  -- enable autorun for current session
  require("lsp.tools.eslint_prettier")._enabled = true
  ```
