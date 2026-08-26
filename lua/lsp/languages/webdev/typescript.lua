---@module 'lsp.languages.webdev.typescript'
--- TypeScript/JS QoL: organizes imports synchronously on every BufWritePre
--- for `*.ts`/`*.tsx`/`*.js`/`*.jsx`, via a direct LSP code-action request
--- rather than the async `vim.lsp.buf.code_action` path.

local M = {}

local lsp = vim.lsp
local api = vim.api
local Autocmd = require("lib.nvim.bindings.autocmd")

--- Check whether a client supports a given CodeActionKind.
---@param client LspMod.Client
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

--- Run "source.organizeImports" synchronously before save.
--- Builds proper LspMod.CodeAction.Params, applies edits, and executes commands explicitly.
---@param bufnr integer
---@return boolean applied
local function organize_imports_sync(bufnr)
  local clients = lsp.get_clients({ bufnr = bufnr })
  if #clients == 0 then
    return false
  end

  ---@type LspMod.Client[]
  local eligible = {}
  for _, c in ipairs(clients) do
    if client_supports_code_action_kind(c, "source.organizeImports") then
      eligible[#eligible + 1] = c
    end
  end
  if #eligible == 0 then
    return false
  end

  local enc = eligible[1].offset_encoding or "utf-16"

  local line_count = api.nvim_buf_line_count(bufnr)
  local td = lsp.util.make_text_document_params(bufnr)

  ---@type LspMod.CodeAction.Params
  local params = {
    textDocument = td,
    range = {
      start = { line = 0, character = 0 },
      ["end"] = { line = math.max(0, line_count - 1), character = 0 },
    },
    context = { only = { "source.organizeImports" }, diagnostics = {} },
  }

  local results = lsp.buf_request_sync(bufnr, "textDocument/codeAction", params, 1000)
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

---@return nil
function M.enable()
  local grp = api.nvim_create_augroup("LangTs", { clear = true })
  Autocmd.create("BufWritePre", function(ev)
    pcall(organize_imports_sync, ev.buf)
  end, {
    group = grp,
    pattern = { "*.ts", "*.tsx", "*.js", "*.jsx" },
  })
end

---@type Lsp.Languages.ConfiguredLangs.Webdev.Typescript.Module
return M
