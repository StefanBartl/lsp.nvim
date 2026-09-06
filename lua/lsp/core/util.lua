---@module 'lsp.core.util'
--- `any_client_can_format(bufnr)`: whether any attached LSP client advertises
--- document (or range) formatting -- the guard `lsp.usercmds.formatter`
--- checks before offering `:LspFormat`.
---
--- `organize_imports_sync(bufnr, kind)`: run an organize-imports-shaped
--- `source.*` code action synchronously, for use on `BufWritePre`.
---@class LspUtil

local lsp = vim.lsp
local api = vim.api

local M = {}

---@param bufnr integer
---@return boolean
function M.any_client_can_format(bufnr)
  bufnr = bufnr or 0
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  for _, c in ipairs(clients) do
    local caps = c.server_capabilities or {}
    if caps.documentFormattingProvider or caps.documentRangeFormattingProvider then
      return true
    end
  end
  return false
end

--- Check whether a client supports a given CodeActionKind.
---@param client vim.lsp.Client
---@param kind string
---@return boolean
local function client_supports_code_action_kind(client, kind)
  if
    not (client and client.supports_method and client:supports_method("textDocument/codeAction"))
  then
    return false
  end
  local caps = client.server_capabilities or {}
  local provider = caps.codeActionProvider
  local kinds = (type(provider) == "table") and provider.codeActionKinds or nil
  if type(kinds) == "table" then
    for _, k in ipairs(kinds) do
      if k == kind or k == "source" then
        return true
      end
    end
    return false
  end
  return true
end

--- Run a `source.*` code action (e.g. "source.organizeImports") synchronously
--- and apply whatever it returns before returning control to the caller.
---
--- Deliberately NOT `vim.lsp.buf.code_action({ apply = true })`: that call is
--- asynchronous -- it fires the request and returns immediately, so on
--- `BufWritePre` the buffer gets written to disk before the response (and the
--- edit it carries) ever arrives. The "on save" feature then silently applies
--- one save late, and the eventual edit lands against whatever the buffer has
--- become by the time the response shows up, not what it was at save time.
--- `buf_request_sync` blocks `BufWritePre` until the action (or the timeout)
--- resolves, so the edit is either applied before the write or not at all.
---@param bufnr integer
---@param kind string # CodeActionKind to request, e.g. "source.organizeImports"
---@param timeout_ms? integer # default 1000
---@return boolean applied
function M.organize_imports_sync(bufnr, kind, timeout_ms)
  bufnr = bufnr or 0
  local clients = lsp.get_clients({ bufnr = bufnr })
  if #clients == 0 then
    return false
  end

  ---@type vim.lsp.Client[]
  local eligible = {}
  for _, c in ipairs(clients) do
    if client_supports_code_action_kind(c, kind) then
      eligible[#eligible + 1] = c
    end
  end
  if #eligible == 0 then
    return false
  end

  local enc = eligible[1].offset_encoding or "utf-16"

  local line_count = api.nvim_buf_line_count(bufnr)
  local td = lsp.util.make_text_document_params(bufnr)

  ---@type lsp.CodeActionParams
  local params = {
    textDocument = td,
    range = {
      start = { line = 0, character = 0 },
      ["end"] = { line = math.max(0, line_count - 1), character = 0 },
    },
    context = { only = { kind }, diagnostics = {} },
  }

  local results = lsp.buf_request_sync(bufnr, "textDocument/codeAction", params, timeout_ms or 1000)
  if not results then
    return false
  end

  local applied = false
  for _, res in pairs(results) do
    local actions = res and res.result
    if type(actions) == "table" then
      for _, action in ipairs(actions) do
        if action.edit then
          vim.lsp.util.apply_workspace_edit(action.edit, enc)
          applied = true
        end
        local cmd = action.command
        if cmd then
          for _, c in ipairs(eligible) do
            if c.supports_method and c:supports_method("workspace/executeCommand") then
              c:request("workspace/executeCommand", cmd, function() end, bufnr)
              applied = true
            end
          end
        end
      end
    end
  end

  return applied
end

return M
