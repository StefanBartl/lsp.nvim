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

---@internal
--- Project markers for a Java project, in priority order.
---
--- These used to be wrapped in a `root_dir = function(fname)` -- the
--- *lspconfig* contract. The native `vim.lsp` pipeline calls
--- `root_dir(bufnr, on_dir)` instead (see |lsp-root_dir()| and
--- `lsp_enable_callback()` in `vim/lsp.lua`), so the buffer number arrived
--- where a filename was expected and `vim.fs.dirname()` raised. Measured by
--- opening a `.java` buffer with jdtls enabled:
---
---     FileType Autocommands for "*": Vim(append):Lua callback:
---     vim/fs.lua:89: file: expected string, got number
---     ... jdtls.lua:42: in function 'root_dir'
---     ... vim/lsp.lua:550: in function 'lsp_enable_callback'
---
--- and afterwards `#vim.lsp.get_clients{ name = "jdtls" } == 0`. The raise
--- happens inside the FileType autocmd, so it aborted `:edit` itself -- every
--- Java file opened with an error and no language server. Even without the
--- raise the wrapper could not have worked: the native contract wants
--- `on_dir(root)` *called*, and a returned string is discarded.
---
--- A plain `root_markers` list is what every sibling module here uses and has
--- the same semantics the wrapper was reaching for -- `vim.fs.root()` walks the
--- markers in order and takes the first that resolves upward -- with none of
--- the signature to get wrong.
---@type string[]
local java_root_markers = {
  "gradlew",
  "build.gradle",
  "build.gradle.kts",
  "pom.xml",
  "settings.gradle",
  "settings.gradle.kts",
  ".git",
}

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
    root_markers = java_root_markers,
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
