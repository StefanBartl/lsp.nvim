---@module 'lsp.servers.webdev.astro.autotag'
--- Astro auto-close tags: is nvim-ts-autotag usable in this session, and the
--- hand-rolled fallback for when it is not.
---
--- **This module does not configure nvim-ts-autotag, on purpose.** The plugin
--- has exactly one, global `setup()`, so configuring it from here means
--- deciding `enable_close`, `enable_rename` and `enable_close_on_slash` for
--- every filetype in the editor -- HTML, TSX, Svelte, Vue -- from inside an
--- Astro module. That is not Astro's call. Whoever installs the plugin owns
--- its options; this only asks whether it is there and wired up.
---
--- It used to call `setup()` with a full options table. Under lazy.nvim that
--- was dead code: the host's own `config` runs during the very `require` that
--- loads the plugin, and `nvim-ts-autotag.config.plugin.setup()` returns early
--- once `did_setup()` is true -- so the second call did nothing, and Astro's
--- `per_filetype.astro` never took effect either. Under a host that installs
--- the plugin *without* configuring it, the same call did the opposite and
--- silently became the global configuration. Both are gone now; what the
--- plugin does is what its owner asked for.
---
--- (The `skip_tags` key that call passed was never read by the plugin at all.
--- Skip patterns are per-filetype `skip_tag_pattern` entries in
--- `nvim-ts-autotag.config.init`, not a `setup()` option.)

local notify = require("lib.nvim.notify").create("[lsp.languages.webdev.astro.autotag]")
local map = require("lib.nvim.bindings.keymap")

local M = {}

---@internal
--- Has anyone called `nvim-ts-autotag`'s `setup()`? Without it the plugin
--- registers no autocommands and attaches to no buffer, so "installed" is not
--- the same as "working".
---
--- Reads an internal module, deliberately tolerantly: an unknown layout is
--- treated as "assume it is fine" rather than as a reason to drop to the
--- fallback, because a renamed internal is not evidence that the plugin is
--- unconfigured.
---@return boolean
local function configured_by_host()
  local ok, plugin = pcall(require, "nvim-ts-autotag.config.plugin")
  if not (ok and type(plugin) == "table" and type(plugin.did_setup) == "function") then
    return true
  end
  return plugin.did_setup() == true
end

--- Can nvim-ts-autotag handle auto-closing here?
---
--- `false` means the caller should install `setup_manual_autoclose` for the
--- buffer instead. Loading the plugin is a side effect of asking, and a wanted
--- one: this runs from the first Astro buffer, which is exactly when it should
--- be up.
---@return boolean active
function M.available()
  local ok = pcall(require, "nvim-ts-autotag")
  if not ok then
    notify.warn(
      "[Astro] nvim-ts-autotag not found. Install for better auto-close support:\n"
        .. "  { 'windwp/nvim-ts-autotag', event = 'InsertEnter' }"
    )
    return false
  end

  if not configured_by_host() then
    notify.warn(
      "[Astro] nvim-ts-autotag is installed but never set up, so it attaches to\n"
        .. "no buffer. Call require('nvim-ts-autotag').setup{} from its own spec;\n"
        .. "Astro will not do it for you, because that setup is global.\n"
        .. "Using the hand-rolled fallback for now."
    )
    return false
  end

  return true
end

--- Hand-rolled auto-close, for when nvim-ts-autotag is not installed.
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
