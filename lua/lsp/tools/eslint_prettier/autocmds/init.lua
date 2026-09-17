---@module 'lsp.tools.eslint_prettier.autocmds'
--- Attach autocmds (BufWritePost) for lint+format with toggle support.
local api = vim.api
local core = require("lsp.tools.eslint_prettier.core.find_root")
local check = require("lsp.tools.eslint_prettier.core.check_config")
local eslint_fix = require("lsp.tools.eslint_prettier.eslint.fix")
local prettier_fmt = require("lsp.tools.eslint_prettier.prettier.format")
local Autocmd = require("lib.nvim.bindings.autocmd")

local M = {}

---@param ctx table plugin context with fields: filetypes (string[]), _enabled (bool)
function M.attach(ctx)
  ctx = ctx or {}
  local filetypes = ctx.filetypes
    or { "javascript", "javascriptreact", "typescript", "typescriptreact", "vue", "svelte" }
  local group = api.nvim_create_augroup("MasonEslintPrettier", { clear = true })

  -- `BufWritePost`, not `BufWritePre`. Both tools read and rewrite the file on
  -- disk, so starting them *before* Neovim's own write means the child and the
  -- editor hold the same path open at the same time. On Windows that is not a
  -- race one of them wins -- it is a sharing violation. Measured on a 25.8 MB
  -- buffer, where Neovim's write takes long enough for the child to get there
  -- first: `:w` took 233 ms and the formatter died with "Der Prozess kann
  -- nicht auf die Datei zugreifen, da sie von einem anderen Prozess verwendet
  -- wird", leaving the file unformatted and a failure notification on screen.
  -- At 3.7 MB the child simply lost the race and the save looked fine, which
  -- is why this only shows up on big files.
  --
  -- Post also removes the reason `eslint_fix`/`prettier_format` had to write
  -- the buffer themselves on this path: by the time it fires, the file on disk
  -- is the buffer, which is exactly what the formatters need.
  Autocmd.create("BufWritePost", function(ev)
    if not ctx._enabled then
      return
    end
    local ft = api.nvim_get_option_value("filetype", { buf = ev.buf })
    local allowed = false
    for _, v in ipairs(filetypes) do
      if v == ft then
        allowed = true
        break
      end
    end
    if not allowed then
      return
    end

    local root = core(ev.buf)
    -- run only if the respective config exists, and prettier only once eslint
    -- has exited: both rewrite the same path, so started together the slower
    -- one's write is what survives and the other's is lost. Measured on a
    -- stubbed pair -- prettier done at ~0.1 s, eslint at ~2 s -- the file held
    -- eslint's output alone.
    local function format()
      if check.has_prettier(root) then
        prettier_fmt.prettier_format(ev.buf)
      end
    end
    if check.has_eslint(root) then
      eslint_fix.eslint_fix(ev.buf, format)
    else
      format()
    end
  end, {
    group = group,
    pattern = { "*.js", "*.cjs", "*.mjs", "*.jsx", "*.ts", "*.tsx", "*.vue", "*.svelte" },
  })
end

return M
