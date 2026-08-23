---@module 'lsp.servers.lua_ls'
--- Lua language server setup using native LSP config/enable with strict root and scoped libraries.

local notify = require("lib.nvim.notify").create("[lsp.servers.lua_ls]")

local M = {}

-- Import required dependencies for ignore patterns and root resolution
local ignore = require("lsp.servers.lua_ls.ignore")
local root_resolver = require("lsp.servers.lua_ls.rootresolver")
local library_profiles = require("lsp.servers.lua_ls.library_profiles")

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean,  profile?: LibraryProfile }|nil
---@return nil
function M.setup(shared, opts)
  -- Ensure shared and opts are tables, even if nil was passed
  shared = shared or {}
  opts = opts or {}

  -- Only proceed if Neovim's native LSP config API is available (Neovim 0.10+)
  if type(vim.lsp.config) == "table" then
    -- Register the lua_ls server configuration
    vim.lsp.config("lua_ls", {
      -- Command to launch the language server executable
      cmd = { "lua-language-server" },

      -- File types this server should attach to
      filetypes = { "lua" },

      -- Use our custom root directory resolver. NOTE: pass the resolver
      -- function itself, not its result — vim.lsp calls it per-buffer as
      -- root_dir(bufnr, cb). Calling it here would freeze root_dir to a
      -- single string computed once at setup time.
      root_dir = root_resolver,

      -- Allow the server to run even without a detected project root
      single_file_support = true,

      -- Pass through shared LSP capabilities (e.g., from cmp-nvim-lsp)
      capabilities = shared.capabilities,

      -- Pass through custom attach handler
      on_attach = function(client, bufnr)
        -- Wrap client to catch malformed requests
        local ok_err, err_handler = pcall(require, "lsp.servers.lua_ls.error_handler")
        if ok_err and type(err_handler.wrap_client) == "function" then
          pcall(err_handler.wrap_client, client)
        end

        if type(shared.on_attach) == "function" then
          shared.on_attach(client, bufnr)
        end
      end,

      -- Attach the workspace library before the initialize request goes out.
      --
      -- This used to live in `on_new_config` below, which never ran: that is
      -- an lspconfig hook, and this server is registered through the native
      -- `vim.lsp.config`, which knows nothing about it. Verified on a running
      -- client -- `client.config.settings.Lua.workspace.library` was nil, so
      -- lua_ls had no Neovim runtime types at all, and `LUA_LS_PROFILE` had
      -- no effect (which is the real reason the `minimal` A/B in
      -- docs/ROADMAP/PERF-Startup-Analyse.md changed nothing).
      ---@param _params table
      ---@param config table
      before_init = function(_params, config)
        local library = library_profiles.build_runtime_library()

        config.settings = config.settings or {}
        config.settings.Lua = config.settings.Lua or {}
        config.settings.Lua.workspace = config.settings.Lua.workspace or {}
        config.settings.Lua.workspace.library = library
      end,

      -- Pass through initialization handler
      on_init = shared.on_init,

      -- Language server specific settings
      settings = {
        Lua = {
          -- Configure Lua runtime environment
          runtime = {
            version = "LuaJIT",
            path = {
              "?.lua",
              "?/init.lua",
            },
            pathStrict = false,
          },

          -- Enable inlay hints for better code insight
          hint = { enable = true },

          -- Configure diagnostics and recognized globals
          diagnostics = {
            globals = {
              -- Neovim API globals
              "vim",
              "vim.uv",
              "vim.loop",
              "vim.fn",
              "vim.api",
              "vim.cmd",
              "vim.o",
              "vim.g",
              "vim.bo",
              "vim.wo",
              "vim.env",
              "vim.log",
              "vim.lsp",
              "vim.inspect",

              -- Testing framework globals (busted/plenary)
              "describe",
              "it",
              "before_each",
              "after_each",
              "setup",
              "teardown",
              "assert",
              "spy",
              "stub",
              "mock",
            },
          },

          -- Erweiterte Completion-Einstellungen
          completion = {
            callSnippet = "Both", -- Zeige Funktion + Signatur
            displayContext = 10, -- Mehr Kontext-Zeilen
            showWord = "Fallback",
            workspaceWord = true,
            keywordSnippet = "Both", -- Zeige Keyword-Snippets
          },

          -- Erweiterte Hover-Informationen
          hover = {
            enable = true,
            viewString = true, -- Zeige String-Werte
            viewStringMax = 1000, -- Maximale String-Länge
            viewNumber = true, -- Zeige Zahlen-Werte
            fieldInfer = 10000, -- Feld-Inferenz-Limit
            previewFields = 50, -- Anzahl Preview-Felder
            enumsLimit = 100, -- Enum-Limit
          },

          -- Wichtig: Signatur-Hilfe aktivieren
          signatureHelp = {
            enable = true,
          },

          -- Disable semantic token highlighting (use TreeSitter instead)
          semantic = { enable = false },

          -- Workspace scanning and library configuration
          workspace = {
            checkThirdParty = true, -- Check for third-party libraries

            -- Use our centralized ignore patterns to skip noisy directories
            ignoreDir = ignore.as_luals_patterns(),

            -- Respect .gitignore files
            useGitIgnore = true,

            -- Limit workspace scanning to prevent performance issues
            -- maxPreload = 3000, -- Maximum number of files to preload
            -- preloadFileSize = 500, -- Maximum file size in KB

            maxPreload = 2000,
            preloadFileSize = 500,

            -- library will be populated dynamically per root in on_new_config
          },

          -- Disable telemetry
          telemetry = { enable = false },
        },
      },

      -- NOTE: there is deliberately no `on_new_config` here any more. It is an
      -- lspconfig concept; `vim.lsp.config` never calls it, so the version
      -- that used to sit here (building a per-root library via
      -- `library_profiles.build_library`) was dead code. The library is set in
      -- `before_init` above instead.
    })

    -- Automatically enable the server unless explicitly disabled
    if (opts or {}).enable ~= false then
      -- Use pcall to prevent errors if vim.lsp.enable is not available
      pcall(vim.lsp.enable, "lua_ls")
    end
  end

  require("lsp.servers.lua_ls.reload").setup()
end

---@class LuaLsServer
return M
