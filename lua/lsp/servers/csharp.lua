---@module 'lsp.servers.csharp'
--- Omnisharp via native LSP config/enable (Neovim ≥ 0.11).

local notify = require("lib.nvim.notify").create("[lsp.servers.csharp]")

local lsp = vim.lsp

---@class CsharpServer
local M = {}

---@return string|nil
local function find_omnisharp()
  -- 1. SYSTEM PATH CHECK
  if vim.fn.executable("omnisharp") == 1 then
    return "omnisharp"
  end

  -- Absolute-path check, rather than `executable()`: under WSL, and for
  -- script wrappers, `executable()` answers about the wrong thing.
  local function file_exists(path)
    local stat = (vim.uv or vim.loop).fs_stat(path)
    return stat and stat.type == "file" or false
  end

  local data_path = vim.fn.stdpath("data")

  -- 2. MASON BIN FALLBACK (the standard wrapper)
  -- On WSL/Linux this is usually a shell script with no extension.
  local mason_bin_linux = data_path .. "/mason/bin/omnisharp"
  local mason_bin_windows = data_path .. "/mason/bin/omnisharp.CMD"

  if file_exists(mason_bin_linux) then
    return mason_bin_linux
  elseif file_exists(mason_bin_windows) then
    return mason_bin_windows
  end

  -- 3. MASON PACKAGES FALLBACK (the assembly directly)
  -- On Linux, Mason unpacks OmniSharp deep into this subdirectory:
  local mason_pkg_run = data_path .. "/mason/packages/omnisharp/OmniSharp"
  -- The standalone build, whose binary is sometimes lowercased:
  local mason_pkg_run_cmd = data_path .. "/mason/packages/omnisharp/omnisharp"

  if file_exists(mason_pkg_run) then
    return mason_pkg_run
  elseif file_exists(mason_pkg_run_cmd) then
    return mason_pkg_run_cmd
  end

  return nil
end

---@internal
--- Resolve a C# project root, to the native `root_dir` contract.
---
--- This replaces `root_markers = { ".git", ".sln", ".csproj" }`. Those two
--- dotted entries look like extensions but `root_markers` entries are *file
--- names*: `vim.fs.root()` hands each one to `vim.fs.find()`, which stats
--- `<dir>/<name>` literally (`vim/fs.lua`, the non-function branch of
--- `test`). Measured against a tree holding `App.sln` and `App.csproj`:
---
---     vim.fs.root(".../proj/src/Q.cs", { "App.sln" })         -> .../proj
---     vim.fs.root(".../proj/src/Q.cs", { ".sln", ".csproj" }) -> nil
---     vim.fs.root(".../proj/src/Q.cs", { "*.sln", "*.csproj" })-> nil
---
--- So a C# project root only ever came from `.git`, and a solution checked out
--- inside a larger repository got that repository as its root. Globbing is not
--- available through `root_markers` at all -- `vim.fs.find` only takes a
--- predicate for that -- which is why this is a `root_dir` function.
---
--- `on_dir` is called, never returned: the native pipeline passes a callback
--- and discards the return value (|lsp-root_dir()|). Not calling it is how a
--- config declines to start, which is what an unnamed buffer gets.
---@param bufnr integer
---@param on_dir fun(root_dir?: string)
---@return nil
local function csharp_root_dir(bufnr, on_dir)
  local fname = vim.api.nvim_buf_get_name(bufnr)
  if fname == "" then
    return
  end

  local dir = vim.fs.dirname(fname)
  local found = vim.fs.find(function(name)
    return name:match("%.sln$") ~= nil or name:match("%.csproj$") ~= nil
  end, { upward = true, path = dir, limit = 1 })

  local root = found[1] and vim.fs.dirname(found[1]) or vim.fs.root(dir, { ".git" })
  if root then
    on_dir(root)
  end
end

--- The resolved binary: `nil` until looked up, `false` once looked up and absent.
---@type string|false|nil
local resolved = nil

---@internal
--- Look the binary up on first use, and only once.
---
--- `vim.fn.executable("omnisharp")` walks every `PATH` entry (and `PATHEXT` on
--- Windows) and costs ~100 ms on a long `PATH` when the name is absent -- far
--- more than every other server's whole `setup()`. Doing it in `setup()` charged
--- that to every start, C# project or not (LUA-92), so it runs when the first C#
--- buffer asks for a root instead.
---@return string|nil cmd
local function resolve()
  if resolved == nil then
    resolved = find_omnisharp() or false
    if not resolved then
      notify.warn("C#: Omnisharp not found; skipping LSP")
    end
  end
  return resolved or nil
end

---@internal
--- Forget the lookup (tests, and a user who installed the server meanwhile).
---@return nil
function M._reset()
  resolved = nil
end

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  shared = shared or {}
  opts = opts or {}

  -- Define config
  if type(lsp.config) == "table" then
    local config_ok, config_err = pcall(function()
      lsp.config("omnisharp", {
        -- A function, so the binary is looked up when a client starts rather
        -- than here; `root_dir` runs first and declines when it is absent.
        cmd = function(dispatchers, config)
          return vim.lsp.rpc.start({ resolve() }, dispatchers, {
            cwd = config.cmd_cwd,
            env = config.cmd_env,
            detached = config.detached,
          })
        end,
        filetypes = { "cs" },
        capabilities = shared.capabilities,
        on_attach = shared.on_attach,
        on_init = shared.on_init,
        enable_roslyn_analyzers = true,
        organize_imports_on_format = true,
        root_dir = function(bufnr, on_dir)
          if resolve() then
            csharp_root_dir(bufnr, on_dir)
          end
        end,
      })
    end)

    if not config_ok then
      notify.error("🔧 C# Setup: Config failed: " .. tostring(config_err))
      return
    end

    if opts.enable ~= false then
      local enable_ok, enable_err = pcall(lsp.enable, "omnisharp")
      if not enable_ok then
        notify.error("🔧 C# Setup: Enable failed: " .. tostring(enable_err))
      end
    end
  else
    notify.error("🔧 C# Setup: lsp.config NOT available!")
  end
end
return M
