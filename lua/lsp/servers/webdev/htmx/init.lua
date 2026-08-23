---@module 'lsp.servers.webdev.htmx'
--- HTMX Language Server für HTMX-Attribute

local notify = require("lib.nvim.notify").create("[lsp.servers.webdev.htmx_lsp]")
local executable = require("lib.nvim.cross.executable")

local M = {}

---Find htmx-lsp executable
---@return string|nil
local function find_htmx_lsp()
  return executable.path("htmx-lsp") or executable.mason_bin("htmx-lsp")
end

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean, filter_stderr?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  shared = shared or {}
  opts = opts or {}

  if type(vim.lsp.config) ~= "table" then
    return
  end

  local htmx_cmd = find_htmx_lsp()
  if not htmx_cmd then
    notify.info("htmx-lsp not found; skipping HTMX LSP setup")
    return
  end

  -- OPTIONAL: Filter INFO-Logs aus stderr
  -- htmx-lsp schreibt JSON-Logs auf stderr, die Neovim als [ERROR] loggt
  ---@diagnostic disable-next-line: unused-local
  local handlers = {}
  if opts.filter_stderr ~= false then
    local ok, stderr_filter = pcall(require, "lsp.servers.webdev.htmx.filter_logs") -- FIX: Filtering funktionert nicht
    if ok and type(stderr_filter.create_json_filter) == "function" then
      -- Use JSON filter to ignore INFO/DEBUG logs
      ---@diagnostic disable-next-line: unused-local
      handlers["stderr"] = stderr_filter.create_json_filter("htmx-lsp")
    end
  end

  vim.lsp.config("htmx", {
    cmd = { htmx_cmd },
    filetypes = { "html", "astro", "htmldjango", "eruby" },
    root_markers = { ".git", "package.json" },
    capabilities = shared.capabilities,
    on_attach = shared.on_attach,
    on_init = shared.on_init,
    -- handlers = handlers,  -- Uncomment to enable stderr filtering
  })

  if opts.enable ~= false then
    pcall(vim.lsp.enable, "htmx")
  end
end

return M
