---@module 'lsp.servers.mobiledev.jdtls'
--- Eclipse JDT Language Server for Java (Android development).
--- Requires Java runtime.

local notify = require("lib.nvim.notify").create("[lsp.servers.jdtls]")
local executable = require("lib.nvim.cross.executable")

local M = {}

---Find jdtls installation path
---@return string|nil
local function find_jdtls()
  return executable.mason_bin("jdtls") or executable.path("jdtls")
end

---Check if Java runtime is available
---@return boolean, string|nil
local function is_java_available()
  local java_home = vim.env.JAVA_HOME
  if not java_home or java_home == "" then
    if vim.fn.executable("java") ~= 1 then
      return false, "JAVA_HOME not set and 'java' not in PATH"
    end
  end
  return true, nil
end

---Detect project root for Java projects
---@param fname string
---@return string|nil
local function java_root_dir(fname)
  local markers = {
    "gradlew",
    "build.gradle",
    "build.gradle.kts",
    "pom.xml",
    "settings.gradle",
    "settings.gradle.kts",
    ".git",
  }

  local dir = vim.fs.dirname(fname)
  return vim.fs.root(dir, markers)
end

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  shared = shared or {}
  opts = opts or {}

  -- Check Java availability first
  local java_ok, java_err = is_java_available()
  if not java_ok then
    notify.warn(string.format("Java LSP setup skipped: %s", java_err or "unknown error"))
    return
  end

  local jdtls_cmd = find_jdtls()
  if not jdtls_cmd then
    notify.info("jdtls not found; skipping Java LSP setup")
    return
  end

  if type(vim.lsp.config) ~= "table" then
    return
  end

  local data_dir = vim.fn.stdpath("cache") .. "/jdtls"
  local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:h:t")
  local workspace_dir = data_dir .. "/" .. project_name

  vim.lsp.config("jdtls", {
    cmd = {
      jdtls_cmd,
      "-data",
      workspace_dir,
    },
    filetypes = { "java" },
    root_dir = java_root_dir,
    capabilities = shared.capabilities,
    on_attach = shared.on_attach,
    on_init = shared.on_init,
    settings = {
      java = {
        signatureHelp = { enabled = true },
        contentProvider = { preferred = "fernflower" },
        completion = {
          favoriteStaticMembers = {
            "org.junit.Assert.*",
            "org.junit.Assume.*",
            "org.junit.jupiter.api.Assertions.*",
            "org.junit.jupiter.api.Assumptions.*",
            "org.junit.jupiter.api.DynamicTest.*",
            "org.mockito.Mockito.*",
            "org.mockito.ArgumentMatchers.*",
          },
        },
        sources = {
          organizeImports = {
            starThreshold = 9999,
            staticStarThreshold = 9999,
          },
        },
        codeGeneration = {
          toString = {
            template = "${object.className}{${member.name()}=${member.value}, ${otherMembers}}",
          },
          useBlocks = true,
        },
        configuration = {
          runtimes = {},
        },
      },
    },
  })

  if opts.enable ~= false then
    pcall(vim.lsp.enable, "jdtls")
  end
end

return M
