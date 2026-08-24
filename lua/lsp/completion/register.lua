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

---@type table<string, LspNvim.CompletionSource>
local specs = {}

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
---@param spec LspNvim.CompletionSource
---@return boolean registered
local function register_cmp(spec)
  local ok, cmp = pcall(require, "cmp")
  if not ok then
    return false
  end

  local Source = {}
  Source.__index = Source

  function Source:is_available()
    return M.applies(spec)
  end

  function Source:get_debug_name()
    return spec.name
  end

  if spec.keyword_pattern ~= nil then
    function Source:get_keyword_pattern()
      return spec.keyword_pattern
    end
  end

  function Source:complete(_, callback)
    callback({ items = spec.items(), isIncomplete = false })
  end

  cmp.register_source(spec.name, setmetatable({}, Source))

  -- cmp has no per-source confirm hook, so this is one global listener per
  -- source that filters on the name. Cheap: it only fires on an accepted
  -- completion, not on every keystroke.
  cmp.event:on("confirm_done", function(event)
    local entry = event.entry
    if entry and entry.source and entry.source.name == spec.name then
      M.picked(spec, entry.completion_item.label)
    end
  end)

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
