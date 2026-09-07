---@module 'lsp.core.diagnostics'
---@brief The single owner of `vim.diagnostic.config()`.
---@description
--- `vim.diagnostic.config()` is one global surface with no notion of an owner:
--- every caller merges into the same table, the last one wins per key, and
--- nobody is told. Two plugins with opinions about signs produce a setup where
--- the icons come from one and the virtual text from the other, depending on
--- startup order, and neither is wrong.
---
--- So this module owns the call. It is made exactly once, from `M.apply`, out
--- of three layers merged so that later wins — the same rule
--- `core/capabilities.lua` uses, with one correction for the severity-keyed
--- sign tables (see `SEVERITY_MAPS`):
---
---   1. **This module's baseline.** What lsp.nvim considers a sane diagnostic
---      presentation on its own.
---   2. **Contributions**, in registration order. Any plugin with a diagnostic
---      opinion calls `M.contribute(name, spec)` before `lsp.setup()` runs.
---      This module does not know who they are and does not require them.
---   3. **`opts.diagnostics`.** Last, so a configuration can always override
---      both. It holds only what a user set: lsp.nvim's own presentation is
---      layer 1, not layer 3, precisely so that a contribution is overruled
---      by the user and not by this plugin's defaults.
---
--- `M.sources()` reports the layers by name, so `:checkhealth lsp` can answer
--- "where did this icon come from" — which is the question the silent-merge
--- behaviour makes impossible to answer otherwise.
---
--- Until 2026-09-08 this module called `vim.diagnostic.config()` itself and
--- `lsp/init.lua` called it a second time with `cfg.diagnostics`. Both writes
--- landed, the second only overriding the keys it named — so lsp.nvim's own
--- signs came from here and its virtual text from DEFAULTS, which is the
--- confusion described above, inside one plugin. Consolidating the two put the
--- presentation in `baseline()` and left `DEFAULTS.diagnostics` with the two
--- keys that are not presentation at all.
---@see lsp.core.capabilities

local M = {}

--- Contributions, in registration order.
---@type { name: string, spec: table }[]
local _contributions = {}

--- The sub-tables of `vim.diagnostic.config()` that are keyed by
--- `vim.diagnostic.severity`, as paths from the root.
---
--- These need their own merge rule. Severity values are 1..4, so a full sign
--- table is `{ [1]=…, [2]=…, [3]=…, [4]=… }` -- which `vim.islist` reports as
--- a list, and `vim.tbl_deep_extend` replaces a list wholesale instead of
--- merging it. A plugin contributing one icon would therefore delete the
--- other three, silently:
---
---   tbl_deep_extend("force", { text = { "A", "B", "C", "D" } },
---                            { text = { "X" } })
---   --> { text = { "X" } }
---
--- Found by the spec that asserts a partial sign contribution keeps its
--- siblings.
---@type string[][]
local SEVERITY_MAPS = {
  { "signs", "text" },
  { "signs", "numhl" },
  { "signs", "linehl" },
  { "signs", "texthl" },
}

---@internal
--- `vim.tbl_deep_extend("force", …)`, with the severity-keyed sign tables
--- merged key by key instead of replaced.
---@param base table
---@param add table
---@return table
local function merge(base, add)
  --- The table `path` names inside `root`, or nil if any step is missing or
  --- is not a table.
  ---@param root table
  ---@param path string[]
  ---@param upto integer # how many segments of `path` to follow
  ---@return table|nil
  local function dig(root, path, upto)
    ---@type any
    local node = root
    for i = 1, upto do
      if type(node) ~= "table" then
        return nil
      end
      node = node[path[i]]
    end
    return type(node) == "table" and node or nil
  end

  local out = vim.tbl_deep_extend("force", base, add)

  for _, path in ipairs(SEVERITY_MAPS) do
    local from_base = dig(base, path, #path)
    local from_add = dig(add, path, #path)
    local parent = dig(out, path, #path - 1)

    -- Only when both sides brought one; otherwise tbl_deep_extend's result is
    -- already right (one side absent means nothing was replaced).
    if from_base and from_add and parent then
      local merged = {}
      for k, v in pairs(from_base) do
        merged[k] = v
      end
      for k, v in pairs(from_add) do
        merged[k] = v
      end
      parent[path[#path]] = merged
    end
  end

  return out
end

--- The table actually handed to `vim.diagnostic.config()`, or nil before
--- `M.apply` has run.
---@type table|nil
local _applied = nil

--- Keys that live in `opts.diagnostics` for lsp.nvim's own use and would be
--- passed verbatim to an API that does not know them.
---
--- `ui` picks where `]d`/`[d` send you (`lsp.bindings.actions`) and
--- `debounce_ms` sizes the publish throttle (`lsp.core.handlers`).
---@type string[]
local NOT_DIAGNOSTIC_CONFIG = { "ui", "debounce_ms" }

--- lsp.nvim's own diagnostic presentation.
---
--- Deliberately a function rather than a constant: the sign table is keyed by
--- `vim.diagnostic.severity.*`, and reading those at module load would pin the
--- values before a test can stub them.
---@nodiscard
---@return table
function M.baseline()
  return {
    underline = true,
    update_in_insert = false,
    severity_sort = true,
    -- A table, not `true`: `spacing`/`prefix` were in config/DEFAULTS.lua and
    -- moved here with the rest of the presentation, so this is what a session
    -- actually rendered before the move.
    virtual_text = { spacing = 2, prefix = "●" },
    signs = {
      text = {
        [vim.diagnostic.severity.ERROR] = "■",
        [vim.diagnostic.severity.WARN] = "■",
        [vim.diagnostic.severity.INFO] = "□",
        [vim.diagnostic.severity.HINT] = "·",
      },
      numhl = {
        [vim.diagnostic.severity.ERROR] = "DiagnosticSignError",
        [vim.diagnostic.severity.WARN] = "DiagnosticSignWarn",
        [vim.diagnostic.severity.INFO] = "DiagnosticSignInfo",
        [vim.diagnostic.severity.HINT] = "DiagnosticSignHint",
      },
    },
    float = {
      focusable = true,
      style = "minimal",
      border = "rounded",
      source = "if_many",
    },
  }
end

--- Register a diagnostic contribution.
---
--- For a plugin that has an opinion about signs, virtual text or float borders
--- and would otherwise call `vim.diagnostic.config()` itself. Call it before
--- `lsp.setup()`; contributions registered afterwards are recorded but do not
--- reach the current configuration until the next `M.apply`.
---
--- Registering the same name twice replaces the earlier spec and keeps its
--- position, so a plugin re-running its own `setup()` does not stack.
---
---   require("lsp.core.diagnostics").contribute("my.nvim", {
---     signs = { text = { [vim.diagnostic.severity.ERROR] = " " } },
---   })
---
---@param name string # The contributing plugin, as it should appear in :checkhealth
---@param spec table # Any subset of what `vim.diagnostic.config()` accepts
---@return boolean ok
---@return string|nil err
function M.contribute(name, spec)
  if type(name) ~= "string" or name == "" then
    return false, "contribute: name must be a non-empty string"
  end
  if type(spec) ~= "table" then
    return false, ("contribute: %s passed a %s, expected a table"):format(name, type(spec))
  end

  for _, entry in ipairs(_contributions) do
    if entry.name == name then
      entry.spec = spec
      return true
    end
  end

  _contributions[#_contributions + 1] = { name = name, spec = spec }
  return true
end

--- Drop a contribution. Takes effect on the next `M.apply`.
---@param name string
---@return boolean removed
function M.forget(name)
  for i, entry in ipairs(_contributions) do
    if entry.name == name then
      table.remove(_contributions, i)
      return true
    end
  end
  return false
end

--- Every layer that goes into the merge, in merge order.
---
--- Answers "where did this come from" for `:checkhealth lsp`. The `user` layer
--- is present only after `M.apply` has been given one.
---@nodiscard
---@return { name: string, spec: table }[]
function M.sources()
  local out = { { name = "lsp.nvim (baseline)", spec = M.baseline() } }
  for _, entry in ipairs(_contributions) do
    out[#out + 1] = { name = entry.name, spec = entry.spec }
  end
  if _applied and _applied.__user then
    -- "opts.diagnostics", not "user config": it is the resolved option table,
    -- which is only what a user set now that lsp.nvim's own presentation has
    -- moved into `baseline()`. Naming it after the option rather than after
    -- an assumed author is the honest label.
    out[#out + 1] = { name = "opts.diagnostics", spec = _applied.__user }
  end
  return out
end

--- The table `vim.diagnostic.config()` was last called with, or nil.
---@nodiscard
---@return table|nil
function M.applied()
  return _applied and _applied.effective or nil
end

--- Merge every layer and configure diagnostics. The one call site.
---
--- Called from `lsp.init` after the servers are enabled, so a server
--- configuration cannot overwrite it.
---@param user_opts table|nil # `cfg.diagnostics`
---@return table effective # What was handed to vim.diagnostic.config()
function M.apply(user_opts)
  local effective = M.baseline()

  for _, entry in ipairs(_contributions) do
    effective = merge(effective, entry.spec)
  end

  local user = nil
  if type(user_opts) == "table" then
    user = vim.deepcopy(user_opts)
    for _, key in ipairs(NOT_DIAGNOSTIC_CONFIG) do
      user[key] = nil
    end
    effective = merge(effective, user)
  end

  vim.diagnostic.config(effective)

  _applied = { effective = effective, __user = user }
  return effective
end

---@internal
--- Forget every contribution and the applied state. Tests only.
---@return nil
function M.__reset()
  _contributions = {}
  _applied = nil
end

return M
