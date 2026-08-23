---@module 'lsp.servers.marksman.rootresolver'
--- Root resolver for the Marksman LSP.
---
--- Marksman's notion of a root is exactly "nearest marker upward", so this is
--- `lib.nvim.fs.polymorphic_rootresolver` with the markdown marker list and
--- nothing else. It used to be a hand-written copy of that module's argument
--- normalization -- buffer number or filename, unnamed-buffer fallback, the
--- optional callback the `vim.lsp` root_dir contract allows -- which is what
--- roadmap finding B8 was about: the same wrapper written more than once
--- because the shared one was not reached for.
---
--- `include_stdpath_config = false` preserves the previous behaviour. A
--- Markdown file under the Neovim config directory belongs to whatever
--- repository it sits in, not to the config as a project.
---
---@see lsp.servers.marksman.config

local rootresolver = require("lib.nvim.fs.polymorphic_rootresolver")
local cfg = require("lsp.servers.marksman.config")

--- @return fun(arg: string|integer, cb?: fun(root: string)): string
return function()
  return rootresolver({
    markers = cfg.root_dir_fallbacks,
    include_stdpath_config = false,
  })
end
