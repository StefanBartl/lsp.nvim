---@module 'lsp.config.pack'
---@brief Reads `vim.g.lsp_nvim.pack`: which of the ecosystem gets installed.
---@description
--- The second configuration channel, and it has to be a separate one.
--- lazy.nvim evaluates `import` while it is still *collecting* specs, long
--- before `require("lsp").setup(opts)` exists to be read -- so *whether* a
--- plugin is installed cannot come from `opts`, only *how* it is configured
--- can. `docs/ROADMAP.md` section 6.2 has the split. Set it before
--- `require("lazy").setup()`: >lua
---     vim.g.lsp_nvim = {
---       pack = {
---         core = true,          -- conform, lazydev, workspace-diagnostics
---         ui = true,            -- trouble, lspsaga, lensline, inc-rename
---         completion = "blink", -- "cmp" | "blink" | false (default: blink)
---         disable = { "lspsaga.nvim" },
---       },
---     }
--- <
--- This lives in `config/` rather than in `pack/` for a mechanical reason:
--- `import = "lsp.pack"` makes lazy require *every* module under that
--- directory and treat each result as a spec list. A helper module sitting
--- there would be read as a malformed spec.
---
--- That same mechanic is why selection cannot be done by importing
--- conditionally -- the import is a directory, not a decision. Every spec
--- carries an `enabled` instead.
---
---@see lsp.pack
---@see lsp.config

local M = {}

--- The `pack` sub-table of `vim.g.lsp_nvim`, never nil.
---@return table
function M.opts()
  local g = vim.g.lsp_nvim
  if type(g) ~= "table" or type(g.pack) ~= "table" then
    return {}
  end
  return g.pack
end

--- Is a group switched on? Groups default to on -- the point of an umbrella is
--- that installing it gives you the set.
---@param group "core"|"ui"
---@return boolean
function M.group(group)
  return M.opts()[group] ~= false
end

--- Which completion engine the pack should install.
---
--- Defaults to nvim-cmp rather than nothing: a pack that installs no
--- completion source by default would look broken in the one place an umbrella
--- is supposed to help most.
---@return "cmp"|"blink"|false
function M.completion()
  local choice = M.opts().completion
  if choice == nil then
    -- blink since 2026-08-24: chosen after testing both live, cmp was the
    -- default only because it was the incumbent when the choice first became
    -- real (2026-08-23).
    return "blink"
  end
  if choice == "cmp" or choice == "blink" then
    return choice
  end
  return false
end

--- Should this plugin be installed?
---
--- Returns a value rather than a closure: lazy reads `enabled` when it resolves
--- the spec, which is after the import, so the answer is already knowable.
---@param name string # Plugin short name, e.g. "lspsaga.nvim".
---@param group "core"|"ui"|nil # Group that must also be on.
---@return boolean
function M.enabled(name, group)
  if group ~= nil and not M.group(group) then
    return false
  end

  local disable = M.opts().disable
  if type(disable) == "table" and vim.tbl_contains(disable, name) then
    return false
  end

  return true
end

return M
