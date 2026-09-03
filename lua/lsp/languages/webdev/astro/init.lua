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

  -- Auto-tag: nvim-ts-autotag when it is installed and configured, otherwise
  -- the hand-rolled fallback -- and the question is asked at the first Astro
  -- buffer, not here. Asking it loads the plugin, and from this point that
  -- pulled the treesitter side into *every* startup (measured: ~25ms of the
  -- `lsp` phase) for a filetype most sessions never see. The answer is
  -- memoized, and nothing is configured (see autotag.lua).
  local autotag = require("lsp.servers.webdev.astro.autotag")
  ---@type boolean|nil
  local autotag_ok = nil

  -- No `vim.lsp.start()` here: `vim.lsp.config("astro", …)` plus
  -- `vim.lsp.enable("astro")` already attach the server on this FileType, and
  -- starting it a second time conflicts with that.
  Autocmd.create("FileType", function(args)
    require("lsp.languages.webdev.astro.keymaps").attach()

    if autotag_ok == nil then
      autotag_ok = autotag.available()
    end

    -- Without nvim-ts-autotag, fall back to the hand-rolled implementation.
    if not autotag_ok then
      autotag.setup_manual_autoclose(args.buf)
    end

    -- Buffer-local settings
    bo[args.buf].commentstring = "{/* %s */}"
    bo[args.buf].shiftwidth = 2
    bo[args.buf].tabstop = 2
    bo[args.buf].expandtab = true
  end, {
    group = grp,
    pattern = "astro",
    desc = "Configure Astro buffer settings",
  })
end

---@type Lsp.Languages.ConfiguredLangs.Webdev.Astro.Module
return M
