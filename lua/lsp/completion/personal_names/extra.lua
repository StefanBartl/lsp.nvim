---@module 'lsp.completion.personal_names.extra'
--- Hand-maintained extra words for `lsp.completion.personal_names`, for
--- anything worth completing as one atomic candidate that isn't already a
--- personal plugin name from `plugins.personal.list` (that list is read
--- live and needs no entry here). Duplicates against that list are fine —
--- they're deduplicated when the two are merged.
---
--- Just add a string. No restart-order dependency, no other file to touch:
--- this is read fresh every time the item cache is rebuilt (once per
--- session, or immediately after editing if you also run `:CmpReloadWords`
--- — see `lsp.completion.personal_names`).

---@type string[]
return {
  -- "REPOS_DIR",
  -- "nvim-treesitter",
}
