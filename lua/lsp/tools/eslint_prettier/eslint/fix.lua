---@module 'lsp.tools.eslint_prettier.eslint.fix'
--- Run eslint_d --fix on current file (uses resolved bin)
local notify = require("lib.nvim.notify").create("[lsp.tools.eslint_prettier.eslint.fix]")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

local api = vim.api
local eslint = require("lsp.tools.eslint_prettier.eslint")

local M = {}

---@param text string
---@return string[] non-empty lines
local function non_empty_lines(text)
  local out = {}
  for _, l in ipairs(vim.split(text, "\n", { plain = true })) do
    if l ~= "" then
      out[#out + 1] = l
    end
  end
  return out
end

--- run async command and collect stdout/stderr
---@param argv string[] list of command + args
---@param opts table|nil
local function run_cmd_collect(argv, opts)
  opts = opts or {}
  spawn_capture(argv, { cwd = opts.cwd }, function(result)
    if opts.on_exit then
      opts.on_exit(result.code, non_empty_lines(result.stdout), non_empty_lines(result.stderr))
    end
  end)
end

---@param bufnr number|nil
function M.eslint_fix(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local filename = api.nvim_buf_get_name(bufnr)
  if filename == "" then
    notify.warn("No file to lint")
    return
  end

  local bin = eslint.get_eslint_bin()
  if not bin then
    notify.error("eslint_d not found (PATH or mason).")
    return
  end

  -- Write buffer before running eslint
  if api.nvim_get_option_value("modified", { buf = bufnr }) then
    api.nvim_buf_call(bufnr, function()
      vim.cmd("write!")
    end)
  end

  -- Ermittle Projekt-Root und setze als cwd
  local find_root = require("lsp.tools.eslint_prettier.core.find_root")
  local root = find_root(bufnr)
  if not root then
    notify.warn("Could not determine project root, using current directory.")
    root = vim.fn.getcwd()
  end

  local args = { bin, "--fix", filename }

  -- Sammle stdout/stderr, setze cwd auf Projekt-Root
  run_cmd_collect(args, {
    cwd = root,
    on_exit = function(code, stdout, stderr)
      if code == 0 then
        vim.cmd("checktime") -- Refresh buffer
        notify.info("eslint_d: fixed")
      else
        local msg = {}

        if stdout and #stdout > 0 then
          table.insert(msg, "[stdout]")
          vim.list_extend(msg, stdout)
        end

        if stderr and #stderr > 0 then
          table.insert(msg, "[stderr]")
          vim.list_extend(msg, stderr)
        end

        if #msg == 0 then
          table.insert(msg, "eslint_d returned non-zero exit code, but no output captured.")
        end

        notify.error(table.concat(msg, "\n"))
      end
    end,
  })
end

return M
