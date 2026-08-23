---@module 'lsp.servers.marksman.code_action_handler'
--- Wraps marksman's own `textDocument/codeAction` handler to drop
--- table-of-contents code actions from the list -- every other client's
--- code actions pass through the default handler untouched.

---@return fun(err:any, result:table|nil, ctx:table, config:table)
local function make_handler()
  local default_handler = vim.lsp.handlers["textDocument/codeAction"]

  return function(err, result, ctx, config)
    if not result or not ctx or not ctx.client_id then
      return default_handler(err, result, ctx, config)
    end

    local client = vim.lsp.get_client_by_id(ctx.client_id)
    if not client or client.name ~= "marksman" then
      return default_handler(err, result, ctx, config)
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

    return default_handler(err, filtered, ctx, config)
  end
end

return make_handler
