---@module 'lsp.pack.completion_blink'
---@brief blink.cmp wiring, the alternative to nvim-cmp.
---@description
--- Selected with `vim.g.lsp_nvim.pack.completion = "blink"`. The two engines
--- are mutually exclusive by construction -- each spec's `enabled` checks
--- `pack.completion()` -- because two completion engines competing for the
--- same keys is not a configuration anyone wants by accident.
---
--- `lsp.core.capabilities` has supported blink all along through
--- `lsp.integrations.blink`; what was missing was a way to install it. This is
--- the spec that used to sit commented out in the config's `plugins/lsp.lua`.
---
--- The two hand-written sources are declared here as providers. blink resolves
--- a provider from its `module` path lazily, so these names cost nothing until
--- a completion is actually requested -- and `opts.source` is how the shared
--- adapter knows which registered spec it is standing in for.
---
--- The accept key comes from `vim.g.lsp_nvim.pack.completion_accept` and
--- defaults to `<CR>`; everything else in the keymap is whichever blink preset
--- that selects, so a config keeps overriding individual keys on top.
---
---@see lsp.pack
---@see lsp.config.pack
---@see lsp.integrations.blink

local pack = require("lsp.config.pack")

---@type table[]
return {
  {
    "saghen/blink.cmp",
    enabled = pack.completion() == "blink" and pack.enabled("blink.cmp"),
    -- Pinned to v1.x so the prebuilt fuzzy binaries match the Lua side.
    version = "1.*",
    opts = {
      -- `<CR>` or `<C-y>`, from the pack option. Set as a whole preset rather
      -- than a single binding: the two differ in more than the key, and a
      -- `keymap` table without a `preset` assigns nothing else at all, so a
      -- config that overrides one key would otherwise lose the rest.
      keymap = {
        preset = pack.completion_accept() == "cr" and "enter" or "default",
      },
      -- Suppress completion in utility buffers -- the same fix the nvim-cmp
      -- fragment carries, and what makes `<CR>` safe to default to. blink's
      -- own guard stops at `buftype = "prompt"`, but `lib.nvim.ui.kit`'s
      -- floating input, chooser and confirm dialogs are `buftype = "nofile"`:
      -- with the menu open over one and Enter bound to accept, submitting a
      -- filename in a rename prompt would take a fuzzy-matched completion
      -- instead of what was typed.
      --
      -- dap's REPL and dapui's panes are named explicitly because blink only
      -- re-enables itself there when this predicate already said yes -- left
      -- implicit they would be collateral of the nofile rule.
      enabled = function()
        local ft = vim.bo.filetype
        if ft == "dap-repl" or vim.startswith(ft, "dapui_") then
          return true
        end
        return vim.bo.buftype ~= "nofile"
      end,
      sources = {
        default = { "lazydev", "lsp", "path", "snippets", "buffer", "personal_names" },
        -- md_words only makes sense where the dictionary was built, so it is
        -- added per filetype rather than globally. `inherit_defaults` keeps the
        -- normal sources instead of replacing them.
        per_filetype = {
          markdown = { inherit_defaults = true, "md_words" },
          mdx = { inherit_defaults = true, "md_words" },
        },
        providers = {
          lazydev = {
            name = "LazyDev",
            module = "lazydev.integrations.blink",
            score_offset = 100,
          },
          personal_names = {
            name = "personal_names",
            module = "lsp.completion.blink",
            opts = { source = "personal_names" },
          },
          md_words = {
            name = "md_words",
            module = "lsp.completion.blink",
            opts = { source = "md_words" },
            -- Plain dictionary words are a fallback behind real LSP items, the
            -- same standing the cmp side gave it with `priority = 100`.
            score_offset = -3,
          },
        },
      },
      fuzzy = {
        implementation = "prefer_rust",
        prebuilt_binaries = { force_version = "v1.4.0" },
      },
      signature = { enabled = true },
    },
  },
}
