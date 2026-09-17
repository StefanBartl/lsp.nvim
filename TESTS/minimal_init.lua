-- Minimal init for running the plenary.nvim test suite headlessly:
--   nvim --headless --noplugin -u TESTS/minimal_init.lua \
--     -c "PlenaryBustedDirectory TESTS/lsp { minimal_init = 'TESTS/minimal_init.lua' }"
--
-- plenary.nvim and lib.nvim are resolved via env vars rather than hardcoded
-- paths, so this works locally (wherever they live for your normal config) and
-- in CI (checked out into a scratch dir by the workflow). See TESTS/README.md.

-- `prepend`, not `append`: `-u` does not stop the user's config directory from
-- being on the runtimepath, and while a config carries its own `lua/lsp/**`
-- an appended entry loses -- the suite would silently exercise that instead of
-- this plugin. The same trap the smoke test documents.
vim.opt.rtp:prepend(vim.fn.getcwd())

---@param var string
local function prepend_env(var)
  local path = os.getenv(var)
  if path and path ~= "" then
    -- Absolute, not the literal env value: CI's LIB_NVIM_PATH/UI_NVIM_PATH
    -- are relative (".deps/lib.nvim"), and any spec that chdir()s to a
    -- fixture directory -- config_layers_spec.lua and languages_spec.lua
    -- both do, to test cwd-relative discovery -- would otherwise have this
    -- rtp entry silently resolve against the *new* cwd on the next
    -- require() of something not already cached in package.loaded, failing
    -- with "module not found" and no file candidate anywhere near the real
    -- checkout.
    vim.opt.rtp:prepend(vim.fn.fnamemodify(path, ":p"))
  end
end

prepend_env("PLENARY_PATH")
prepend_env("LIB_NVIM_PATH")
-- ui.kit/ui.contextmenu moved out of lib.nvim.ui.kit/lib.nvim.contextmenu
-- in the 2026-09 migration -- needed by TESTS/lsp/pack_spec.lua and
-- anything touching lspdoctor/the root/workspace pickers.
prepend_env("UI_NVIM_PATH")

vim.cmd("runtime plugin/plenary.vim")
