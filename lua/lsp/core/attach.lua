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

--- Build the on_attach/on_init pair every server is set up with.
---
--- `opts.hooks` is how third-party behaviour gets in. This module used to
--- `pcall(require, ...)` lazydev and NvChad inline; both now live in
--- `lsp.integrations.*` and are handed over as plain functions by `lsp.init`,
--- so the core does not know which plugins exist (roadmap section 3).
---@param opts { use_workspace_diagnostics?: boolean, hooks?: { on_attach?: function[], on_init?: function[] } }|nil
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

  local hooks = opts.hooks or {}

  local function on_init(client, _)
    for _, hook in ipairs(hooks.on_init or {}) do
      pcall(hook, client)
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

    for _, hook in ipairs(hooks.on_attach or {}) do
      pcall(hook, client, bufnr)
    end
  end

  return { on_attach = on_attach, on_init = on_init }
end

return M
