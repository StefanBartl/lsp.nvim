---@module 'lsp.servers.mobiledev.kotlin_language_server'
--- Kotlin Language Server for Android development.
--- Requires JAVA_HOME to be set.

local notify = require("lib.nvim.notify").create("[lsp.servers.kotlin_language_server]")

local M = {}

---Check if kotlin-language-server and Java are available
---@return boolean, string|nil
local function is_kotlin_available()
  if vim.fn.executable("kotlin-language-server") ~= 1 then
    return false, "kotlin-language-server not found"
  end

  local java_home = vim.env.JAVA_HOME
  if not java_home or java_home == "" then
    if vim.fn.executable("java") ~= 1 then
      return false, "JAVA_HOME not set and 'java' not in PATH"
    end
  end

  return true, nil
end

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  shared = shared or {}
  opts = opts or {}

  -- Early exit if requirements not met
  local available, err = is_kotlin_available()
  if not available then
    notify.warn(string.format("Kotlin LSP setup skipped: %s", err or "unknown error"))
    return
  end

  if type(vim.lsp.config) ~= "table" then
    return
  end

  vim.lsp.config("kotlin_language_server", {
    cmd = { "kotlin-language-server" },
    filetypes = { "kotlin" },
    root_markers = {
      "settings.gradle",
      "settings.gradle.kts",
      "build.gradle",
      "build.gradle.kts",
      ".git",
    },
    capabilities = shared.capabilities,
    on_attach = shared.on_attach,
    on_init = shared.on_init,
    settings = {
      kotlin = {
        compiler = {
          jvm = {
            target = "1.8",
          },
        },
      },
    },
  })

  if opts.enable ~= false then
    pcall(vim.lsp.enable, "kotlin_language_server")
  end
end

return M
