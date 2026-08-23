---@module 'lsp.core.diagnostics'
--- Unified `vim.diagnostic.config()`: virtual_lines only on the current line,
--- virtual_text off, modern sign config on Neovim 0.10+ with a fallback
--- for older versions.
---@class DiagnosticsPolicy
local M = {}

--- Unified diagnostic visuals:
--- - virtual_lines nur für die aktuelle Zeile
--- - virtual_text aus
--- - moderne Sign-Konfiguration (Neovim 0.10+), Fallback für ältere Versionen
---@return nil
function M.setup()
  local use_modern_signs = vim.fn.has("nvim-0.10") == 1

  -- Common diagnostic config
  vim.diagnostic.config({
    underline = true,
    update_in_insert = false,
    severity_sort = true,
    -- virtual_lines = { only_current_line = true },
    virtual_text = true,
    -- Modern sign configuration (no deprecated sign_define)
    signs = use_modern_signs and {
      -- Using Nerd Font icons or simple ASCII
      text = {
        [vim.diagnostic.severity.ERROR] = "■",
        [vim.diagnostic.severity.WARN] = "■",
        [vim.diagnostic.severity.INFO] = "□",
        [vim.diagnostic.severity.HINT] = "·",
      },
      -- Optional: highlight groups for line numbers
      numhl = {
        [vim.diagnostic.severity.ERROR] = "DiagnosticSignError",
        [vim.diagnostic.severity.WARN] = "DiagnosticSignWarn",
        [vim.diagnostic.severity.INFO] = "DiagnosticSignInfo",
        [vim.diagnostic.severity.HINT] = "DiagnosticSignHint",
      },
    } or true, -- keep signs enabled on older Neovim; icons set below via sign_define
    float = {
      focusable = true,
      style = "minimal",
      border = "rounded",
      source = "if_many",
    },
  })

  -- Backward compat: only define legacy signs if Neovim < 0.10
  if not use_modern_signs then
    ---@type table<string,string>
    local Signs = { Error = "■", Warn = "■", Info = "□", Hint = "·" }
    for k, v in pairs(Signs) do
      local hl = "DiagnosticSign" .. k
      -- Using sign_define only on old Neovim avoids the deprecation warning on 0.10+
      vim.fn.sign_define(hl, { text = v, texthl = hl, numhl = "" })
    end
  end
end

return M
