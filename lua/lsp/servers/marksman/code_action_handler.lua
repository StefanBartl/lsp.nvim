---@module 'lsp.servers.marksman.code_action_handler'
--- Wraps marksman's own `textDocument/codeAction` handler to drop
--- table-of-contents code actions from the list -- every other client's
--- code actions pass through the default handler untouched.

---@internal
--- Hand the result on to whatever handler would have run without us.
---
--- Looked up per call rather than captured when the wrapper is built, and
--- tolerant of there being none. Both halves are the bug this replaced.
---
--- Neovim has had no `vim.lsp.handlers["textDocument/codeAction"]` since 0.11:
--- `vim.lsp.buf.code_action()` aggregates results from several clients into one
--- prompt and keeps its own handler (`vim/lsp/buf.lua`, "Can't call/use
--- vim.lsp.handlers['textDocument/codeAction']"). Measured on 0.12.2: the key
--- is `nil`, so the captured upvalue was `nil`, so *every* call raised --
--- including the marksman path this module exists for. End to end against a
--- fake marksman client:
---
---     client:request("textDocument/codeAction", ...)  -- no explicit handler
---     -> code_action_handler.lua:31: attempt to call upvalue
---        'default_handler' (a nil value)
---
--- Capturing at build time was the second half: `make_handler()` runs from
--- `M.setup`, so a handler another plugin installs afterwards was invisible to
--- it either way.
---
--- With no handler to defer to, returning the filtered list is the whole job --
--- a response handler's return value is what the requester receives.
---@param err any
---@param result table|nil
---@param ctx table
---@param config table
---@return any
local function forward(err, result, ctx, config)
  local handler = vim.lsp.handlers["textDocument/codeAction"]
  if type(handler) == "function" then
    return handler(err, result, ctx, config)
  end
  return result
end

---@return fun(err:any, result:table|nil, ctx:table, config:table)
local function make_handler()
  return function(err, result, ctx, config)
    if not result or not ctx or not ctx.client_id then
      return forward(err, result, ctx, config)
    end

    local client = vim.lsp.get_client_by_id(ctx.client_id)
    if not client or client.name ~= "marksman" then
      return forward(err, result, ctx, config)
    end

    -- Filter out TOC-related code actions
    local filtered = {}
    for i = 1, #result do
      local action = result[i]
      local title = type(action.title) == "string" and action.title:lower() or ""

      if not title:find("toc", 1, true) and not title:find("table of contents", 1, true) then
        filtered[#filtered + 1] = action
      end
    end

    return forward(err, filtered, ctx, config)
  end
end

return make_handler
