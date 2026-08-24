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
