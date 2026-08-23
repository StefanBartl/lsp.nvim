---@module 'lsp.bindings.actions'
---@brief The behaviour behind the keymap catalogue.
---@description
--- `config/KEYMAPS.lua` stays declarative data: an entry names an action, it
--- does not implement one. Anything with a decision in it -- which rename
--- backend, what to do when Trouble is not open -- lives here.
---
--- Third-party plugins are required lazily, inside the action, never at setup
--- time. Probing at bind time would force-load a plugin the user configured to
--- load on demand, which is both slower and a behaviour change; a command
--- string like `<cmd>Trouble …<cr>` stays inert until pressed and lets the
--- plugin manager do its job.
---
---@see lsp.config.KEYMAPS
---@see lsp.bindings.keymaps

local M = {}

---@internal
--- The resolved configuration, required lazily.
---
--- A top-level `require("lsp.config")` here would close a cycle:
--- `lsp.config` -> `lsp.config.KEYMAPS` -> `lsp.bindings.actions` -> back.
--- Requiring inside the call sites breaks it, and costs nothing -- `require`
--- is cached after the first hit.
---@return LspNvim.Config
local function cfg()
  return require("lsp.config").get()
end

-- ---------------------------------------------------------------- formatter

---@internal
--- The formatter API `setup()` published, building one on demand if setup has
--- not run (which is the case when a user binds these actions by hand without
--- calling `require("lsp").setup()`).
---@return table|nil
local function formatter()
  if type(vim.g._formatter_api) == "table" then
    return vim.g._formatter_api
  end

  local ok, mod = pcall(require, "lsp.formatter")
  if not (ok and type(mod.build) == "function") then
    return nil
  end

  local c = cfg()
  vim.g._formatter_api = mod.build({
    format_on_save = c.formatter.on_save,
    timeout_ms = c.formatter.timeout_ms,
  })
  return vim.g._formatter_api
end

--- Toggle format-on-save.
---@return nil
function M.format_toggle()
  local api = formatter()
  if api then
    api.toggle()
  end
end

--- Format the current buffer once, through the configured engine.
---@return nil
function M.format_buffer()
  local api = formatter()
  if api then
    api.format(0)
  end
end

--- Format via the language server directly, bypassing the engine.
---@return nil
function M.format_lsp()
  vim.lsp.buf.format({ async = true })
end

-- ---------------------------------------------------------------- rename

--- Rename the symbol under the cursor.
---
--- Resolves the two renames the config used to carry side by side: `grn` ran
--- `vim.lsp.buf.rename`, `<leader>rn` ran `:IncRename`. Same operation, two
--- keys, two behaviours (roadmap finding B9). Now both keys reach this, and
--- `rename.provider` decides the backend once.
---
--- inc-rename is driven through `feedkeys` rather than an `expr` mapping so a
--- single entry can serve both providers -- an `expr` mapping cannot decide at
--- press time to *not* be one.
---@return nil
function M.rename()
  local provider = cfg().rename.provider

  if provider ~= "native" and pcall(require, "inc_rename") then
    local cword = vim.fn.expand("<cword>")
    vim.api.nvim_feedkeys(":IncRename " .. cword, "n", false)
    return
  end

  vim.lsp.buf.rename()
end

-- ---------------------------------------------------------------- trouble

---@internal
--- Move inside an open Trouble diagnostics list without focusing it.
---@param direction "next"|"prev"
---@return nil
local function trouble_move(direction)
  local ok, trouble = pcall(require, "trouble")
  if not ok then
    return
  end
  if not trouble.is_open({ mode = "diagnostics" }) then
    require("lib.nvim.notify").create("[lsp.nvim]").info("Trouble diagnostics list is not open")
    return
  end
  trouble[direction]({ mode = "diagnostics", skip_groups = true, jump = true })
end

--- Next entry in the open Trouble diagnostics list.
---@return nil
function M.trouble_diag_next()
  trouble_move("next")
end

--- Previous entry in the open Trouble diagnostics list.
---@return nil
function M.trouble_diag_prev()
  trouble_move("prev")
end

-- ---------------------------------------------------------------- diagnostics

--- Buffer diagnostics into the location list, and open it.
---@return nil
function M.diag_to_loclist()
  require("lsp.diagnostics.loclist").to_loc({ open = true, win_id = 0 })
end

--- Workspace diagnostics into the quickfix list, and open it.
---@return nil
function M.diag_to_qflist()
  require("lsp.diagnostics.quickfix").to_qf({ open = true })
end

--- Next diagnostic in the buffer's location list.
---@return nil
function M.diag_next()
  require("lsp.diagnostics.loclist").next_loc(nil)
end

--- Previous diagnostic in the buffer's location list.
---@return nil
function M.diag_prev()
  require("lsp.diagnostics.loclist").prev_loc(nil)
end

--- Next quickfix entry.
---
--- `pcall`-wrapped `:cnext`, which is the only thing that separated this from
--- the `<cmd>cnext<cr>` the Trouble keymaps bound to the same key: at the end
--- of the list Vim raises E553, and swallowing it is the friendlier behaviour
--- for a key one holds down. That was the whole of roadmap finding B3 -- two
--- owners, not two behaviours.
---@return nil
function M.qf_next()
  require("lsp.diagnostics.quickfix").next_qf()
end

--- Previous quickfix entry.
---@return nil
function M.qf_prev()
  require("lsp.diagnostics.quickfix").prev_qf()
end

--- Next location-list entry.
---@return nil
function M.loc_next()
  pcall(vim.cmd, "lnext")
end

--- Previous location-list entry.
---@return nil
function M.loc_prev()
  pcall(vim.cmd, "lprevious")
end

-- ---------------------------------------------------------------- misc

--- Pick the root scope (cwd / git root / file path).
---@return nil
function M.root_scope_pick()
  require("lsp.core.root_scope_picker").open()
end

--- Toggle Marksman's markdown hints.
---@return nil
function M.marksman_hints_toggle()
  require("lsp.servers.marksman.hints").toggle()
end

return M
