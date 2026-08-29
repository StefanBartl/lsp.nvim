---@module 'lsp.languages.webdev.astro'
--- Astro entry point: wires usercmds.lua, autocmds.lua and autotag.lua
--- together, then attaches keymaps.lua and sets buffer-local Astro
--- options (commentstring, 2-space indent) on FileType.

local M = {}

local bo = vim.bo
local Autocmd = require("lib.nvim.bindings.autocmd")

---@return nil
function M.enable()
  -- Cleared augroup, not decoration: `enable()` has no idempotency guard, so
  -- a groupless autocmd here stacks once per config reload. Measured before
  -- the fix: three `enable()` runs left three identical FileType handlers.
  local grp = Autocmd.group("LangAstro", true)

  require("lsp.languages.webdev.astro.usercmds").setup()
  require("lsp.languages.webdev.astro.autocmds").setup()

  -- Auto-Tag: nvim-ts-autotag wenn es da und konfiguriert ist, sonst der
  -- handgeschriebene Fallback -- und die Frage wird erst beim ersten
  -- Astro-Buffer gestellt. Sie zu stellen laedt das Plugin, und von hier aus
  -- zog das die Treesitter-Seite in *jeden* Startup (gemessen: ~25ms der
  -- `lsp`-Phase), fuer einen Filetype, den die meisten Sessions nie sehen.
  -- Die Antwort ist memoisiert; konfiguriert wird nichts (siehe autotag.lua).
  local autotag = require("lsp.servers.webdev.astro.autotag")
  ---@type boolean|nil
  local autotag_ok = nil

  -- FIXED: Don't call vim.lsp.start() - let vim.lsp.enable() handle it
  Autocmd.create("FileType", function(args)
    require("lsp.languages.webdev.astro.keymaps").attach()

    if autotag_ok == nil then
      autotag_ok = autotag.available()
    end

    -- Without nvim-ts-autotag, fall back to the hand-rolled implementation.
    if not autotag_ok then
      autotag.setup_manual_autoclose(args.buf)
    end

    -- Buffer-lokale Settings
    bo[args.buf].commentstring = "{/* %s */}"
    bo[args.buf].shiftwidth = 2
    bo[args.buf].tabstop = 2
    bo[args.buf].expandtab = true

    -- REMOVED: vim.lsp.start() - causes conflict with vim.lsp.enable()
    -- The server auto-attaches because:
    -- 1. vim.lsp.config("astro", {...}) defines the config
    -- 2. vim.lsp.enable("astro") enables auto-attach on FileType
    -- 3. filetypes = { "astro" } triggers attachment
  end, {
    group = grp,
    pattern = "astro",
    desc = "Configure Astro buffer settings",
  })
end

---@type Lsp.Languages.ConfiguredLangs.Webdev.Astro.Module
return M
