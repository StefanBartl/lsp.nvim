---@module 'lsp.pack.ui'
---@brief The plugins that put LSP results on screen.
---@description
--- None of these is required for the LSP setup to work; each replaces or
--- augments a piece of Neovim's own presentation. Switch the group off with
--- `vim.g.lsp_nvim.pack.ui = false`, or drop individual ones through
--- `pack.disable`.
---
--- Every `config` here is a single call into the matching adapter. The pack
--- layer holds specs, not logic -- the option tables and the Neovim 0.12
--- Trouble patch live in `lsp.integrations.*`.
---
---@see lsp.pack
---@see lsp.config.pack
---@see lsp.integrations.trouble
---@see lsp.integrations.lspsaga
---@see lsp.integrations.lensline
---@see lsp.integrations.inc_rename

local pack = require("lsp.config.pack")

---@type table[]
return {
  {
    "folke/trouble.nvim",
    enabled = pack.enabled("trouble.nvim", "ui"),
    dependencies = { "nvim-tree/nvim-web-devicons" },
    version = "*",
    -- On demand. The catalogue's `<cmd>Trouble …<cr>` keymaps are covered by
    -- `cmd`, and everything else that reaches Trouble does so through
    -- `pcall(require, "trouble")`, which lazy's require hook turns into a load.
    --
    -- This used to be `lazy = false` for `]w`/`[w`, on the grounds that those
    -- move within an *already-open* list and so would not trigger a `cmd`.
    -- True, but they never needed the plugin loaded to answer correctly:
    -- `bindings.actions`'s `trouble_move` now asks `package.loaded["trouble"]`
    -- first, and if Trouble was never loaded there is no list of its open --
    -- the same notify, without the plugin. Eager, this cost ~79ms plus the
    -- ~71ms of nvim-web-devicons it pulls in, on every start, for a
    -- diagnostics panel most starts never open.
    cmd = "Trouble",
    config = function()
      require("lsp.integrations.trouble").configure()
    end,
  },

  {
    "nvimdev/lspsaga.nvim",
    enabled = pack.enabled("lspsaga.nvim", "ui"),
    event = "LspAttach",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      require("lsp.integrations.lspsaga").configure()
    end,
  },

  {
    "oribarilan/lensline.nvim",
    enabled = pack.enabled("lensline.nvim", "ui"),
    branch = "release/2.x",
    event = "LspAttach",
    config = function()
      require("lsp.integrations.lensline").configure()
    end,
  },

  {
    "smjonas/inc-rename.nvim",
    enabled = pack.enabled("inc-rename.nvim", "ui"),
    cmd = "IncRename",
    config = function()
      require("lsp.integrations.inc_rename").configure()
    end,
  },
}
