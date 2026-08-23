---@module 'lsp.core.attach'
--- Build on_init/on_attach handlers; no dependency on lspconfig.

local M = {}

---@param bufnr integer
---@return boolean
local function has_valid_buf(bufnr)
  if type(bufnr) ~= "number" or bufnr <= 0 then
    return false
  end
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return false
  end
  local bt = vim.bo[bufnr].buftype
  if bt ~= "" and bt ~= "acwrite" then
    return false
  end
  return true
end

---@param opts { use_workspace_diagnostics?: boolean, use_lazydev?: boolean }|nil
---@return { on_attach: fun(client,bufnr), on_init: fun(client,init_result):boolean }
function M.build(opts)
  opts = opts or {}

  -- `opts.use_workspace_diagnostics` is only the STARTUP default (seeded
  -- once, e.g. machine-role-gated in lsp/init.lua). After that,
  -- lsp.core.workspace_diagnostics.enabled() is the live, runtime-
  -- toggleable source of truth (see :LspWorkspaceDiagnostics{Toggle,On,Off,
  -- Status,Now}) — on_attach below reads it fresh on every attach instead of
  -- a value captured once here.
  local workspace_diagnostics = require("lsp.core.workspace_diagnostics")
  workspace_diagnostics.seed(opts.use_workspace_diagnostics == true)

  local function on_init(client, _)
    local ok, nvlsp = pcall(require, "nvchad.configs.lspconfig")
    if ok and type(nvlsp.on_init) == "function" then
      pcall(nvlsp.on_init, client)
    end
    return true
  end

  local function on_attach(client, bufnr)
    if not client or type(client) ~= "table" then
      return
    end
    if not has_valid_buf(bufnr) then
      return
    end
    if not client.server_capabilities then
      return
    end

    -- Deferred on purpose. Calling the plugin's populate directly from here
    -- put a measured 300-420ms stall right after LspAttach -- it shells out
    -- to git and stats the whole repo synchronously. schedule_populate does
    -- the same work off the attach path, without subprocesses, and enforces
    -- a size gate. See lsp.core.workspace_diagnostics' module header.
    if workspace_diagnostics.enabled() then
      workspace_diagnostics.schedule_populate(client, bufnr)
    end

    if opts.use_lazydev and vim.bo[bufnr].filetype == "lua" then
      pcall(require, "lazydev")
    end

    local ok, nvlsp = pcall(require, "nvchad.configs.lspconfig")
    if ok and type(nvlsp.on_attach) == "function" then
      pcall(nvlsp.on_attach, client, bufnr)
    end
  end

  return { on_attach = on_attach, on_init = on_init }
end

return M
