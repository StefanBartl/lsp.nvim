---@module 'lsp.tools.eslint_prettier.prettier.format'
--- Runs prettier as a subprocess (`spawn_capture`) and collects its stdout as
--- non-empty lines -- the actual formatting call `prettier/init.lua`'s
--- resolved binary is used for.
local notify = require("lib.nvim.notify").create("[lsp.tools.eslint_prettier.prettier.format]")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

local api = vim.api
local run = require("lsp.tools.eslint_prettier.prettier")

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

---@param argv string[]
---@param opts { cwd: string?, on_exit: (fun(code: integer, stdout: string[], stderr: string[]))? }|nil
local function run_cmd_collect(argv, opts)
  opts = opts or {}
  spawn_capture(argv, { cwd = opts.cwd }, function(result)
    if opts.on_exit then
      opts.on_exit(result.code, non_empty_lines(result.stdout), non_empty_lines(result.stderr))
    end
  end)
end

---@param bufnr number|nil
function M.prettier_format(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local filename = api.nvim_buf_get_name(bufnr)
  if filename == "" then
    notify.warn("No file to format")
    return
  end

  local bin = run.get_prettier_bin()
  if not bin then
    notify.error("prettier not found (PATH or mason).")
    return
  end

  if api.nvim_get_option_value("modified", { buf = bufnr }) then
    api.nvim_buf_call(bufnr, function()
      vim.cmd("write!")
    end)
  end

  local args = { bin, "--write", filename }
  run_cmd_collect(args, {
    on_exit = function(code, _, err)
      if code == 0 then
        vim.cmd("checktime")
        notify.info("prettier: formatted")
      else
        notify.warn("prettier failed:\n" .. table.concat(err, "\n"))
      end
    end,
  })
end

return M
