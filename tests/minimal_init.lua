-- Minimal init for running the plenary.nvim test suite headlessly:
--   nvim --headless --noplugin -u tests/minimal_init.lua \
--     -c "PlenaryBustedDirectory tests/lsp { minimal_init = 'tests/minimal_init.lua' }"
--
-- plenary.nvim and lib.nvim are resolved via env vars rather than hardcoded
-- paths, so this works locally (wherever they live for your normal config) and
-- in CI (checked out into a scratch dir by the workflow). See tests/README.md.

-- `prepend`, not `append`: `-u` does not stop the user's config directory from
-- being on the runtimepath, and while a config carries its own `lua/lsp/**`
-- an appended entry loses -- the suite would silently exercise that instead of
-- this plugin. The same trap the smoke test documents.
vim.opt.rtp:prepend(vim.fn.getcwd())

---@param var string
local function prepend_env(var)
  local path = os.getenv(var)
  if path and path ~= "" then
    vim.opt.rtp:prepend(path)
  end
end

prepend_env("PLENARY_PATH")
prepend_env("LIB_NVIM_PATH")

vim.cmd("runtime plugin/plenary.vim")
