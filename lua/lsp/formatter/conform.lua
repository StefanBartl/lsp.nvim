---@module 'lsp.formatter.conform'
--- Conform setup and utilities.
--- Adds a helper to format while preserving all window views that display the buffer.
--- Linux/macOS focused; works when Conform is available.

local notify = require("lib.nvim.notify").create("[lsp.formatter.conform]")
local sys_env = require("lib.nvim.system.env")

local api = vim.api
local fn = vim.fn
local env = vim.env
local uv = vim.uv or vim.loop

---@class ConformPolicy
local M = {}

-- Add mason/bin to PATH defensively (works even if mason isn't loaded yet)
-- Keeps the user's PATH untouched beyond prepending a single path once.
local function ensure_mason_in_path()
  local sep = sys_env.get().is_windows and ";" or ":"
  local mason_bin = fn.stdpath("data") .. "/mason/bin"
  local PATH = env.PATH or ""
  if not string.find(PATH, mason_bin, 1, true) then
    env.PATH = mason_bin .. sep .. PATH
  end
end

-- Resolve an executable across common install locations (pipx, mason, pyenv, Windows)
-- Keeps the original behavior; prefer linux/macOS paths but does not break on Windows.
---@param cmd string
---@return string
local function resolve(cmd)
  local exepath = fn.exepath(cmd)
  if exepath ~= nil and exepath ~= "" then
    return exepath
  end
  local home = (uv.os_homedir and uv.os_homedir())
    or os.getenv("HOME")
    or os.getenv("USERPROFILE")
    or ""
  ---@type string[]
  local candidates = {
    fn.stdpath("data") .. "/mason/bin/" .. cmd .. (sys_env.get().is_windows and ".cmd" or ""),
    home .. "/.local/bin/" .. cmd,
    home .. "/.pyenv/shims/" .. cmd,
    home .. "/AppData/Roaming/Python/Scripts/" .. cmd .. ".exe",
  }
  for i = 1, #candidates do
    local p = candidates[i]
    if
      type(p) == "string"
      and p ~= ""
      and ((uv.fs_stat and uv.fs_stat(p)) or fn.filereadable(p) == 1)
    then
      return p
    end
  end
  return cmd -- fallback; conform/exepath will try again
end

-- Collect per-window views for all windows currently showing bufnr.
---@param bufnr integer
---@return table<integer, table> views_by_win
local function collect_views(bufnr)
  local views = {} ---@type table<integer, table>
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      -- winsaveview() is per-current-window; use nvim_win_call to scope it.
      local ok, view = pcall(api.nvim_win_call, win, function()
        return fn.winsaveview()
      end)
      if ok and type(view) == "table" then
        views[win] = view
      end
    end
  end
  return views
end

-- Restore all previously collected views if windows are still valid.
---@param views_by_win table<integer, table>
---@return nil
local function restore_views(views_by_win)
  for win, view in pairs(views_by_win) do
    if api.nvim_win_is_valid(win) then
      pcall(api.nvim_win_call, win, function()
        pcall(fn.winrestview, view)
      end)
    end
  end
end

-- Public helper: Format with Conform while preserving all window views.
-- Synchronous formatting is used to avoid race conditions with subsequent write.
---@param bufnr integer|nil
---@param opts table|nil
---@return boolean
function M.format_preserve_view(bufnr, opts)
  bufnr = bufnr or 0
  local ok_conform, conform = pcall(require, "conform")
  if not ok_conform or type(conform.format) ~= "function" then
    return false
  end
  if vim.bo[bufnr].buftype ~= "" then
    return false
  end
  local views = collect_views(bufnr)
  -- Force synchronous run; after edits, restore views deterministically.
  local ok = pcall(
    conform.format,
    vim.tbl_extend("force", {
      bufnr = bufnr,
      async = false, -- critical for deterministic restore
      timeout_ms = 1200,
      lsp_fallback = true,
    }, opts or {})
  )
  restore_views(views)
  return ok == true
end

---@return nil
function M.setup()
  local ok, conform = pcall(require, "conform")
  if not ok then
    return
  end

  ensure_mason_in_path()

  conform.setup({
    formatters_by_ft = {
      lua = { "stylua" },
      --   go = { "goimports", "gofmt" },
      javascript = { "prettierd", "prettier" },
      typescript = { "prettierd", "prettier" },
      typescriptreact = { "prettierd", "prettier" },
      javascriptreact = { "prettierd", "prettier" },
      json = { "jq" },
      css = { "prettierd", "prettier" },
      html = { "prettierd", "prettier" },
      --  zig = { "zigfmt" },
      --  c = { "clang_format" },
      --  cpp = { "clang_format" },
      cs = { "csharpier" },
      markdown = { "mdformat", "prettierd", "prettier" },
      sh = { "shfmt", "shellharden" }, -- shfmt first (idempotent), shellharden optional
      bash = { "shfmt", "shellharden" },
      zsh = { "shfmt" }, -- shellharden may warn on zsh-isms; keep optional
      -- ksh = { "shfmt" },
    },

    -- Explicit commands so Conform can find the executables reliably
    formatters = {
      mdformat = {
        command = resolve("mdformat"),
        args = { "-" },
        stdin = true,
        env = { PYTHONIOENCODING = "utf-8", PYTHONUTF8 = "1" },
      },
      prettierd = {
        command = resolve("prettierd"),
      },
      prettier = {
        command = resolve("prettier"),
        prepend_args = { "--stdin-filepath", "$FILENAME" },
      },

      shfmt = {
        command = resolve("shfmt"),
        -- -i 2 (indent=2), -ci (switch-case indent), -sr (space redirect), -bn (binary ops on new line)
        args = { "-i", "2", "-ci", "-sr", "-bn" },
        stdin = true,
      },
      shellharden = {
        command = resolve("shellharden"),
        -- Reads stdin and writes stdout; acts as a safe rewriter/formatter
        args = { "--transform", "-" },
        stdin = true,
      },
    },

    notify_on_error = true,
  })
end

-- Small helper to show which formatter chain is configured & available for current buffer
---@param bufnr integer|nil
---@return nil
function M.which(bufnr)
  bufnr = bufnr or 0
  local ft = vim.bo[bufnr].filetype
  ---@type string[]
  local chain = (ft == "markdown") and { "mdformat", "prettierd", "prettier" }
    or (ft == "markdown.mdx") and { "prettierd", "prettier" }
    or {}
  if #chain == 0 then
    notify.info("No formatter chain known for filetype=" .. tostring(ft))
    return
  end
  local lines = { "Formatters for filetype=" .. ft .. ":" }
  for i = 1, #chain do
    local name = chain[i]
    local cmd = (name == "mdformat" and resolve("mdformat"))
      or (name == "prettierd" and resolve("prettierd"))
      or resolve("prettier")
    local found = fn.exepath(cmd) or ""
    local ok = (found ~= "")
    lines[#lines + 1] = string.format(
      " - %s: %s%s",
      name,
      (ok and found or cmd),
      ok and " (available)" or " (NOT FOUND)"
    )
  end
  notify.info(table.concat(lines, "\n"))
end

return M
