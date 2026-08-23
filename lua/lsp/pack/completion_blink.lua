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
--- the spec that used to sit commented out in the config's `plugins/lsp.lua`,
--- which is why the roadmap (section 15) still lists the choice between the
--- engines as open: it was never actually available.
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
        default = { "lazydev", "lsp", "path", "snippets", "buffer" },
        providers = {
          lazydev = {
            name = "LazyDev",
            module = "lazydev.integrations.blink",
            score_offset = 100,
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
