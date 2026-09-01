---@module 'lsp.integrations.inc_rename.setup'
--- @module 'config.inc_rename'
--- Incremental LSP rename with Noice cmdline UI and automatic save of edited buffers.
--- Press <leader>rn to start a workspace-aware rename pre-filled with <cword>.
--- On <CR>, the LSP applies a WorkspaceEdit; a post_hook then writes all touched buffers.

-- ============================================================================
-- Types
-- ============================================================================

--- LSP text edit
--- @class LspTextEdit
--- @field range table              -- LSP Range
--- @field newText string

--- A change to a single text document
--- @class LspTextDocumentEdit
--- @field textDocument lsp.VersionedTextDocumentIdentifier
--- @field edits LspTextEdit[]

--- File operations in WorkspaceEdit (rename/create/delete)
--- @class LspFileOp
--- @field kind "rename"|"create"|"delete"
--- @field oldUri string|nil
--- @field newUri string|nil
--- @field uri string|nil

--- Result table passed by inc-rename's post_hook (LSP WorkspaceEdit result)
--- @class IncRenameResult
--- @field changes? table<string, LspTextEdit[]>
--- @field documentChanges? (LspTextDocumentEdit|LspFileOp)[]

-- ============================================================================
-- Helpers
-- ============================================================================

--- Collect all URIs affected by a WorkspaceEdit-like result.
--- @param res IncRenameResult|nil
--- @return string[] uris
local function collect_uris(res)
  ---@type string[]
  local uris = {}
  if not res then
    return uris
  end
  local push = function(u)
    if not u then
      return
    end
    uris[#uris + 1] = u
  end

  -- From map-like "changes"
  if res.changes then
    for uri, edits in pairs(res.changes) do
      if type(edits) == "table" and #edits > 0 then
        push(uri)
      end
    end
  end

  -- From array-like "documentChanges" (may contain TextDocumentEdit or file ops)
  if res.documentChanges then
    for _, dc in ipairs(res.documentChanges) do
      -- ---@cast dc table
      if dc.textDocument and dc.edits then
        push(dc.textDocument.uri)
      elseif dc.kind == "rename" then
        push(dc.oldUri)
        push(dc.newUri)
      elseif dc.kind == "create" or dc.kind == "delete" then
        push(dc.uri)
      end
    end
  end
  return uris
end

--- True if the result contains at least one edit or file op.
--- @param res IncRenameResult|nil
--- @return boolean
local function has_edits(res)
  if not res then
    return false
  end
  if res.changes then
    for _, edits in pairs(res.changes) do
      if type(edits) == "table" and #edits > 0 then
        return true
      end
    end
  end
  if res.documentChanges and #res.documentChanges > 0 then
    return true
  end
  return false
end

--- Write only buffers that correspond to the given URIs (load hidden ones as needed).
--- Preserves window state and avoids writing unmodified or unmodifiable buffers.
--- @param uris string[]
local function write_uri_buffers(uris)
  local seen = {}
  for _, uri in ipairs(uris) do
    if not seen[uri] then
      seen[uri] = true
      local bufnr = vim.uri_to_bufnr(uri) -- loads buffer if not loaded yet
      if
        vim.api.nvim_buf_is_loaded(bufnr)
        and vim.bo[bufnr].modifiable
        and vim.bo[bufnr].buftype == ""
        and vim.bo[bufnr].modified
      then
        vim.api.nvim_buf_call(bufnr, function()
          -- keepalt: do not clobber alternate file; silent keeps cmdline clean
          vim.cmd("silent keepalt write")
        end)
      end
    end
  end
end

-- ============================================================================
-- Setup
-- ============================================================================

local M = {}

--- Configure inc-rename.
---
--- A function rather than work at require-time: this file used to run its
--- `inc_rename.setup()` as a side effect of being required, which meant
--- requiring it to read a helper also reconfigured the plugin and set a global
--- option. The pack spec's `config` calls this.
---@return boolean ok
function M.configure()
  local ok_mod, inc_rename = pcall(require, "inc_rename")
  if not ok_mod then
    return false
  end

  -- Live preview of the edits in a split while typing; complements
  -- inc-rename's own preview for multi-file renames.
  vim.o.inccommand = "split"

  inc_rename.setup({
    -- Keep UI defaults; Noice preset supplies the cmdline UI
    cmd_name = "IncRename",
    hl_group = "Substitute",
    show_message = true,
    save_in_cmdline_history = true,

    -- After the LSP rename applied its WorkspaceEdit, save all touched buffers.
    ---@param result IncRenameResult|nil
    post_hook = function(result)
      -- Ensure we run after Neovim finished applying edits
      vim.schedule(function()
        if not has_edits(result) then
          return
        end
        local uris = collect_uris(result)
        if #uris == 0 then
          -- Fallback: if the server returned no URIs, write all modified buffers.
          vim.cmd("silent wall")
          return
        end
        write_uri_buffers(uris)
      end)
    end,
  })

  return true
end

-- If using Noice, enable the dedicated preset for inc-rename's cmdline integration.
-- This only changes the input UI; the rename scope remains LSP-driven (workspace edits).
-- require("noice").setup({ presets = { inc_rename = true } })

-- ============================================================================
-- Keymaps
-- ============================================================================

-- <leader>rn moved into lsp.nvim's keymap catalogue, together with `grn`.
--
-- The two used to do different things -- `grn` ran vim.lsp.buf.rename, this ran
-- :IncRename -- which is what made "which rename am I in?" a real question.
-- Both now go through the catalogue's `rename` action, which picks the backend
-- from `rename.provider` ("auto" prefers inc-rename when installed). This file
-- keeps owning inc-rename's *setup* (its post_hook auto-save), just not the
-- key that starts it.

return M
