---@module 'lsp.servers.mobiledev.sourcekit'
--- SourceKit-LSP for Swift and iOS development.
--- macOS only - gracefully skips on other platforms.

local notify = require("lib.nvim.notify").create("[lsp.servers.sourcekit]")

local M = {}

---Check if sourcekit-lsp is available (macOS only)
---@return boolean
local function is_sourcekit_available()
  if not (vim.loop or vim.uv).os_uname().sysname == "Darwin" then
    return false
  end
  return vim.fn.executable("sourcekit-lsp") == 1
end

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  shared = shared or {}
  opts = opts or {}

  -- Early exit if not macOS or sourcekit-lsp not available
  if not is_sourcekit_available() then
    notify.info("sourcekit-lsp not available (macOS only); skipping Swift LSP setup")
    return
  end

  if type(vim.lsp.config) ~= "table" then
    return
  end

  vim.lsp.config("sourcekit", {
    cmd = { "sourcekit-lsp" },
    filetypes = { "swift", "objective-c", "objective-cpp" },
    root_markers = {
      "Package.swift",
      ".git",
      "compile_commands.json",
    },
    capabilities = shared.capabilities,
    on_attach = shared.on_attach,
    on_init = shared.on_init,
  })

  if opts.enable ~= false then
    pcall(vim.lsp.enable, "sourcekit")
  end
end

return M
