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
