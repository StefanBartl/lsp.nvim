---@module 'lsp.completion.blink'
---@brief Adapts a registered source spec to blink.cmp's provider contract.
---@description
--- blink resolves providers from a `module` path and calls `new(opts)` on what
--- it finds, so a provider cannot be handed a closure the way `cmp.register_source`
--- takes an object. `opts.source` carries the name instead, and the spec is
--- looked up in `lsp.completion.register` at request time.
---
--- That indirection is also what keeps the ordering honest: blink resolves the
--- module the first time the provider is asked for, which is long after
--- `setup()` has registered the specs.
---
--- The pick is caught in `execute`, which blink calls on accept -- per source,
--- so unlike nvim-cmp there is no global event to filter.
---
---@see lsp.completion.register
---@see lsp.pack.completion_blink

local register = require("lsp.completion.register")

---@class LspNvim.BlinkSource
---@field source_name string
local Source = {}
Source.__index = Source

--- blink instantiates this with the provider's `opts`.
---@param opts? { source?: string }
---@return LspNvim.BlinkSource
function Source.new(opts)
  return setmetatable({ source_name = (opts or {}).source or "" }, Source)
end

---@internal
---@return LspNvim.CompletionSource|nil
function Source:spec()
  return register.spec(self.source_name)
end

--- blink asks before requesting items; `per_filetype` already narrows this, but
--- a spec's own `filetypes` is the authority either way.
---@return boolean
function Source:enabled()
  local spec = self:spec()
  return spec ~= nil and register.applies(spec)
end

---@param _ table # blink.cmp.Context
---@param callback fun(response: table|nil)
---@return nil
function Source:get_completions(_, callback)
  local spec = self:spec()
  if spec == nil then
    callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
    return
  end

  callback({
    items = spec.items(),
    -- The item sets are built and cached whole, never sliced by prefix, so
    -- blink can filter what it already has instead of asking again per
    -- keystroke.
    is_incomplete_forward = false,
    is_incomplete_backward = false,
  })
end

--- Called when the user accepts one of our items.
---
--- `default_implementation()` must still run -- it is what actually inserts the
--- text. Counting first and inserting second would be the same order; doing
--- only the counting would break completion entirely.
---@param _ table # blink.cmp.Context
---@param item table
---@param callback fun()
---@param default_implementation fun()
---@return nil
function Source:execute(_, item, callback, default_implementation)
  local spec = self:spec()
  if spec ~= nil and type(item.label) == "string" then
    register.picked(spec, item.label)
  end
  default_implementation()
  callback()
end

return Source
