---@module 'lsp.config.KEYMAPS'
---@brief Declarative catalogue of every keymap lsp.nvim can bind.
---@description
--- Keymaps are data. `bindings/keymaps.lua` iterates `entries`, applies the
--- user's `keymaps.map` overrides and registers what is left; `docs/BINDINGS.md`
--- is generated from the same table rather than kept in sync by hand. Adding a
--- mapping means adding an entry, never touching the binding site.
---
--- Presets are name lists over one entry table, not three copies of it -- a
--- changed description or lhs would otherwise have to be corrected in every
--- preset that mentions it.
---
--- These keys came from five places in the nvim config
--- (`bindings/mappings/lsp.lua`, `bindings/mappings/trouble.lua`, the LSP lines
--- of `bindings/mappings/fzf.lua`, `config/inc_rename/`, and this plugin's own
--- `diagnostics/keymaps.lua`). Consolidating them is what removes the cases
--- where two modules owned the same key without knowing about each other.
---
--- Behaviour lives in `bindings/actions.lua`; an entry names an action, it does
--- not implement one. Command-string entries (`<cmd>Trouble …<cr>`,
--- `:FzfLua …<cr>`) are deliberately left as strings: they stay inert until
--- pressed, so the plugin manager can keep loading those plugins on demand.
---
---@see lsp.bindings.keymaps
---@see lsp.bindings.actions
---@see lsp.config.DEFAULTS

local actions = require("lsp.bindings.actions")

---@type table<string, LspNvim.KeymapSpec>
local entries = {
  -- ------------------------------------------------------------ navigation
  -- The `ls*` family is prefixless and three characters long. It sits beside
  -- Neovim 0.11's own `grr`/`gri`/`grn`/`grt`/`gO` rather than replacing them:
  -- those are buffer-local on LspAttach, these are global, so both work. The
  -- price is that every Normal-mode `l` waits out 'timeoutlen' to see whether
  -- an `s` follows -- deliberate, and documented in docs/BINDINGS.md.
  goto_definition = {
    lhs = "lsd",
    mode = "n",
    rhs = vim.lsp.buf.definition,
    desc = "Go to definition",
  },
  goto_declaration = {
    lhs = "lsD",
    mode = "n",
    rhs = vim.lsp.buf.declaration,
    desc = "Go to declaration",
  },
  goto_type_definition = {
    lhs = "lst",
    mode = "n",
    rhs = vim.lsp.buf.type_definition,
    desc = "Go to type definition",
  },
  goto_type_definition_gr = {
    lhs = "grt",
    mode = "n",
    rhs = vim.lsp.buf.type_definition,
    desc = "Go to type definition (g-prefix variant)",
  },
  goto_references = {
    lhs = "lsr",
    mode = "n",
    rhs = vim.lsp.buf.references,
    desc = "List references",
  },
  goto_implementations = {
    lhs = "lsi",
    mode = "n",
    rhs = vim.lsp.buf.implementation,
    desc = "List implementations",
  },
  document_symbols = {
    lhs = "lss",
    mode = "n",
    rhs = vim.lsp.buf.document_symbol,
    desc = "Document symbols",
  },
  code_action = {
    lhs = "lsa",
    mode = "n",
    rhs = vim.lsp.buf.code_action,
    desc = "Code action",
  },
  signature_help = {
    lhs = "<M-s>",
    mode = "i",
    rhs = vim.lsp.buf.signature_help,
    desc = "Signature help",
  },

  -- ------------------------------------------------------------ rename
  -- One action, two keys. `grn` and `<leader>rn` used to run *different*
  -- renames (native vs. :IncRename) -- roadmap finding B9. Both now reach
  -- `actions.rename`, which picks the backend from `rename.provider`, so the
  -- muscle memory for either key survives without the two drifting apart.
  rename = {
    lhs = "grn",
    mode = "n",
    rhs = actions.rename,
    desc = "Rename symbol",
  },
  rename_leader = {
    lhs = "<leader>rn",
    mode = "n",
    rhs = actions.rename,
    desc = "Rename symbol (leader variant)",
  },

  -- ------------------------------------------------------------ formatter
  format_toggle = {
    lhs = "<leader>tft",
    mode = "n",
    rhs = actions.format_toggle,
    desc = "Toggle format-on-save",
  },
  format_buffer = {
    lhs = "<leader>ft",
    mode = "n",
    rhs = actions.format_buffer,
    desc = "Format buffer once",
  },
  format_lsp = {
    lhs = "<leader>fl",
    mode = "n",
    rhs = actions.format_lsp,
    desc = "Format via the language server directly",
  },

  -- ------------------------------------------------------------ inlay hints
  -- `<leader>th` is the global switch; the per-filetype one sits on the
  -- shifted key rather than a third prefix, because "the same toggle, narrower
  -- scope" is exactly what a shift usually means here.
  hints_toggle = {
    lhs = "<leader>th",
    mode = "n",
    rhs = actions.hints_toggle,
    desc = "Toggle inlay hints (global)",
  },
  hints_toggle_filetype = {
    lhs = "<leader>tH",
    mode = "n",
    rhs = actions.hints_toggle_filetype,
    desc = "Toggle inlay hints for this filetype",
  },

  -- ------------------------------------------------------------ diagnostics
  diag_to_qflist = {
    lhs = "<leader>wq",
    mode = "n",
    rhs = actions.diag_to_qflist,
    desc = "Diagnostics -> quickfix (workspace)",
  },
  diag_to_loclist = {
    lhs = "<leader>lq",
    mode = "n",
    rhs = actions.diag_to_loclist,
    desc = "Diagnostics -> loclist (buffer)",
  },
  -- Neovim's own `vim.diagnostic.setqflist`, kept because it populates the
  -- list differently from `diag_to_qflist` (no open, no workspace walk).
  diag_setqflist = {
    lhs = "<leader>tq",
    mode = "n",
    rhs = vim.diagnostic.setqflist,
    desc = "Diagnostics -> quickfix (plain)",
  },
  diag_next = {
    lhs = "]d",
    mode = { "n", "x", "o" },
    rhs = actions.diag_next,
    desc = "Next diagnostic (buffer)",
  },
  diag_prev = {
    lhs = "[d",
    mode = { "n", "x", "o" },
    rhs = actions.diag_prev,
    desc = "Prev diagnostic (buffer)",
  },
  qf_next = {
    lhs = "]q",
    mode = "n",
    rhs = actions.qf_next,
    desc = "Next quickfix entry",
  },
  qf_prev = {
    lhs = "[q",
    mode = "n",
    rhs = actions.qf_prev,
    desc = "Prev quickfix entry",
  },
  loc_next = {
    lhs = "]l",
    mode = "n",
    rhs = actions.loc_next,
    desc = "Next location-list entry",
  },
  loc_prev = {
    lhs = "[l",
    mode = "n",
    rhs = actions.loc_prev,
    desc = "Prev location-list entry",
  },

  -- ------------------------------------------------------------ trouble
  trouble_toggle = {
    lhs = "<leader>xt",
    mode = "n",
    rhs = "<cmd>Trouble diagnostics toggle<cr>",
    desc = "Trouble: toggle diagnostics",
    requires = "trouble",
  },
  trouble_all = {
    lhs = "<leader>xx",
    mode = "n",
    rhs = "<cmd>Trouble diagnostics<cr>",
    desc = "Trouble: all diagnostics",
    requires = "trouble",
  },
  trouble_workspace = {
    lhs = "<leader>xw",
    mode = "n",
    rhs = "<cmd>Trouble diagnostics filter.buf=nil<cr>",
    desc = "Trouble: workspace diagnostics",
    requires = "trouble",
  },
  trouble_buffer = {
    lhs = "<leader>xd",
    mode = "n",
    rhs = "<cmd>Trouble diagnostics filter.buf=0<cr>",
    desc = "Trouble: buffer diagnostics",
    requires = "trouble",
  },
  trouble_references = {
    lhs = "<leader>xlr",
    mode = "n",
    rhs = "<cmd>Trouble lsp_references<cr>",
    desc = "Trouble: references",
    requires = "trouble",
  },
  trouble_definitions = {
    lhs = "<leader>xld",
    mode = "n",
    rhs = "<cmd>Trouble lsp_definitions<cr>",
    desc = "Trouble: definitions",
    requires = "trouble",
  },
  trouble_type_definitions = {
    lhs = "<leader>xlt",
    mode = "n",
    rhs = "<cmd>Trouble lsp_type_definitions<cr>",
    desc = "Trouble: type definitions",
    requires = "trouble",
  },
  trouble_implementations = {
    lhs = "<leader>xli",
    mode = "n",
    rhs = "<cmd>Trouble lsp_implementations<cr>",
    desc = "Trouble: implementations",
    requires = "trouble",
  },
  trouble_symbols = {
    lhs = "<leader>xls",
    mode = "n",
    rhs = "<cmd>Trouble lsp_document_symbols<cr>",
    desc = "Trouble: document symbols",
    requires = "trouble",
  },
  trouble_loclist = {
    lhs = "<leader>xl",
    mode = "n",
    rhs = "<cmd>Trouble loclist<cr>",
    desc = "Trouble: location list",
    requires = "trouble",
  },
  trouble_qflist = {
    lhs = "<leader>xq",
    mode = "n",
    rhs = "<cmd>Trouble qflist<cr>",
    desc = "Trouble: quickfix list",
    requires = "trouble",
  },
  trouble_diag_next = {
    lhs = "]w",
    mode = "n",
    rhs = actions.trouble_diag_next,
    desc = "Next entry in the open Trouble diagnostics list",
    requires = "trouble",
  },
  trouble_diag_prev = {
    lhs = "[w",
    mode = "n",
    rhs = actions.trouble_diag_prev,
    desc = "Prev entry in the open Trouble diagnostics list",
    requires = "trouble",
  },

  -- ------------------------------------------------------------ picker
  -- Hardwired to fzf-lua, exactly as the config had them. The backend
  -- abstraction (fzf-lua | telescope | snacks | pickers.nvim) is roadmap
  -- section 7's `integrations/picker`, i.e. phase 4 -- pretending to have it
  -- now would mean an indirection with one implementation behind it.
  picker_document_symbols = {
    lhs = "<leader>dos",
    mode = "n",
    rhs = "<cmd>FzfLua lsp_document_symbols<cr>",
    desc = "Picker: document symbols",
    requires = "fzf-lua",
  },
  picker_workspace_symbols = {
    lhs = "<leader>wos",
    mode = "n",
    rhs = "<cmd>FzfLua lsp_live_workspace_symbols<cr>",
    desc = "Picker: workspace symbols (live)",
    requires = "fzf-lua",
  },
  picker_document_diagnostics = {
    lhs = "<leader>do",
    mode = "n",
    rhs = "<cmd>FzfLua diagnostics_document<cr>",
    desc = "Picker: document diagnostics",
    requires = "fzf-lua",
  },
  picker_workspace_diagnostics = {
    lhs = "<leader>wo",
    mode = "n",
    rhs = "<cmd>FzfLua diagnostics_workspace<cr>",
    desc = "Picker: workspace diagnostics",
    requires = "fzf-lua",
  },

  -- ------------------------------------------------------------ misc
  root_scope_pick = {
    lhs = "<leader>lsp",
    mode = "n",
    rhs = actions.root_scope_pick,
    desc = "Pick root scope (cwd / git root / file path)",
  },
  -- Only `add` gets a key. `remove` and `list` are rare enough to type, and a
  -- second key next to this one would be one keystroke away from removing the
  -- folder you meant to add.
  workspace_folder_add = {
    lhs = "<leader>lsw",
    mode = "n",
    rhs = actions.root_workspace_add,
    desc = "Add a workspace folder (multi-root / monorepo)",
  },
  marksman_hints = {
    lhs = "<leader>lb",
    mode = "n",
    rhs = actions.marksman_hints_toggle,
    desc = "Toggle Marksman markdown hints",
  },
}

--- Which entries each preset binds.
---
--- `minimal` drops everything Neovim 0.11 already provides on its own
--- (`grn`, `grt`, `gO`, `grr`, `gri`, `]d`/`[d`) plus the prefixless `ls*`
--- family, and keeps what has no native equivalent.
---@type table<LspNvim.KeymapPreset, string[]>
local presets = {
  default = vim.tbl_keys(entries),
  minimal = {
    "signature_help",
    "rename_leader",
    "format_toggle",
    "format_buffer",
    "hints_toggle",
    "hints_toggle_filetype",
    "format_lsp",
    "diag_to_qflist",
    "diag_to_loclist",
    "diag_setqflist",
    "qf_next",
    "qf_prev",
    "loc_next",
    "loc_prev",
    "trouble_toggle",
    "trouble_all",
    "trouble_workspace",
    "trouble_buffer",
    "trouble_loclist",
    "trouble_qflist",
    "trouble_diag_next",
    "trouble_diag_prev",
    "picker_document_symbols",
    "picker_workspace_symbols",
    "picker_document_diagnostics",
    "picker_workspace_diagnostics",
    "root_scope_pick",
    "workspace_folder_add",
    "marksman_hints",
  },
  none = {},
}

table.sort(presets.default)

--- which-key group labels, curated rather than derived from the bound
--- left-hand sides.
---
--- Deriving them would label every `<leader>x` prefix this plugin touches, and
--- most of them are shared: `<leader>f` is the config's find/file prefix,
--- `<leader>d`, `<leader>w`, `<leader>l` and `<leader>t` likewise. Calling
--- those "LSP" would be wrong. `<leader>x` is the one prefix that is entirely
--- ours.
---@type table<string, string>
local groups = {
  ["<leader>x"] = "Trouble / LSP lists",
  ["<leader>xl"] = "Trouble LSP views",
}

return {
  entries = entries,
  presets = presets,
  groups = groups,
}
