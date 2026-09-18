---@module 'lsp.completion.register'
---@brief Registers a hand-written completion source with whichever engine runs.
---@description
--- A source describes *what* it completes; this decides *how* it gets in. That
--- split is the point: before it existed, `markdown_words` reached for
--- `require("cmp")` inside a FileType autocommand and warned when it was
--- missing, so choosing blink silently cost you the source and printed a
--- confusing message about nvim-cmp.
---
--- A source now hands over a spec and never learns which engine won:
---
--- ```lua
--- register.source({
---   name = "md_words",
---   items = function() return items end,
---   namespace = "md_words",       -- enables usage-count ranking
---   filetypes = { "markdown" },   -- absent = every buffer
--- })
--- ```
---
--- The two engines take opposite approaches, which is why this file exists
--- rather than a shared base class:
---
--- - **nvim-cmp** registers at runtime (`cmp.register_source`) and reports the
---   pick through one global event, filtered by source name.
--- - **blink** resolves providers from `module` paths declared in its config
---   (see `lsp.pack.completion_blink`), so registration here only records the
---   spec for `lsp.completion.blink` to find, and the pick arrives at the
---   source's own `execute`.
---
---@see lsp.completion.usage
---@see lsp.completion.blink
---@see lsp.config.pack

local M = {}

---@class LspNvim.CompletionSource
---@field name string # Source name, as the engine will report it.
---@field items fun(): table[] # LSP CompletionItems. Called per request; cache inside.
---@field namespace? string # Usage namespace. Omit to opt out of frequency ranking.
---@field filetypes? string[] # Restrict to these filetypes. Omit for all buffers.
---@field keyword_pattern? string # nvim-cmp only; blink derives its own.
---@field on_pick? fun(label: string) # Extra work after a pick, besides the count bump.

---@internal
--- The specs table has to survive a module reload for the same reason the
--- `cmp` registration guard below does -- and a fresh `local specs = {}` per
--- load does not.
---
--- Both engines' *live* completion object is created once and then closes
--- over `specs` by reference, forever: cmp's `Source:complete` closes over it
--- directly; blink caches its provider object for the session
--- (`sources.providers[provider_id]`, set once in blink's own
--- `sources/lib/init.lua`) and reaches this table through `M.spec`, itself a
--- closure over the same upvalue. `:Lazy reload lsp.nvim` clears every
--- `lsp.*` module -- this one included -- and re-running `personal_names.setup()`
--- or `markdown_words.setup()` afterwards calls `M.source()` on a *fresh*
--- register.lua instance, which used to write into a brand new, empty
--- `specs` that nothing already running would ever read again.
---
--- Measured against a spec double-check of nvim-cmp's own registration
--- (`cmp.register_source` keys by a fresh id in `core.lua`, not by name, so
--- it is additive) and blink's own provider cache (`provider/init.lua` calls
--- `require(config.module).new(...)` exactly once per `provider_id`): after
--- one simulated reload and re-registration with different `items`, the
--- live source under either engine kept offering the *first* load's items,
--- while the second load's own `M.spec(name)` correctly reported the new
--- ones -- to a caller neither engine will ever ask again. `:CmpReloadWords`
--- after that reports "Reloaded" and changes nothing a user can see, same
--- shape as the bug this table's sibling guard already fixed once.
---
--- Anchored on `_G` rather than on `cmp`, because blink has no analogous host
--- this module could reach into -- `_G` is the one thing neither engine's
--- reload story touches.
---@return table<string, LspNvim.CompletionSource>
local function specs_table()
  local key = "__lsp_nvim_completion_specs"
  local t = rawget(_G, key)
  if type(t) ~= "table" then
    t = {}
    rawset(_G, key, t)
  end
  return t
end

---@type table<string, LspNvim.CompletionSource>
local specs = specs_table()

--- Look up a registered spec. Used by the blink source modules, which are
--- resolved by blink from a `module` path and get no arguments.
---@param name string
---@return LspNvim.CompletionSource|nil
function M.spec(name)
  return specs[name]
end

--- Every registered spec, for `:checkhealth`.
---@return table<string, LspNvim.CompletionSource>
function M.all()
  return specs
end

--- Should this source offer items in the current buffer?
---@param spec LspNvim.CompletionSource
---@return boolean
function M.applies(spec)
  if spec.filetypes == nil then
    return true
  end
  return vim.tbl_contains(spec.filetypes, vim.bo.filetype)
end

--- Record a pick: bump the count, then run the source's own hook.
---@param spec LspNvim.CompletionSource
---@param label string
---@return nil
function M.picked(spec, label)
  if spec.namespace ~= nil then
    require("lsp.completion.usage").bump(spec.namespace, label)
  end
  if spec.on_pick ~= nil then
    pcall(spec.on_pick, label)
  end
end

---@internal
--- nvim-cmp: register a source object and listen for its confirmations.
---
--- Once per source name, however often this is called. `setup()` runs again on
--- a config reload and the sources register again with it, and cmp has no way
--- to remove a listener -- so the `confirm_done` hooks used to stack. Measured:
--- three registrations, and one accepted word counted three times.
---
--- That is not a transient miscount. The counts live in
--- `lsp_completion_usage.json`, they only ever go up, and `usage.lua` describes
--- them as the user's history "accumulated over months" -- so every reload
--- permanently skewed the ranking the file exists to hold.
---
--- The guard is kept on the `cmp` module rather than in a local here, and that
--- placement is the point: a module-local one is cleared by the very reload it
--- has to survive. `:Lazy reload lsp.nvim` drops every `lsp.*` module including
--- this one, while cmp -- and the listeners already on its event bus -- stay
--- exactly where they were. The guard belongs with the thing it is guarding.
---
--- Everything the source does looks the spec up by name rather than closing
--- over the table it was given, so re-registering still takes effect: a
--- changed `items` or `filetypes` is live from the next request without a
--- second object reaching cmp.
---@param spec LspNvim.CompletionSource
---@return boolean registered
local function register_cmp(spec)
  local ok, cmp = pcall(require, "cmp")
  if not ok then
    return false
  end

  local name = spec.name

  ---@type table<string, true>
  local hooked = rawget(cmp, "__lsp_nvim_confirm_hooked")
  if type(hooked) ~= "table" then
    hooked = {}
    cmp.__lsp_nvim_confirm_hooked = hooked
  end
  if hooked[name] then
    return true
  end

  local Source = {}
  Source.__index = Source

  function Source:is_available()
    local current = specs[name]
    return current ~= nil and M.applies(current)
  end

  function Source:get_debug_name()
    return name
  end

  if spec.keyword_pattern ~= nil then
    function Source:get_keyword_pattern()
      local current = specs[name]
      return current and current.keyword_pattern or spec.keyword_pattern
    end
  end

  function Source:complete(_, callback)
    local current = specs[name]
    callback({ items = current and current.items() or {}, isIncomplete = false })
  end

  cmp.register_source(name, setmetatable({}, Source))

  -- cmp has no per-source confirm hook, so this is one global listener per
  -- source that filters on the name. Cheap: it only fires on an accepted
  -- completion, not on every keystroke.
  cmp.event:on("confirm_done", function(event)
    local entry = event.entry
    if entry and entry.source and entry.source.name == name then
      local current = specs[name]
      if current ~= nil then
        M.picked(current, entry.completion_item.label)
      end
    end
  end)

  hooked[name] = true
  return true
end

--- Register a source with the active engine.
---
--- Returns whether it actually got in, so a caller can say so in `status()`.
--- Under blink this is `true` as soon as the spec is recorded: blink resolves
--- the provider lazily from its config, so there is nothing to fail here and
--- nothing to warn about if blink has not loaded yet.
---@param spec LspNvim.CompletionSource
---@return boolean registered
function M.source(spec)
  assert(type(spec.name) == "string" and spec.name ~= "", "source needs a name")
  assert(type(spec.items) == "function", spec.name .. ": items must be a function")

  specs[spec.name] = spec

  local engine = require("lsp.config.pack").completion()
  if engine == "cmp" then
    return register_cmp(spec)
  end
  if engine == "blink" then
    return true
  end

  -- Completion switched off entirely. The spec stays recorded so
  -- `:checkhealth` can still say the source exists but has no engine.
  return false
end

--- Which engine the sources were handed to.
---@return "cmp"|"blink"|false
function M.engine()
  return require("lsp.config.pack").completion()
end

return M
