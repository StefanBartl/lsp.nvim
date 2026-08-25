-- luacheck configuration for lsp.nvim
std = "lua51"
cache = true

-- Neovim injects `vim` as a read-only global.
read_globals = { "vim" }

-- Line length is handled by stylua, not luacheck.
max_line_length = false

ignore = {
  "212/_.*", -- unused argument whose name starts with underscore
  "212/self", -- unused self
  "122", -- setting a read-only field of a global (e.g. vim.*): common in Neovim
}

-- scripts/gen_map.lua runs under `nvim -l`, which passes the CLI arguments as
-- the global `arg` rather than as function parameters.
files["scripts/"] = {
  read_globals = { "vim", "arg" },
}

-- plenary.nvim's busted-style harness (describe/it/...) and luassert's
-- runtime-extended `assert` (assert.has_no.errors, assert.are.same, ...) are
-- only present under TESTS/, so scope them there rather than loosening checks
-- plugin-wide.
--
-- Declared rather than inherited: luacheck ships built-in busted defaults, but
-- they match `**/spec/**`, `**/test/**` and `**/tests/**` -- all lowercase. The
-- suite used to live in `tests/` and picked the std up for free; renaming it to
-- `TESTS/` silently dropped it and turned every spec assertion into an
-- "accessing undefined field of global assert" warning.
files["TESTS/"] = {
  globals = {
    "vim",
    "assert",
    "describe",
    "it",
    "before_each",
    "after_each",
    "pending",
  },
}
