---@module 'lsp.servers.csharp'
--- Omnisharp via native LSP config/enable (Neovim ≥ 0.11).

local notify = require("lib.nvim.notify").create("[lsp.servers.csharp]")

local lsp = vim.lsp
local executable = vim.fn.executable

---@class CsharpServer
local M = {}

---@return string|nil
local function find_omnisharp()
  -- 1. SYSTEM PATH CHECK
  if executable("omnisharp") == 1 then
    return "omnisharp"
  end

  -- Hilfsfunktion für absolute Pfadprüfungen (zuverlässiger als executable() bei WSL/Skripten)
  local function file_exists(path)
    local stat = (vim.uv or vim.loop).fs_stat(path)
    return stat and stat.type == "file" or false
  end

  -- Standard-Datenpfad auflösen
  local data_path = vim.fn.stdpath("data")

  -- 2. MASON BIN FALLBACK (Der Standard-Wrapper)
  -- Unter WSL/Linux ist das oft ein Shell-Skript ohne Endung
  local mason_bin_linux = data_path .. "/mason/bin/omnisharp"
  local mason_bin_windows = data_path .. "/mason/bin/omnisharp.CMD"

  if file_exists(mason_bin_linux) then
    return mason_bin_linux
  elseif file_exists(mason_bin_windows) then
    return mason_bin_windows
  end

  -- 3. MASON PACKAGES FALLBACK (Direkter Zugriff auf die Assembly)
  -- Mason entpackt OmniSharp unter Linux tief in diesen Unterordner:
  local mason_pkg_run = data_path .. "/mason/packages/omnisharp/OmniSharp"
  -- Falls es die standalone Version ist (manchmal auch kleingeschrieben):
  local mason_pkg_run_cmd = data_path .. "/mason/packages/omnisharp/omnisharp"

  if file_exists(mason_pkg_run) then
    return mason_pkg_run
  elseif file_exists(mason_pkg_run_cmd) then
    return mason_pkg_run_cmd
  end

  notify.warn("C#: omnisharp not found in PATH or Mason")
  return nil
end

---@param shared {capabilities?:table,on_attach?:fun(client,bufnr),on_init?:fun(client,init_result):boolean}|nil
---@param opts { enable?: boolean }|nil
---@return nil
function M.setup(shared, opts)
  -- notify.info("🔧 C# Setup: Starting...") -- DEBUG

  shared = shared or {}
  opts = opts or {}

  local cmd = find_omnisharp()
  if not cmd then
    notify.warn("C#: Omnisharp not found; skipping LSP")
    return
  end

  -- notify.info("🔧 C# Setup: Found cmd = " .. cmd) -- DEBUG

  -- Define config
  if type(lsp.config) == "table" then
    -- notify.info("🔧 C# Setup: lsp.config available") -- DEBUG

    local config_ok, config_err = pcall(function()
      lsp.config("omnisharp", {
        cmd = { cmd },
        filetypes = { "cs" },
        capabilities = shared.capabilities,
        on_attach = shared.on_attach,
        on_init = shared.on_init,
        enable_roslyn_analyzers = true,
        organize_imports_on_format = true,
        root_markers = { ".git", ".sln", ".csproj" },
      })
    end)

    if not config_ok then
      notify.error("🔧 C# Setup: Config failed: " .. tostring(config_err))
      return
    end

    -- notify.info("🔧 C# Setup: Config registered") -- DEBUG

    if opts.enable ~= false then
      local enable_ok, enable_err = pcall(lsp.enable, "omnisharp")
      if not enable_ok then
        notify.error("🔧 C# Setup: Enable failed: " .. tostring(enable_err))
      else
        -- notify.info("🔧 C# Setup: LSP enabled ✓") -- DEBUG
      end
    end
  else
    notify.error("🔧 C# Setup: lsp.config NOT available!")
  end
end
return M
