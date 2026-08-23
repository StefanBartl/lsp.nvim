---@module 'lsp.tools.deprecated_help.lsp.lua_ls.lua_ls'
--- lua_ls specific handling for deprecated diagnostics.
--- Responsibilities:
---  - Detect deprecated warnings emitted by lua_ls (and only lua_ls).
---  - For each relevant diagnostic, append a contextual notify message
---    and add a buffer-local keymap to open :help for the detected symbol.
---  - Keep track of created mappings to avoid duplicates.
---
--- Integration:
---  - This module registers itself with myplugin.lsp_common.
---  - It relies on myplugin.catch and myplugin.helper.

local notify = require("lib.nvim.notify").create("[lsp.tools.deprecated_help.lsp.lua_ls.lua_ls]")

local helper = require("lsp.tools.deprecated_help.helper")
local catch = require("lsp.tools.deprecated_help.lsp.lua_ls.catch")
local diagnostic = require("lsp.tools.deprecated_help.lsp.lua_ls.diagnostic")
local lsp_common = require("lsp.tools.deprecated_help.lsp_common")

local M = {}

local defaults = require("lsp.tools.deprecated_help.defaults")

-- Show help for symbol.
-- This uses Vim's :help command; it will error silently if no help exists.
---@param bufnr number
---@param symbol string
function M.show_help(bufnr, symbol)
  -- guard
  if not symbol or symbol == "" then
    notify.info("No symbol available for help.")
    return
  end

  -- switch to buffer if not current (so :h opens in correct window context)
  if bufnr and vim.api.nvim_get_current_buf() ~= bufnr and vim.api.nvim_buf_is_loaded(bufnr) then
    -- do not force window change; setting buffer local mapping is main behavior.
    -- But opening help doesn't require buffer switch; still, keep it simple:
    vim.api.nvim_set_current_buf(bufnr)
  end

  -- call help command for symbol (safe protected call)
  local ok, _ = pcall(function()
    vim.cmd("help " .. symbol)
  end)
  if not ok then
    notify.warn("Help not found for: " .. symbol)
  end
end

-- Internal: handle diagnostics for lua_ls only
---@param _err any
---@param result table
---@param ctx table
---@param _config table
local function on_publish(_err, result, ctx, _config)
  -- Try to find client again for absolute safety
  local client = nil
  if ctx and ctx.client_id then
    client = vim.lsp.get_client_by_id(ctx.client_id)
  end
  if not client or client.name ~= "lua_ls" then
    return -- only process lua_ls
  end

  local bufnr = result and result.uri and vim.uri_to_bufnr(result.uri) or nil
  if not bufnr or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  local buf_cache = helper.ensure_buf_cache(bufnr)

  for _, diag in ipairs(result.diagnostics) do
    -- use catch heuristics to ensure only deprecated warnings are processed
    if diagnostic.is_deprecated_warning(diag) then
      local symbol = catch.extract_symbol(bufnr, diag)
      if symbol == "" then
        -- fallback to generic brief symbol from message (first word)
        symbol = (diag.message or ""):match("([%w%._:]+)") or ""
      end

      -- Avoid repeated notifications/mappings for same symbol in same buffer
      if symbol ~= "" and not buf_cache[symbol] then
        buf_cache[symbol] = true

        -- notify user with appended actionable hint
        local notify_msg = string.format(
          "%s\n[Hint] Press %s to open :help for '%s' (buffer-local).",
          diag.message,
          defaults.keymap,
          symbol
        )
        notify.warn(notify_msg)

        -- set buffer-local keymap to open help for this symbol
        -- mapping will call our module function with the symbol captured by a closure
        local lhs = defaults.keymap
        local rhs_fn = function()
          M.show_help(bufnr, symbol)
        end
        helper.set_buf_keymap_once(
          bufnr,
          lhs,
          rhs_fn,
          { desc = "Open help for deprecated symbol: " .. symbol }
        )
      end
    end
  end
end

-- Setup function to register callback into lsp_common and optionally override defaults.
---@param opts table|nil
function M.setup(opts)
  opts = opts or {}
  if opts.keymap and type(opts.keymap) == "string" then
    defaults.keymap = opts.keymap
  end

  -- register with lsp_common
  lsp_common.register_server_callback("lua_ls", on_publish)
end

return M
