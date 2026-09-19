---@module 'lsp.pack.core'
---@brief The plugins the LSP setup does not work properly without.
---@description
--- conform is the formatter engine; without it the formatter falls back to the
--- language server for everything. lazydev and workspace-diagnostics are soft
--- in principle but always wanted in practice, which is why they are in `core`
--- rather than behind their own flag.
---
--- Deliberately absent: mason. Package management is usually already set up in
--- a config (NvChad brings it, for one), and a second manager racing the first
--- into "Package is already installing" is exactly the failure an umbrella
--- should not introduce. `mason.ensure_install` uses whatever mason is there.
---
--- No `config` for conform on purpose: `lsp.formatter.conform.setup()` is the
--- single authoritative `conform.setup()` call and runs from `lsp.setup()`. A
--- second one here would be silently overwritten -- roadmap finding B5.
---
---@see lsp.pack
---@see lsp.config.pack
---@see lsp.integrations.conform

local pack = require("lsp.config.pack")

---@type table[]
return {
  {
    "stevearc/conform.nvim",
    enabled = pack.enabled("conform.nvim", "core"),
    -- Explicit rather than absent: `lsp.setup()`'s bootstrap always calls
    -- `require("conform")` (`lsp.formatter.conform.setup()`,
    -- `lsp.formatter.build()`), so this loads on every startup no matter what
    -- trigger a spec declares -- a `require` from another module is an
    -- accident, not a trigger (LUA-93; the `lsp.integrations.blink` case this
    -- rule names). Declaring `ft`/`cmd`/`event` here would make the spec read
    -- lazy while staying eager underneath, which is worse than no trigger at
    -- all. `lazy = false` says what actually happens.
    lazy = false,
  },

  {
    "folke/lazydev.nvim",
    enabled = pack.enabled("lazydev.nvim", "core"),
    ft = "lua",
    dependencies = {
      { "DrKJeff16/wezterm-types", lazy = true, version = false },
    },
    opts = {
      library = {
        { path = "${3rd}/luv/library", words = { "vim%.uv", "uv", "vim%.loop" } },
        { path = "lazydev.nvim/types" },
        { path = "luvit-meta/library", words = { "vim%.uv", "uv", "vim%.loop" } },
        { path = "plenary.nvim/types", mods = { "plenary" } },
        { path = "telescope.nvim/types", mods = { "telescope" } },
        { "nvim-dap-ui" },
        { path = "wezterm-types", mods = { "wezterm" } },
        { path = "LazyVim", words = { "LazyVim" } },
        { path = "nvim-treesitter", mods = { "vim.treesitter" } },
      },
    },
  },

  {
    "artemave/workspace-diagnostics.nvim",
    enabled = pack.enabled("workspace-diagnostics.nvim", "core"),
    event = "LspAttach",
  },
}
