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
    -- Not lazy: the keymap catalogue binds `<cmd>Trouble …<cr>` globally, and
    -- `]w`/`[w` ask an already-open list to move. Loading on `cmd = "Trouble"`
    -- would cover the former and not the latter.
    lazy = false,
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
