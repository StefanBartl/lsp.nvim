---@module 'lsp.servers.mobiledev.dartls'
--- Dart Analysis Server for Flutter development.

local notify = require("lib.nvim.notify").create("[lsp.servers.dartls]")

local M = {}

---Find Flutter SDK path
---@return string|nil
local function find_flutter_sdk()
  local flutter_bin = vim.fn.exepath("flutter")
  if flutter_bin ~= "" then
    local sdk = vim.fn.fnamemodify(flutter_bin, ":h:h")
    return sdk
  end
  return vim.env.FLUTTER_ROOT or vim.env.FLUTTER_SDK
end

---Check if dart executable is available
---@return boolean
local function is_dart_available()
  return vim.fn.executable("dart") == 1
end

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  shared = shared or {}
  opts = opts or {}

  -- Early exit if dart is not available
  if not is_dart_available() then
    notify.info("dart executable not found; skipping Dart LSP setup")
    return
  end

  local flutter_sdk = find_flutter_sdk()

  if type(vim.lsp.config) ~= "table" then
    return
  end

  vim.lsp.config("dartls", {
    cmd = { "dart", "language-server", "--protocol=lsp" },
    filetypes = { "dart" },
    root_markers = { "pubspec.yaml", ".git" },
    capabilities = shared.capabilities,
    on_attach = shared.on_attach,
    on_init = function(client, init_result)
      if flutter_sdk then
        client.config.settings = vim.tbl_deep_extend("force", client.config.settings or {}, {
          dart = {
            sdkPath = flutter_sdk .. "/bin/cache/dart-sdk",
            flutterSdkPath = flutter_sdk,
            analysisExcludedFolders = {
              flutter_sdk .. "/packages",
            },
          },
        })
      end

      if type(shared.on_init) == "function" then
        return shared.on_init(client, init_result)
      end
      return true
    end,
    settings = {
      dart = {
        enableSdkFormatter = true,
        lineLength = 120,
        completeFunctionCalls = true,
        showTodos = true,
      },
    },
  })

  if opts.enable ~= false then
    pcall(vim.lsp.enable, "dartls")
  end
end

return M
