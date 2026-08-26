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

--- Turn format-on-save on.
---@return nil
function M.format_on()
  local api = formatter()
  if api then
    api.enable()
  end
end

--- Turn format-on-save off.
---@return nil
function M.format_off()
  local api = formatter()
  if api then
    api.disable()
  end
end

--- Report whether format-on-save is active.
---@return nil
function M.format_status()
  local api = formatter()
  local state = (api ~= nil and api.is_enabled()) and "on" or "off"
  require("lib.nvim.notify").create("[lsp.nvim]").info("format-on-save: " .. state)
end

--- Show which formatter would run for this buffer, and whether it is present.
---@return nil
function M.format_which()
  local ok, conform = pcall(require, "lsp.formatter.conform")
  if ok and type(conform.which) == "function" then
    conform.which(0)
    return
  end
  require("lib.nvim.notify").create("[lsp.nvim]").warn("conform helper unavailable")
end

-- ---------------------------------------------------------------- workspace

---@internal
--- The runtime toggle for workspace-wide diagnostics on attach.
---@return table|nil
local function workspace()
  local ok, mod = pcall(require, "lsp.core.workspace_diagnostics")
  return ok and mod or nil
end

--- Toggle workspace-wide diagnostics on attach.
---@return nil
function M.workspace_toggle()
  local wd = workspace()
  if wd then
    wd.toggle()
  end
end

--- Enable workspace-wide diagnostics on attach.
---@return nil
function M.workspace_on()
  local wd = workspace()
  if wd then
    wd.set(true)
  end
end

--- Disable workspace-wide diagnostics on attach.
---@return nil
function M.workspace_off()
  local wd = workspace()
  if wd then
    wd.set(false)
  end
end

--- Report the current state of the workspace-diagnostics toggle.
---@return nil
function M.workspace_status()
  local wd = workspace()
  local state = (wd ~= nil and wd.enabled()) and "ON" or "OFF"
  require("lib.nvim.notify").create("[lsp.nvim]").info("workspace diagnostics on attach: " .. state)
end

--- Populate workspace diagnostics for this buffer now, toggle or not.
---@return nil
function M.workspace_now()
  local notify = require("lib.nvim.notify").create("[lsp.nvim]")
  local wd = workspace()
  if wd == nil then
    notify.warn("workspace diagnostics module unavailable")
    return
  end

  local ok, count_or_err = wd.populate_now(0)
  if not ok then
    notify.warn(tostring(count_or_err))
    return
  end
  notify.info(("populated workspace diagnostics for %d client(s)"):format(count_or_err))
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

---@internal
--- How many times a navigation action should move.
---
--- `nil` means "this came from a keypress": Vim calls a keymap callback with no
--- arguments, so the count is `v:count1` -- 1 when nothing was typed, N after
--- `3]d`. The `:Lsp diag` routes pass 1 explicitly instead, because `v:count`
--- is whatever the last *keypress* left behind and has nothing to do with a
--- command the user typed out.
---
--- NEW-25 asks for exactly this on any mapping that means "move": these are
--- `]d`/`[d`, `]q`/`[q`, `]l`/`[l` and `]w`/`[w`. The leader-prefixed actions
--- (populate a list, toggle a setting) have no ordered target and get none.
---@param count integer|nil
---@return integer
local function steps(count)
  if type(count) == "number" and count > 0 then
    return count
  end
  return vim.v.count1
end

-- ---------------------------------------------------------------- trouble

---@internal
--- Move `n` entries inside `view`, deferred until it has actually rendered.
---
--- Not `trouble.next(opts)`/`.prev(opts)`, Trouble's own public wrapper: that
--- wrapper reads `vim.v.count1` itself, inside the action it runs. Looping it
--- `n` times -- the previous shape of this function -- meant a real keypress
--- like `3]w` moved 3 * 3 = 9 entries: the loop resolved `n` from `v:count1`,
--- and then every iteration read the same still-unconsumed `v:count1` again.
--- Calling `view:move()` directly bypasses that action entirely, so `n` --
--- already resolved once by `steps()` -- is the only count in play.
---
--- `view:wait()` matters even when the view looks already open: Trouble
--- mounts the window inside a promise callback
--- (`view:refresh({opening=true}):next(...)`), not synchronously inside
--- `trouble.open()`, so a `:move()` right after opening a cold view would run
--- before `self.win.win` exists. `:wait()` is the same deferral
--- `trouble.next()`/`.prev()` use internally (`M:action` -> `self:wait`); for
--- a view that already rendered, its promise has already resolved and the
--- callback runs right away.
---@param view table # A `trouble.View`, from `trouble.open()`.
---@param direction "next"|"prev"
---@param n integer
---@return nil
local function trouble_view_move(view, direction, n)
  local opts = { jump = true }
  opts[direction == "next" and "down" or "up"] = n
  view:wait(function()
    view:move(opts)
  end)
end

---@internal
--- Move inside an open Trouble diagnostics list, without opening it.
---
--- Distinct from `trouble_jump` below: `]w`/`[w` are meant as "move within the
--- list you already opened", so silence (via a notify, not an error) is the
--- right response when there is none -- unlike `]d`/`[d`'s Trouble sink,
--- which opens the list on purpose.
---@param direction "next"|"prev"
---@param count integer|nil # Explicit repeat; from a keypress, `v:count1`.
---@return nil
local function trouble_move(direction, count)
  -- Asked before requiring, and that ordering is the point: if Trouble has
  -- never been loaded, no list of its can be open, so the answer is already
  -- known. Going through `require` first would load the whole plugin only to
  -- be told there is nothing to move in -- which is what made `lazy = false`
  -- look necessary for these two keymaps in the first place.
  if not package.loaded["trouble"] then
    require("lib.nvim.notify").create("[lsp.nvim]").info("Trouble diagnostics list is not open")
    return
  end

  local ok, trouble = pcall(require, "trouble")
  if not ok then
    return
  end
  if not trouble.is_open({ mode = "diagnostics" }) then
    require("lib.nvim.notify").create("[lsp.nvim]").info("Trouble diagnostics list is not open")
    return
  end
  local view = trouble.open({ mode = "diagnostics", refresh = false })
  if view then
    trouble_view_move(view, direction, steps(count))
  end
end

--- Next entry in the open Trouble diagnostics list.
---@param count integer|nil # Explicit repeat; from a keypress, `v:count1`.
---@return nil
function M.trouble_diag_next(count)
  trouble_move("next", count)
end

--- Previous entry in the open Trouble diagnostics list.
---@param count integer|nil # Explicit repeat; from a keypress, `v:count1`.
---@return nil
function M.trouble_diag_prev(count)
  trouble_move("prev", count)
end

---@internal
--- Whether `]d`/`[d` should route through Trouble instead of the native
--- location list, per `diagnostics.ui` (`"auto"|"native"|"trouble"`,
--- normalized by `lsp.config`).
---
--- `"trouble"` and `"auto"` resolve the same way at runtime: both need
--- Trouble actually installed, and there is nothing else to prefer it over.
--- The distinction is only for the config's own clarity -- "auto, whichever
--- is available" versus "I want Trouble" -- and matches how the rest of this
--- module degrades: quietly, never by breaking a keybinding whose plugin
--- happens to be absent.
---@return boolean
local function diagnostics_use_trouble()
  if cfg().diagnostics.ui == "native" then
    return false
  end
  return pcall(require, "trouble")
end

---@internal
--- `]d`/`[d`'s Trouble sink: open (and focus) the diagnostics list, then jump.
---
--- Unlike `trouble_move` above, opening is the point -- "Trouble als
--- Default-Senke" (roadmap section 15.1) means `]d` behaves exactly like
--- Trouble's own `next`, panel and all, not like a silent background move.
---@param direction "next"|"prev"
---@param count integer|nil
---@return boolean handled
local function trouble_jump(direction, count)
  local ok, trouble = pcall(require, "trouble")
  if not ok then
    return false
  end
  local view = trouble.open({ mode = "diagnostics" })
  if not view then
    return false
  end
  trouble_view_move(view, direction, steps(count))
  return true
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

--- Next diagnostic. Routes through Trouble when `diagnostics.ui` resolves to
--- it (roadmap section 15.1); otherwise the native location list.
---@param count integer|nil # Explicit repeat; from a keypress, `v:count1`.
---@return nil
function M.diag_next(count)
  if diagnostics_use_trouble() and trouble_jump("next", count) then
    return
  end
  require("lsp.diagnostics.loclist").next_loc(nil, steps(count))
end

--- Previous diagnostic. Routes through Trouble when `diagnostics.ui` resolves
--- to it (roadmap section 15.1); otherwise the native location list.
---@param count integer|nil # Explicit repeat; from a keypress, `v:count1`.
---@return nil
function M.diag_prev(count)
  if diagnostics_use_trouble() and trouble_jump("prev", count) then
    return
  end
  require("lsp.diagnostics.loclist").prev_loc(nil, steps(count))
end

--- Next quickfix entry.
---
--- `pcall`-wrapped `:cnext`, which is the only thing that separated this from
--- the `<cmd>cnext<cr>` the Trouble keymaps bound to the same key: at the end
--- of the list Vim raises E553, and swallowing it is the friendlier behaviour
--- for a key one holds down. That was the whole of roadmap finding B3 -- two
--- owners, not two behaviours.
---@param count integer|nil # Explicit repeat; from a keypress, `v:count1`.
---@return nil
function M.qf_next(count)
  require("lsp.diagnostics.quickfix").next_qf(steps(count))
end

--- Previous quickfix entry.
---@param count integer|nil # Explicit repeat; from a keypress, `v:count1`.
---@return nil
function M.qf_prev(count)
  require("lsp.diagnostics.quickfix").prev_qf(steps(count))
end

--- Next location-list entry.
---@param count integer|nil # Explicit repeat; from a keypress, `v:count1`.
---@return nil
function M.loc_next(count)
  pcall(vim.cmd, steps(count) .. "lnext")
end

--- Previous location-list entry.
---@param count integer|nil # Explicit repeat; from a keypress, `v:count1`.
---@return nil
function M.loc_prev(count)
  pcall(vim.cmd, steps(count) .. "lprevious")
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

--- Report the active root scope without opening the picker.
---@return nil
function M.root_show()
  local notify = require("lib.nvim.notify").create("[lsp.nvim]")
  local ok, scope = pcall(require, "lsp.core.root_scope")
  if not ok then
    notify.warn("root scope module unavailable")
    return
  end

  local mode = scope.get()
  local label = type(scope.label) == "function" and scope.label(mode) or tostring(mode)
  notify.info("root scope: " .. label)
end

return M
