---@module 'lsp.integrations.trouble'
---@brief trouble.nvim, the diagnostics UI.
---@description
--- Owns Trouble's configuration: the preview split, the index formatter, and
--- the Neovim 0.12 compatibility patch. `pack/ui.lua` only points its spec's
--- `config` here, because the pack layer holds specs, not logic.
---
--- Trouble is otherwise driven entirely through the keymap catalogue's
--- `<cmd>Trouble …<cr>` entries, which stay inert until pressed so the plugin
--- manager can keep loading it on demand. `available()` therefore probes with
--- `require` only when something asks -- health does, setup does not.
---
---@see lsp.integrations.trouble.numbering
---@see lsp.config.KEYMAPS
---@see lsp.integrations

local M = {}

---@type string
M.plugin = "trouble.nvim"

---@type boolean
M.hard = false

---@type string
M.note = "diagnostics UI; driven from the keymap catalogue"

---@return boolean
function M.available()
  return (pcall(require, "trouble"))
end

---@internal
--- The preview pane every mode shares.
---@return table
local function preview()
  return {
    type = "split",
    relative = "win",
    position = "right",
    size = 0.30,
  }
end

---@internal
--- Neovim 0.12 dropped or renamed `TSHighlighter._on_win` / `_on_line`, which
--- `trouble.view.treesitter` calls directly. Remap them to whatever this
--- Neovim actually has, or to a no-op, so Trouble's decoration provider does
--- not error on every redraw.
---
--- Deferred so Trouble's own setup has registered its provider first, and
--- guarded on the methods being absent rather than applied unconditionally --
--- on a Neovim that still has them, patching would replace working code.
---@return nil
local function patch_treesitter_view()
  vim.schedule(function()
    local ok = pcall(require, "trouble.view.treesitter")
    if not ok then
      return
    end

    local highlighter = vim.treesitter.highlighter
    if type(highlighter) ~= "table" then
      return
    end
    -- Patching private fields is the whole point of this function, so the
    -- handle is untyped: `_on_win`/`_on_line` are marked private on
    -- `vim.treesitter.highlighter`, and reading or writing them through the
    -- typed name is three findings that all say the same true thing.
    ---@cast highlighter table<string, any>

    ---@param primary string
    ---@param fallbacks string[]
    ---@return function|nil
    local function resolve(primary, fallbacks)
      if type(highlighter[primary]) == "function" then
        return nil -- already present: leave it alone
      end
      for _, alt in ipairs(fallbacks) do
        if type(highlighter[alt]) == "function" then
          return highlighter[alt]
        end
      end
      return function() end
    end

    local on_win = resolve("_on_win", { "on_win", "_win_start" })
    if on_win ~= nil then
      highlighter._on_win = on_win
    end

    local on_line = resolve("_on_line", { "on_line", "_on_buf" })
    if on_line ~= nil then
      highlighter._on_line = on_line
    end
  end)
end

--- Configure Trouble. Called from the pack spec's `config`.
---@return boolean ok
function M.configure()
  local ok, trouble = pcall(require, "trouble")
  if not ok then
    return false
  end

  local index = require("lsp.integrations.trouble.numbering").index_prefix()

  ---@param mode string
  ---@return table
  local function list_mode(mode)
    return {
      mode = mode,
      preview = preview(),
      formatters = { index = index, main = "message" },
    }
  end

  trouble.setup({
    preview = preview(),
    modes = {
      diagnostics = list_mode("diagnostics"),
      qflist = list_mode("qflist"),
      loclist = list_mode("loclist"),
    },
  })

  patch_treesitter_view()
  return true
end

return M
