---@module 'lsp.config.DEFAULTS'
---@brief Immutable default configuration for lsp.nvim.
---@description
--- Single source of truth for every user-settable value. `config/init.lua`
--- deep-merges the user's options over a copy of this table; the table itself
--- is never mutated at runtime.
---
--- Every key here is read by code. Options from `docs/ROADMAP.md` section 9
--- that nothing consumes yet (`completion`, `rename`, `integrations`) are
--- deliberately absent -- a default nothing reads is a promise the plugin does
--- not keep. They arrive with the layer that honors them.
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

  keymaps = {
    -- The mechanism is on by default; the "default" catalogue entry is still
    -- empty (see config/KEYMAPS.lua), so this binds nothing until the keymap
    -- consolidation in roadmap phase 3. On by default now means no config
    -- change is needed later, and no key is claimed in the meantime.
    enable = true,
    preset = "default",
    -- Per-action overrides, e.g. `map = { goto_definition = "gd", rename = false }`.
    map = {},
  },

  usrcmds = {
    enable = true,
  },

  which_key = {
    enable = true,
  },
}

return DEFAULTS
