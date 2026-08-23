---@module 'lsp.pack.completion'
---@brief nvim-cmp wiring the LSP setup contributes.
---@description
--- Not a nvim-cmp *installation*: an `opts` fragment that lazy merges into
--- whatever cmp spec a config already has. That composition is why completion
--- is its own pack module -- an umbrella that owned cmp outright would fight
--- every config that configures its own completion.
---
--- Two contributions, both belonging to "LSP is set up here" rather than to a
--- particular config:
---
--- - the lazydev source at `group_index = 0`, so Lua `require` paths rank
---   above ordinary buffer words;
--- - suppressing completion in utility buffers.
---
--- The second is a bug fix, not a preference. Any buffer with a non-empty
--- 'buftype' is a scratch/prompt/terminal surface, and `lib.nvim.ui.kit`'s
--- floating input, chooser and confirm dialogs are all `buftype=nofile`. With
--- cmp's popup open over one, `<CR>` is bound to "confirm the visible
--- completion" (nvchad.configs.cmp sets `select = true`), so submitting a
--- filename in a rename prompt could silently accept a fuzzy-matched
--- completion instead of what was typed.
---
--- Anything config-specific -- a personal word list, a Copilot bridge -- stays
--- in that config's own cmp spec. lazy merges both.
---
---@see lsp.pack
---@see lsp.config.pack
---@see lsp.integrations.cmp

local pack = require("lsp.config.pack")

---@type table[]
return {
  {
    "hrsh7th/nvim-cmp",
    enabled = pack.completion() == "cmp" and pack.enabled("nvim-cmp"),
    opts = function(_, opts)
      opts.sources = opts.sources or {}
      table.insert(opts.sources, { name = "lazydev", group_index = 0 })

      local previous = opts.enabled
      opts.enabled = function()
        if vim.bo.buftype ~= "" then
          return false
        end
        return type(previous) ~= "function" or previous()
      end
    end,
  },
}
