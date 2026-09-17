# lsp.tools.eslint_prettier — README / quickstart

## Goal
This module makes it easy to use `eslint_d` and `prettier` (via Mason) in Neovim.
You get user commands for running them manually, plus an optional autostart on save.

## Prerequisites
- Neovim 0.11 or newer, as for the rest of `lsp.nvim`
- Mason (for installing the binaries)
  - `:MasonInstall eslint_d prettier`
- The project must have an ESLint and/or Prettier configuration file in the project root:
  - ESLint **flat config** — `eslint.config.js`, `.mjs`, `.cjs`, `.ts` — which has been the default since ESLint v9 and is the only format v10 reads. Looked for first.
  - or legacy `.eslintrc`, `.eslintrc.js`, `.eslintrc.cjs`, `.eslintrc.json`, `.eslintrc.yml`, `.eslintrc.yaml`
  - or `package.json` with a top-level `eslintConfig` key
  - `.prettierrc`, `.prettierrc.js`, `.prettierrc.cjs`, `.prettierrc.json`, `.prettierrc.yml`, `.prettierrc.yaml`, `prettier.config.js`
  - or `package.json` with a top-level `prettier` key

`package.json` counts only when it *declares* the tool's own key. The file is
decoded rather than searched, so `"prettier": "^3.3.3"` under `devDependencies`
does not make a project a Prettier project, and an `eslintConfig` key does not
answer for Prettier.

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
```

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

`filetypes` **replaces** the default rather than adding to it; the default is
`{ "javascript", "javascriptreact", "typescript", "typescriptreact", "vue",
"svelte" }`, so the list above drops Vue and Svelte. `enable_on_setup`
defaults to `true`.

## Usage

* Manually:

  * `:EslintFix` — runs `eslint_d --fix` on the current file (if an ESLint config is present)
  * `:PrettierFormat` — runs `prettier --write` on the current file (if a Prettier config is present)
  * `:LintAndFormat` — runs both in sequence (ESLint → Prettier)
* Automatically on save:
  * Active by default (as long as `enable_on_setup = true`)
  * On `BufWritePost`, i.e. **after** Neovim has written the file — not before.
    Both tools read and rewrite the file on disk, and starting them ahead of
    Neovim's own write means editor and child hold the same path open at once,
    which on Windows is a sharing violation rather than a race someone wins.
  * Chained, not concurrent: `eslint_d --fix` first, `prettier --write` only
    once it has exited. Started together the slower one's write is what
    survives and the other's is lost.
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
