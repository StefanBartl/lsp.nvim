---@module 'lsp.config.DEFAULTS'
---@brief Immutable default configuration for lsp.nvim.
---@description
--- Single source of truth for every user-settable value. `config/init.lua`
--- deep-merges the user's options over a copy of this table; the table itself
--- is never mutated at runtime.
---
--- Every key here is read by code. Options
--- that nothing consumes yet (`completion`, `integrations`) are deliberately
--- absent -- a default nothing reads is a promise the plugin does not keep.
--- They arrive with the layer that honors them.
---
---@see lsp.config
---@see lsp.config.KEYMAPS

---@type LspNvim.Config
local DEFAULTS = {
  -- Which servers are set up and enabled. Each name resolves to
  -- `lsp.servers.<name>`, with `lsp.servers.webdev.<name>` tried as a fallback
  -- for dotless names. This used to be a hardcoded ACTIVE list inside
  -- `core/registry.lua`, where turning a server on or off meant editing the
  -- plugin (roadmap finding B7).
  servers = {
    "bashls",
    "lua_ls",
    "gopls",
    "marksman",
    -- "emmet_ls",

    -- Web development
    "html",
    "ts_ls",
    "tailwindcss",
    -- "astro",
    -- "htmx",
    -- "wasm_language_tools",

    -- "clangd",
    "csharp",
    -- "zig",

    -- Mobile development
    -- "jdtls",                   -- Java (Android)
    -- "kotlin_language_server",  -- Kotlin (Android)
    -- "dartls",                  -- Dart/Flutter
  },

  -- Passed to `vim.diagnostic.config()` after the servers are enabled.
  diagnostics = {
    update_in_insert = false,
    severity_sort = true,
    virtual_text = { spacing = 2, prefix = "●" },
    float = { border = "rounded", source = "if_many" },
    -- Where "]d"/"[d" send you. "trouble" and "auto" behave identically at
    -- runtime (see lsp.bindings.actions.diagnostics_use_trouble); "auto" only
    -- exists so a config can say "whichever is available" without naming
    -- Trouble explicitly. Not passed to vim.diagnostic.config() -- lsp.init
    -- strips this key first, since diagnostic.config() doesn't know it.
    ---@type "auto"|"native"|"trouble"
    ui = "auto",
  },

  formatter = {
    -- Off at startup; the runtime toggle (`:LspFormatToggle`, `<leader>tft`)
    -- owns it from there.
    on_save = false,
    timeout_ms = 1500,
  },

  -- Handed to `core/attach.lua`'s builder.
  attach = {
    -- Startup default only -- `lsp.core.workspace_diagnostics` overrides it at
    -- any time. On by default because that module measures workspace size
    -- itself and refuses to populate above its `max_files` gate; the old
    -- machine-role proxy for "big repo" was a worse predictor than the
    -- measurement.
    use_workspace_diagnostics = true,
    use_lazydev = true,
  },

  mason = {
    -- Off by default: installing packages is a side effect a plugin should not
    -- perform unless asked.
    ensure_install = false,
    overrides = {
      lsp = {
        ["java-language-server"] = false,
        ["csharp-language-server"] = false,
      },
      dap = {
        ["node-debug2-adapter"] = false,
      },
      linters = {
        ["eslint_d"] = true,
      },
      formatters = {
        ["prettier"] = true,
      },
    },
  },

  lspdoctor = {
    use_notify = false,
    list_limit = 8,
    -- `null-ls` is inert here: it is not installed. Kept because which
    -- formatter wins a conflict is a decision, not a leftover.
    formatter_priority = { "null-ls", "eslint", "lua_ls" },
    semantic_tokens_timeout = 300,
    scratch_filetype = "markdown",
    auto_open_scratch = true,
    scratch_threshold = 20,
  },

  tools = {
    eslint_prettier = {
      enable = true,
      filetypes = { "javascript", "typescript", "javascriptreact", "typescriptreact" },
    },
    lsp_signature = { enable = true },
    ts_type_lookup = { enable = true },
    deprecated_help = { enable = true },
  },

  -- Filetype-specific quality-of-life setup under `lsp/languages/**`, applied
  -- before the servers are registered.
  languages = { enable = true },

  --- Hand-written completion sources.
  ---
  --- `personal_names.labels` is a reader, not a list: the plugin names it
  --- completes are the *host config's* data, so the config hands them over
  --- rather than this plugin reaching into `plugins.personal.list`. Without a
  --- reader the source falls back to `extra.lua` alone.
  ---
  --- Read at setup time regardless of which completion engine is active --
  --- that is the whole point. Wiring it from nvim-cmp's `opts` (as the config
  --- did until 2026-08-23) meant switching to blink silently dropped it.
  completion = {
    personal_names = {
      enable = true,
      ---@type (fun(): (string|{name: string})[])|nil
      labels = nil,
    },
  },

  rename = {
    -- "auto" prefers inc-rename when it is installed and falls back to
    -- `vim.lsp.buf.rename`; "inc_rename" and "native" pin one. Both the `grn`
    -- and `<leader>rn` entries go through this, so the two keys can no longer
    -- do different things (roadmap finding B9).
    provider = "auto",
  },

  keymaps = {
    enable = true,
    preset = "default",
    -- Per-action overrides, e.g. `map = { goto_definition = "gd", rename = false }`.
    map = {},
  },

  usrcmds = {
    enable = true,
    -- Keep the ~25 flat `:Lsp*`/`:Diag*` commands as aliases onto the `:Lsp`
    -- routes. On by default: muscle memory beats tidiness and an alias costs a
    -- line. Off gives you `:Lsp` alone.
    legacy_aliases = true,
  },

  which_key = {
    enable = true,
  },

  -- Right-click context menu (nvzone/menu, soft dependency; entries from
  -- lsp.integrations.menu, mirroring the resolved keymap catalogue --
  -- see keymaps.preset/keymaps.map). Off automatically when nvzone/menu
  -- isn't installed -- this only gates whether M.items()/M.submenu()
  -- return entries at all.
  menu = {
    enable = true,
  },
}

return DEFAULTS
