---@module 'lsp.servers.webdev.astro.autotag'
--- Astro Auto-Close Tags via nvim-ts-autotag integration

local notify = require("lib.nvim.notify").create("[lsp.languages.webdev.astro.autotag]")
local map = require("lib.nvim.map")

local M = {}

---@return boolean success
function M.setup()
  local ok, autotag = pcall(require, "nvim-ts-autotag")
  if not ok then
    notify.warn(
      "[Astro] nvim-ts-autotag not found. Install for better auto-close support:\n"
        .. "  { 'windwp/nvim-ts-autotag', event = 'InsertEnter' }"
    )
    return false
  end

  -- Configure nvim-ts-autotag für Astro
  autotag.setup({
    opts = {
      -- Enable closing tags for Astro files
      enable_close = true,
      enable_rename = true,
      enable_close_on_slash = true,
    },
    -- Astro-spezifische Filetype-Einstellungen
    per_filetype = {
      astro = {
        enable_close = true,
        enable_rename = true,
        enable_close_on_slash = true,
      },
    },
    -- Optional: Skip tags that should not auto-close
    skip_tags = {
      "area",
      "base",
      "br",
      "col",
      "command",
      "embed",
      "hr",
      "img",
      "slot",
      "input",
      "keygen",
      "link",
      "meta",
      "param",
      "source",
      "track",
      "wbr",
      "menuitem",
    },
  })

  return true
end

--- Fallback: Manuelle Auto-Close Implementation (falls nvim-ts-autotag nicht verfügbar)
---@param bufnr integer
---@return nil
function M.setup_manual_autoclose(bufnr)
  map("i", ">", function()
    ---@diagnostic disable-next-line: deprecated
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    local before_cursor = line:sub(1, col)

    -- Check if we're closing a tag
    local tag_match = before_cursor:match("<([%w%-]+)[^>]*$")

    if tag_match then
      -- Self-closing tags
      local self_closing = {
        img = true,
        br = true,
        hr = true,
        input = true,
        meta = true,
        link = true,
        area = true,
        base = true,
        col = true,
        embed = true,
        param = true,
        source = true,
        track = true,
        wbr = true,
        slot = true,
      }

      if not self_closing[tag_match:lower()] then
        -- Insert closing tag
        local close_tag = "</" .. tag_match .. ">"
        vim.api.nvim_put({ ">" }, "c", false, true)
        local new_col = col + 1
        vim.api.nvim_buf_set_text(bufnr, row - 1, new_col, row - 1, new_col, { close_tag })
        vim.api.nvim_win_set_cursor(0, { row, new_col })
        return
      end
    end

    -- Default behavior
    vim.api.nvim_put({ ">" }, "c", false, true)
  end, {
    buffer = bufnr,
    desc = "Astro: Auto-close tag (manual fallback)",
    silent = true,
  })

  -- Auto-close on "/"
  map("i", "/", function()
    ---@diagnostic disable-next-line: deprecated
    local _, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    local before_cursor = line:sub(1, col)

    -- Check if we're in a self-closing position: <tag /
    if before_cursor:match("<[%w%-]+%s*$") then
      vim.api.nvim_put({ "/>" }, "c", false, true)
      return
    end

    -- Default behavior
    vim.api.nvim_put({ "/" }, "c", false, true)
  end, {
    buffer = bufnr,
    desc = "Astro: Self-close tag",
    silent = true,
  })
end

return M
