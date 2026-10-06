-- Minimal init of the spec suite. testing.nvim runs it in its own editor and in every child
-- editor before the spec (`minit` of .testing.lua); start the suite with:
--   bash scripts/test.sh
--
-- lib.nvim and ui.nvim (the `deps` of .testing.lua) are put on the runtimepath by testing.nvim
-- with absolute paths; scripts/test.sh resolves them and exits 1 naming every place it looked
-- when one is missing. See TESTS/README.md.

-- `prepend`, not `append`: `-u` does not stop the user's config directory from
-- being on the runtimepath, and while a config carries its own `lua/lsp/**`
-- an appended entry loses -- the suite would silently exercise that instead of
-- this plugin. The same trap the smoke test documents.
vim.opt.rtp:prepend(vim.fn.getcwd())

-- Swap and shada stay off for the whole suite, including every child editor
-- that reuses this file: stale swap files fail suites with E326.
vim.o.swapfile = false
vim.o.shadafile = "NONE"
