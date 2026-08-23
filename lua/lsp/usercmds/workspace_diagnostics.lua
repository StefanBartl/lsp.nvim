---@module 'lsp.usercmds.workspace_diagnostics'
--- :LspWorkspaceDiagnostics{Toggle,On,Off,Status,Now} — runtime control over
--- whether workspace-diagnostics.nvim populates diagnostics workspace-wide
--- on every LSP attach (see lsp.core.workspace_diagnostics for why this is
--- toggleable rather than a fixed startup-only flag).

local notify = require("lib.nvim.notify").create("[lsp.usercmds.workspace_diagnostics]")

local nvim_create_user_command = vim.api.nvim_create_user_command

local M = {}

local desc_tag = "[lsp_workspace_diagnostics] "

---@return nil
function M.attach()
  local wd = require("lsp.core.workspace_diagnostics")

  pcall(nvim_create_user_command, "LspWorkspaceDiagnosticsToggle", function()
    wd.toggle()
  end, { desc = desc_tag .. "toggle workspace-wide diagnostics populate on LSP attach" })

  pcall(nvim_create_user_command, "LspWorkspaceDiagnosticsOn", function()
    wd.set(true)
  end, { desc = desc_tag .. "enable workspace-wide diagnostics populate on LSP attach" })

  pcall(nvim_create_user_command, "LspWorkspaceDiagnosticsOff", function()
    wd.set(false)
  end, { desc = desc_tag .. "disable workspace-wide diagnostics populate on LSP attach" })

  pcall(nvim_create_user_command, "LspWorkspaceDiagnosticsStatus", function()
    notify.info("workspace diagnostics on LSP attach: " .. (wd.enabled() and "ON" or "OFF"))
  end, { desc = desc_tag .. "show current state" })

  pcall(nvim_create_user_command, "LspWorkspaceDiagnosticsNow", function()
    local ok, count_or_err = wd.populate_now(0)
    if not ok then
      notify.warn(tostring(count_or_err))
    else
      notify.info(
        ("populated workspace diagnostics for %d client(s) on this buffer"):format(count_or_err)
      )
    end
  end, { desc = desc_tag .. "force-populate workspace diagnostics now, regardless of the toggle" })
end

return M
