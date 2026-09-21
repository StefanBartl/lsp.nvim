---@module 'lsp.core.util'
--- `any_client_can_format(bufnr)`: whether any attached LSP client advertises
--- document (or range) formatting -- the guard `lsp.usercmds.formatter`
--- checks before offering `:LspFormat`.
---
--- `organize_imports_sync(bufnr, kind)`: run an organize-imports-shaped
--- `source.*` code action synchronously, for use on `BufWritePre`.
---
--- `is_internal(client)` / `server_clients(bufnr)`: which of Neovim's clients are
--- lsp.nvim's own in-process ones (no process, no language) and which are
--- language servers.
---@class LspUtil

local lsp = vim.lsp
local api = vim.api

local M = {}

--- Every client lsp.nvim runs itself is named with this prefix (today only
--- `lsp.nvim-gitsigns`, see `lsp.core.gitsigns_actions`).
---
--- To Neovim they are clients like any other, so they show up in every
--- `vim.lsp.get_clients()` -- attached to each buffer gitsigns tracks, whatever
--- its language. A consumer that means "is a language server there" (the winbar's
--- guard, `:Lsp stop`, `:Lsp restart`) asks `server_clients` instead.
---@type string
M.INTERNAL_PREFIX = "lsp.nvim-"

--- Is this the name of one of lsp.nvim's own in-process clients?
---@param name any
---@return boolean
function M.is_internal_name(name)
  return type(name) == "string" and vim.startswith(name, M.INTERNAL_PREFIX)
end

--- Is this one of lsp.nvim's own in-process clients?
---@param client vim.lsp.Client|table|nil
---@return boolean
function M.is_internal(client)
  return client ~= nil and M.is_internal_name(client.name)
end

--- The language servers attached to a buffer: `vim.lsp.get_clients` without
--- lsp.nvim's own in-process clients.
---@param bufnr? integer # default: the current buffer
---@return vim.lsp.Client[]
function M.server_clients(bufnr)
  ---@type vim.lsp.Client[]
  local out = {}
  for _, client in ipairs(lsp.get_clients({ bufnr = bufnr or 0 })) do
    if not M.is_internal(client) then
      out[#out + 1] = client
    end
  end
  return out
end

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

  -- Asked per eligible client, not through `lsp.buf_request_sync`. That call
  -- is buffer-wide: it asks every client that supports `textDocument/
  -- codeAction` and waits for all of them, so the `eligible` list above was
  -- computed and then thrown away. One attached client that is not eligible
  -- and does not answer made the whole call time out and return nothing.
  --
  -- Measured with an eligible, cooperative client: alone it applied the action
  -- in 0ms; with one ineligible mute client also on the buffer the identical
  -- call returned `false` after the full 1549ms. This runs on `BufWritePre`,
  -- so that is organize-on-save silently not happening *and* a second added to
  -- every `:w`.
  --
  -- One deadline across all of them, rather than the timeout per client: the
  -- caller is blocking a write and asked for a bound on the whole thing.
  local uv = vim.uv or vim.loop
  local deadline = uv.hrtime() + (timeout_ms or 1000) * 1e6

  local applied = false
  for _, client in ipairs(eligible) do
    local remaining = math.floor((deadline - uv.hrtime()) / 1e6)
    if remaining <= 0 then
      break
    end

    local ok, res = pcall(function()
      return client:request_sync("textDocument/codeAction", params, remaining, bufnr)
    end)
    local actions = ok and type(res) == "table" and res.result or nil

    if type(actions) == "table" then
      for _, action in ipairs(actions) do
        if action.edit then
          -- This client's encoding, not the first eligible one's. Edits from a
          -- `utf-8` server were being applied as `utf-16` whenever a `utf-16`
          -- client happened to sort first -- wrong columns on every line with
          -- a non-ASCII character, which is exactly the damage the
          -- offset-encoding warning in `:LspDoctor buffer` exists to predict.
          lsp.util.apply_workspace_edit(action.edit, client.offset_encoding or "utf-16")
          applied = true
        end

        -- To the client that offered the command, not to every eligible one:
        -- a command is the issuing server's own, and the others have no reason
        -- to know it.
        local cmd = action.command
        if
          cmd
          and client.supports_method
          and client:supports_method("workspace/executeCommand")
        then
          client:request("workspace/executeCommand", cmd, function() end, bufnr)
          applied = true
        end
      end
    end
  end

  return applied
end

return M
