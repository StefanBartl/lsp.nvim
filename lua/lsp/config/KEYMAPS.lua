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
  -- Neovim's own `grr`/`gri`/`grn`/`grt`/`gO` because it uses different keys --
  -- not, as this comment claimed until now, because Neovim's are buffer-local
  -- and therefore out of the way. They are not buffer-local.
  -- `$VIMRUNTIME/lua/vim/_core/defaults.lua` sets all six at startup with the
  -- note "mapped unconditionally to avoid different behavior depending on
  -- whether an LSP client is attached", and a `--headless --noplugin` session
  -- with no client at all reports `maparg("grn", "n", false, true).buffer == 0`
  -- for every one of them.
  --
  -- Which matters for the two entries below that DO claim those left-hand
  -- sides: being global, `rename` (`grn`) and `goto_type_definition_gr` (`grt`)
  -- replace Neovim's outright the moment the binder runs -- measured, after
  -- `bindings.keymaps.setup()` under the `default` preset `maparg("grn").desc`
  -- reads "LSP: Rename symbol" where it read "vim.lsp.buf.rename()" before.
  -- That is what roadmap finding B9 needs; it just does not need an LspAttach
  -- hook to get it.
  --
  -- The family's own price is that every Normal-mode `l` waits out
  -- 'timeoutlen' to see whether an `s` follows -- deliberate, and documented in
  -- docs/BINDINGS.md.
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
  -- Through `actions.code_action`, which opens fzf-lua's picker (a diff preview
  -- of the edit before it is applied) when fzf-lua is installed and falls back
  -- to `vim.lsp.buf.code_action` when it is not -- `code_actions.picker` pins
  -- either.
  --
  -- Normal mode only. This was `{ "n", "x" }` for one commit, and that made
  -- every `l` in Visual mode wait out 'timeoutlen' -- measured with
  -- `mapcheck("l", "x")`, which answered with this mapping. The Normal-mode
  -- wait of the `ls*` family is a documented price; Visual mode had none, and
  -- `vl` / `vjl` are how a selection gets extended. The range case is
  -- `code_action_range` below, on a key that is already a prefix there.
  code_action = {
    lhs = "lsa",
    mode = "n",
    rhs = actions.code_action,
    desc = "Code action (with diff preview)",
  },
  -- The same picker for a selection. `gra` is Neovim's own Visual-mode code
  -- action, so `g` + `r` is already a pending prefix in `x` mode and this adds
  -- no wait to any key -- the catalogue replaces the native mapping the way
  -- `grn` and `grt` replace theirs. Normal mode keeps Neovim's own `gra`.
  code_action_range = {
    lhs = "gra",
    mode = "x",
    rhs = actions.code_action,
    desc = "Code action for the selection (with diff preview)",
  },
  -- The floating, editable peek (`lsp.core.peek`): look at a definition
  -- without leaving the code. `lsd`/`lst` jump and lose the place, `lsr`/`lsi`
  -- list; this is what sits between. lspsaga's `peek_definition` /
  -- `peek_type_definition`, and the same mnemonic: `p` for peek, the
  -- capital for the type -- the shifted `lsD` and `lsC` follow the same
  -- "sibling on shift" pattern.
  peek_definition = {
    lhs = "lsp",
    mode = "n",
    rhs = actions.peek_definition,
    desc = "Peek definition (floating, editable)",
  },
  peek_type_definition = {
    lhs = "lsT",
    mode = "n",
    rhs = actions.peek_type_definition,
    desc = "Peek type definition (floating, editable)",
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

  -- --------------------------------------------------- code-action indicator
  -- Same global/shifted-for-filetype pairing as the inlay-hint toggles above,
  -- for the same reason: it is the same kind of switch.
  --
  -- `tb` (bulb), not the `tl` this used to be: `<leader>tl` is NvChad's
  -- "move tab left", the mirror of `<leader>tr`. That pair is positional and
  -- cannot move; a mnemonic for "lightbulb" can. Which of the two survived
  -- depended on load order, so one of them was always silently broken.
  lightbulb_toggle = {
    lhs = "<leader>tb",
    mode = "n",
    rhs = actions.lightbulb_toggle,
    desc = "Toggle the code-action indicator (global)",
  },
  lightbulb_toggle_filetype = {
    lhs = "<leader>tB",
    mode = "n",
    rhs = actions.lightbulb_toggle_filetype,
    desc = "Toggle the code-action indicator for this filetype",
  },

  -- ------------------------------------------------------- winbar breadcrumb
  -- `tW`, not `tw`: `<leader>tw` is gitsigns' word-diff toggle, and the shifted
  -- key is free. The breadcrumb is a per-window bar, so this is the global
  -- switch; the per-filetype one is `:Lsp winbar toggle <filetype>`.
  winbar_toggle = {
    lhs = "<leader>tW",
    mode = "n",
    rhs = actions.winbar_toggle,
    desc = "Toggle the LSP breadcrumb in the winbar (global)",
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
  -- The quick fix for the diagnostic on this line: `]d` jumps and shows it,
  -- this applies the fix. In `<leader>x`, the namespace this plugin owns
  -- outright (see `groups` below).
  diag_code_action = {
    lhs = "<leader>xa",
    mode = "n",
    rhs = actions.diag_code_action,
    desc = "Quick fix for the diagnostic on this line",
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
  -- The outline sidebar: Trouble's `symbols` mode is already configured as a
  -- right-hand panel that follows the cursor, unlike `trouble_symbols` above,
  -- which is the plain list. lspsaga's `outline`.
  trouble_outline = {
    lhs = "<leader>xo",
    mode = "n",
    rhs = "<cmd>Trouble symbols toggle<cr>",
    desc = "Trouble: outline sidebar (document symbols)",
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

  -- Call hierarchy, through the same picker. Neovim ships
  -- `vim.lsp.buf.incoming_calls`, but it dumps into the quickfix list, which
  -- loses the tree the protocol actually returns; fzf-lua's providers keep it
  -- browsable. `lsc`/`lsC` follow `lsd`/`lsD`: the lowercase key is the
  -- direction one asks for far more often ("who calls this"), the shifted one
  -- is its sibling.
  picker_incoming_calls = {
    lhs = "lsc",
    mode = "n",
    rhs = "<cmd>FzfLua lsp_incoming_calls<cr>",
    desc = "Picker: incoming calls (who calls this)",
    requires = "fzf-lua",
  },
  picker_outgoing_calls = {
    lhs = "lsC",
    mode = "n",
    rhs = "<cmd>FzfLua lsp_outgoing_calls<cr>",
    desc = "Picker: outgoing calls (what this calls)",
    requires = "fzf-lua",
  },

  -- Everything that uses, implements or defines the symbol, in one list with
  -- a preview (lspsaga's `finder`). `f` for finder.
  picker_finder = {
    lhs = "lsf",
    mode = "n",
    rhs = actions.finder,
    desc = "Picker: finder (references + implementations + definitions)",
    requires = "fzf-lua",
  },
  -- Type hierarchy. Few servers answer it (clangd, gopls, jdtls, measured;
  -- dartls unconfirmed); the action
  -- says so instead of waiting for "No results". `h` for hierarchy: lower case
  -- is the direction asked for more, up to the supertypes.
  picker_type_super = {
    lhs = "lsh",
    mode = "n",
    rhs = actions.type_super,
    desc = "Picker: supertypes of this type",
  },
  picker_type_sub = {
    lhs = "lsH",
    mode = "n",
    rhs = actions.type_sub,
    desc = "Picker: subtypes of this type",
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
--- `minimal` keeps the entries with no plausible native equivalent. It drops
--- `rename` (`grn`), `goto_type_definition_gr` (`grt`) and `diag_next`/
--- `diag_prev` (`]d`/`[d`) -- the catalogue keys Neovim already binds to the
--- same action -- plus seven of the nine prefixless `ls*` keys. (`gO`, `grr`
--- and `gri` were named here as dropped too, until someone checked: the
--- catalogue has never bound any of the three, so there was nothing to drop.)
---
--- Two exceptions, named because "no plausible native equivalent" is not what
--- a reader would guess of either. Both were measured against
--- `nvim_get_keymap("n")` in a `--noplugin` session rather than assumed:
---
--- * `]q`/`[q`/`]l`/`[l` ARE Neovim 0.11 defaults (`:cnext`, `:cprevious`,
---   `:lnext`, `:lprevious`), and `minimal` keeps them anyway. The catalogue's
---   versions swallow E553 at the end of a list, which was the whole of roadmap
---   finding B3 -- and a key one holds down is exactly where an error beats a
---   stop.
--- * `picker_incoming_calls` (`lsc`) and `picker_outgoing_calls` (`lsC`) are
---   `ls*` keys and `minimal` keeps them too: call hierarchy is the one thing
---   in the family Neovim has no default for. The cost is the one thing
---   `minimal` does NOT buy back -- two `ls*` maps stay live under it against
---   nine under `default`, and one is enough to make every Normal-mode `l` wait
---   out 'timeoutlen'. If that wait is the reason for picking the preset,
---   `keymaps.map = { picker_incoming_calls = false, picker_outgoing_calls =
---   false }` is what finishes the job.
---
--- The entries added with the lspsaga replacement (`peek_*`, `picker_finder`,
--- `picker_type_*` -- all `ls*` keys -- plus `trouble_outline`, `winbar_toggle`
--- and `diag_code_action`) are deliberately not in `minimal`. The `ls*` ones
--- would each cost the wait this preset exists to avoid; the three others are
--- leader keys and could be, but a preset that keeps growing stops being the
--- short list it is for.
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
    "lightbulb_toggle",
    "lightbulb_toggle_filetype",
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
    "picker_incoming_calls",
    "picker_outgoing_calls",
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
