---@module 'lsp.languages.webdev.astro'
--- Astro entry point: wires usercmds.lua, autocmds.lua and autotag.lua
--- together, then attaches keymaps.lua and sets buffer-local Astro
--- options (commentstring, 2-space indent) on FileType.

local M = {}

local bo = vim.bo
local Autocmd = require("lib.nvim.autocmd")

---@return nil
function M.enable()
  -- Cleared augroup, not decoration: `enable()` has no idempotency guard, so
  -- a groupless autocmd here stacks once per config reload. Measured before
  -- the fix: three `enable()` runs left three identical FileType handlers.
  local grp = Autocmd.group("LangAstro", true)

  require("lsp.languages.webdev.astro.usercmds").setup()
  require("lsp.languages.webdev.astro.autocmds").setup()

  -- Auto-tag setup (versuche zuerst nvim-ts-autotag)
  local autotag = require("lsp.servers.webdev.astro.autotag")
  local autotag_ok = autotag.setup()

  -- FIXED: Don't call vim.lsp.start() - let vim.lsp.enable() handle it
  Autocmd.create("FileType", function(args)
    require("lsp.languages.webdev.astro.keymaps").attach()

    -- Falls nvim-ts-autotag nicht verfügbar, nutze manuelle Implementation
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
