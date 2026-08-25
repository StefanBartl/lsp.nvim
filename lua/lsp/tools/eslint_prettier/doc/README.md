# lsp.tools.eslint_prettier — README / quickstart

## Goal
This module makes it easy to use `eslint_d` and `prettier` (via Mason) in Neovim.
You get user commands for running them manually, plus an optional autostart on save.

## Prerequisites
- Neovim (0.8+ recommended)
- Mason (for installing the binaries)
  - `:MasonInstall eslint_d prettier`
- The project must have an ESLint and/or Prettier configuration file in the project root:
  - `.eslintrc`, `.eslintrc.json`, `.eslintrc.js`, `package.json` with `eslintConfig`, etc.
  - `.prettierrc`, `prettier.config.js`, `package.json` with `prettier`, etc.

## Example: minimal project configuration

### package.json (excerpt)
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

### .eslintrc.json (alternative)

```json
{
  "env": { "browser": true, "es2021": true },
  "extends": "eslint:recommended",
  "parserOptions": { "ecmaVersion": 2021, "sourceType": "module" },
  "rules": {}
}
```

### .prettierrc (alternative)

```json
{
  "printWidth": 80,
  "singleQuote": true,
  "trailingComma": "es5"
}
```

## Neovim: wiring it in (init.lua)

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

## Usage

* Manually:

  * `:EslintFix` — runs `eslint_d --fix` on the current file (if an ESLint config is present)
  * `:PrettierFormat` — runs `prettier --write` on the current file (if a Prettier config is present)
  * `:LintAndFormat` — runs both in sequence (ESLint → Prettier)
* Automatically on save:
  * Active by default (as long as `enable_on_setup = true`)
  * `:ToggleLintFormatOnSave` — toggles the autorun behaviour globally

## Notes & troubleshooting

* If the tools are not found:

  * Check whether Mason installed them: the `:Mason` UI or `:MasonInstall eslint_d prettier`.
  * The default Mason bin folder is `stdpath('data') .. '/mason/bin'`. The plugin looks for the binaries there automatically (including the `.cmd` suffix on Windows).
  * If Mason lives elsewhere, give explicit paths via `setup{ binaries = {...} }`.
* Performance:

  * Most calls run asynchronously; for very large files it can make sense to disable autorun and format manually.
* Further development:

  * If you want to see ESLint diagnostics in Neovim, use `null-ls` or a native LSP integration.

## Licence / miscellaneous

* The module is meant as a Neovim Lua helper; the implementation can be adapted to project- or team-wide needs.
