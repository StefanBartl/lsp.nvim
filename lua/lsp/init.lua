---@module 'lsp'
---@brief Public entry point for lsp.nvim.
---@description
--- Planned umbrella plugin for the whole LSP ecosystem: the server registry,
--- attach handling, capabilities, formatter and workspace-diagnostics toggles,
--- `:LspDoctor`, and the wiring of the LSP-adjacent third-party plugins.
--- `docs/ROADMAP.md` has the full design and the migration plan.
---
--- What exists today is the scaffold plus the parts that need nothing from the
--- migration: configuration, the `:Lsp` verb, the keymap mechanism, and health
--- checks. It configures no language servers -- the nvim config's own
--- `lua/lsp/**` still does that, and moving it is migration phase 2.
---
--- The module root is `lsp` on purpose (roadmap §5): Neovim occupies only
--- `vim.lsp` and nvim-lspconfig only `lspconfig`, so every existing
--- `require("lsp.…")` path in the config keeps resolving once the code moves.
---
--- lib.nvim is a hard dependency (LUA-01): bare `require`, no fallback.
---
--- Example: >lua
---   require("lsp").setup()
---   require("lsp").setup({
---     keymaps = { preset = "minimal", map = { rename = "<leader>rn" } },
---   })
--- <
---
---@see lsp.config
---@see lsp.bindings
---@see lsp.health

local config = require("lsp.config")

local M = {}

---@type boolean
local _initialized = false

---@type LspNvim.KeymapSpec[]
local _keymaps = {}

---@type boolean
local _usrcmd = false

--- Set up lsp.nvim. Safe to call once; a second call is refused rather than
--- rebinding on top of the first.
---@param opts? LspNvim.Config|table
---@return boolean success
function M.setup(opts)
  if _initialized then
    require("lib.nvim.notify").create("[lsp.nvim]").warn("setup() has already run")
    return false
  end

  local cfg = config.setup(opts)
  _keymaps, _usrcmd = require("lsp.bindings").setup(cfg)
  _initialized = true

  return true
end

--- Snapshot of what the plugin currently is. `:Lsp status` and
--- `:checkhealth lsp` both read this, so neither can drift from the other.
---@return LspNvim.Status
function M.status()
  return {
    initialized = _initialized,
    config = _initialized and config.get() or nil,
    keymaps = _keymaps,
    usrcmd = _usrcmd,
    clients = vim.lsp.get_clients(),
    warnings = config.warnings(),
  }
end

return M
