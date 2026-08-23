---@module 'lsp.core.capabilities'
--- Build client capabilities from the base protocol plus injected contributors.
---
--- This module used to `pcall(require, ...)` NvChad, cmp and blink itself. It
--- does not any more: each of those lives in `lsp.integrations.<name>` and is
--- passed in as a plain function, so the core stays testable without a plugin
--- manager and adding a completion engine touches one adapter instead of this
--- file (roadmap section 3's layering).
---
--- What stays here is the part that is genuinely core: the base capabilities,
--- the verification that *something* contributed completion support, and the
--- hand-written fallback when nothing did. That check is why roadmap finding
--- B1 -- a broken merge that silently degraded completion -- is visible at all.
---
--- Never notifies directly: degraded/missing completion stacks are collected
--- into `warnings` and returned alongside `caps`, so the caller (lsp/init.lua)
--- decides whether/how to surface them.

local lsp = vim.lsp
local tbl_deep_extend = vim.tbl_deep_extend

local M = {}

---@alias LspCaps.Warning { level: "warn"|"error", msg: string }

---@alias LspCaps.Contributor fun(caps: table): table|nil, LspCaps.Warning[]|nil

--- Build the client capabilities.
---
--- `contributors` are applied in order and each may return a new capability
--- table, warnings, or neither. Order matters: `tbl_deep_extend("force", …)`
--- lets a later contributor win, which is why `lsp.integrations` hands them
--- over NvChad-first and completion-engine-after.
---@param contributors LspCaps.Contributor[]|nil
---@return table caps
---@return LspCaps.Warning[] warnings
function M.get(contributors)
  -- Start with base LSP capabilities
  local caps = lsp.protocol.make_client_capabilities()
  ---@type LspCaps.Warning[]
  local warnings = {}

  for _, contribute in ipairs(contributors or {}) do
    local ok, contributed, contributed_warnings = pcall(contribute, caps)
    if not ok then
      warnings[#warnings + 1] =
        { level = "warn", msg = "capability contributor failed: " .. tostring(contributed) }
    else
      if type(contributed) == "table" then
        caps = contributed
      end
      for _, w in ipairs(contributed_warnings or {}) do
        warnings[#warnings + 1] = w
      end
    end
  end

  -- Explizit completion capabilities verifizieren
  if not caps.textDocument or not caps.textDocument.completion then
    warnings[#warnings + 1] = {
      level = "error",
      msg = "⚠️  NO COMPLETION CAPABILITIES! Check if nvim-cmp or blink.cmp is installed!",
    }

    -- Fallback: Minimale completion capabilities manuell setzen
    caps.textDocument = caps.textDocument or {}
    caps.textDocument.completion = {
      dynamicRegistration = false,
      completionItem = {
        snippetSupport = true,
        commitCharactersSupport = true,
        deprecatedSupport = true,
        preselectSupport = true,
        tagSupport = {
          valueSet = { 1 }, -- Deprecated
        },
        insertReplaceSupport = true,
        resolveSupport = {
          properties = { "documentation", "detail", "additionalTextEdits" },
        },
        insertTextModeSupport = {
          valueSet = { 1, 2 }, -- AsIs = 1, AdjustIndentation = 2
        },
        labelDetailsSupport = true,
      },
      contextSupport = true,
      insertTextMode = 1,
      completionList = {
        itemDefaults = {
          "commitCharacters",
          "editRange",
          "insertTextFormat",
          "insertTextMode",
          "data",
        },
      },
    }
    warnings[#warnings + 1] =
      { level = "warn", msg = "⚠️  Using FALLBACK completion capabilities" }
  end

  return caps, warnings
end

---Apply capabilities globally to all LSP configs. Never notifies directly
---(see module doc) -- always returns the warnings from M.get(), plus an
---extra entry when vim.lsp.config itself isn't available, so the caller
---can iterate a single list either way.
---
---Prefer `require("lsp").apply_capabilities()`: it passes the integration
---layer's contributors, and calling this directly without them yields the bare
---protocol capabilities plus the "no completion" fallback -- which looks like a
---broken setup rather than a missing argument.
---@param contributors LspCaps.Contributor[]|nil
---@return boolean ok
---@return LspCaps.Warning[] warnings
function M.apply_globally(contributors)
  -- Merge these caps into every named config as a base ("*")
  local caps, warnings = M.get(contributors)
  if type(lsp.config) ~= "table" then
    warnings[#warnings + 1] =
      { level = "error", msg = "vim.lsp.config not available (Neovim < 0.10?)" }
    return false, warnings
  end
  lsp.config("*", { capabilities = caps })
  return true, warnings
end

return M
