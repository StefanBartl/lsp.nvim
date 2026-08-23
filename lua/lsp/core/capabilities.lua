---@module 'lsp.core.capabilities'
--- Build client capabilities from multiple completion stacks (cmp, blink, NvChad).
---
--- Never notifies directly: degraded/missing completion stacks are collected
--- into `warnings` and returned alongside `caps`, so the caller (lsp/init.lua)
--- decides whether/how to surface them.

local lsp = vim.lsp
local tbl_deep_extend = vim.tbl_deep_extend

local M = {}

---@alias LspCaps.Warning { level: "warn"|"error", msg: string }

---@return table caps
---@return LspCaps.Warning[] warnings
function M.get()
  -- Start with base LSP capabilities
  local caps = lsp.protocol.make_client_capabilities()
  ---@type LspCaps.Warning[]
  local warnings = {}

  -- NvChad capabilities FIRST
  do
    local ok, nvlsp = pcall(require, "nvchad.configs.lspconfig")
    if ok and type(nvlsp.capabilities) == "table" then
      caps = tbl_deep_extend("force", caps, nvlsp.capabilities)
    end
  end

  -- nvim-cmp capabilities (wichtig für completion)
  do
    local ok, cmp = pcall(require, "cmp_nvim_lsp")
    if ok and type(cmp.default_capabilities) == "function" then
      local cmp_caps = cmp.default_capabilities()
      caps = tbl_deep_extend("force", caps, cmp_caps)

      -- Verify completion capabilities wurden geladen
      if not (caps.textDocument and caps.textDocument.completion) then
        warnings[#warnings + 1] =
          { level = "warn", msg = "⚠️  nvim-cmp loaded but no completion capabilities!" }
      end
    else
      warnings[#warnings + 1] =
        { level = "warn", msg = "⚠️  nvim-cmp not found! Completion may not work." }
    end
  end

  -- Blink capabilities optional, als fallback
  do
    local ok, blink = pcall(require, "blink.cmp")
    if ok and type(blink.get_lsp_capabilities) == "function" then
      caps = tbl_deep_extend("force", caps, blink.get_lsp_capabilities(caps))
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
---@return boolean ok
---@return LspCaps.Warning[] warnings
function M.apply_globally()
  -- Merge these caps into every named config as a base ("*")
  local caps, warnings = M.get()
  if type(lsp.config) ~= "table" then
    warnings[#warnings + 1] =
      { level = "error", msg = "vim.lsp.config not available (Neovim < 0.10?)" }
    return false, warnings
  end
  lsp.config("*", { capabilities = caps })
  return true, warnings
end

return M
