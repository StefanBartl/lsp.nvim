---@module 'lsp.core.lightbulb'
---@brief Code-action indicator: a sign in the line when there is something to
---@brief apply there.
---@description
--- `lsa` (`vim.lsp.buf.code_action`) is a blind grab: you press it and find
--- out afterwards whether the server had anything. This module asks
--- `textDocument/codeAction` for the cursor position ahead of the keypress and
--- marks the line when the answer is non-empty, so the key is only pressed
--- when it pays.
---
--- **Why it is filtered by kind, and why that is the whole design.** The naive
--- lightbulb -- light up whenever any action comes back -- is on permanently
--- with several of the servers this plugin configures: `ts_ls` offers "Move to
--- a new file" on nearly every top-level statement, `gopls` is similarly
--- generous with refactors. An indicator that is always on carries no
--- information. So `kinds` is an allowlist of |lsp-code-action-kind| prefixes
--- and defaults to `quickfix` and `source`: the bulb means "something here is
--- broken and fixable", not "a refactoring is theoretically possible".
--- `refactor.*` is opt-in, and `kinds = {}` turns the filter off entirely.
---
--- An action with **no** `kind` passes the filter regardless. `kind` is
--- optional in the protocol and a plain `Command` never has one; dropping
--- those would silently hide every action from a server that does not
--- classify.
---
--- The request carries `triggerKind = 2` (Automatic). Servers that distinguish
--- it -- gopls and rust-analyzer do -- answer an automatic request more
--- cheaply than the one behind a keypress, which is exactly the trade this
--- module wants.
---
--- **Where it draws, and why not simply a sign.** The sign column already
--- carries diagnostic signs and `virtual_text` is on at end of line
--- (`lsp.core.diagnostics`), so both obvious places are taken. `render =
--- "sign"` therefore places the mark with a priority *above* the diagnostic
--- signs and only on the cursor line: it borrows the column for the one line
--- you are looking at and gives it back when you move on. `render =
--- "virtual_text"` puts it at `right_align` instead, at the window edge, where
--- the diagnostic message at `eol` cannot collide with it.
---
--- Structure mirrors `lsp.core.inlay_hints` deliberately -- global default
--- plus per-filetype overrides, where an absent filetype key inherits the
--- global and `false` is an explicit off, its own augroup, and the same
--- `on/off/toggle/status/clear` surface. Two features that behave the same way
--- should be configured the same way.
---
--- Driven by `:Lsp lightbulb [on|off|toggle|status|clear] [filetype]` and
--- `<leader>tl`.
---
--- Not to be confused with `:LspMdHints`, which toggles marksman's
--- Hint-severity diagnostics and predates this module under the same nickname;
--- that one is a diagnostic switch for one server, this one is the editor
--- indicator for every server.
---
---@see lsp.config.DEFAULTS
---@see lsp.core.inlay_hints
---@see lsp.bindings.actions
---@see lsp.core.diagnostics

local notify = require("lib.nvim.notify").create("[lsp.core.lightbulb]")
local autocmd = require("lib.nvim.bindings.autocmd")
local debounce = require("lib.nvim.debounce")

local api = vim.api

local M = {}

--- Augroup for the cursor/attach handlers. Separate from `lsp_nvim` for the
--- same reason `lsp.core.inlay_hints` keeps its own: that group belongs to the
--- keymap layer and is cleared with `keymaps.enable = false`.
---@type string
M.GROUP = "lsp_nvim_lightbulb"

--- Highlight group for the indicator. Linked to `Special` by default rather
--- than to a `DiagnosticSign*` group: it is not a diagnostic, and in most
--- colorschemes `Special` is the warm accent that reads as "notable" without
--- claiming a severity. Override it with `:hi link LspCodeActionLightbulb …`.
---@type string
M.HL = "LspCodeActionLightbulb"

---@type integer
local NS = api.nvim_create_namespace("lsp_nvim_lightbulb")

---@class LspLightbulb.State
---@field enable boolean
---@field filetypes table<string, boolean>
---@field kinds string[]
---@field render "sign"|"virtual_text"
---@field text string
---@field debounce_ms integer
---@field priority integer

---@type LspLightbulb.State
local state = {
  enable = false,
  filetypes = {},
  kinds = { "quickfix", "source" },
  render = "sign",
  text = "󰌵",
  debounce_ms = 150,
  priority = 20,
}

---@type boolean
local registered = false

--- Debounced entry point, rebuilt by `setup()` because the window is a
--- configuration value.
---@type Lib.Debounce.Handle|nil
local scheduled = nil

--- Bumped on every refresh. A response whose token is stale describes a cursor
--- position that is no longer the one on screen, and drawing it would leave
--- the bulb one keypress behind.
---@type integer
local token = 0

--- In-flight requests from the current refresh, so a superseded round can be
--- cancelled instead of merely ignored.
---@type { client: vim.lsp.Client, id: integer }[]
local inflight = {}

--- Where the indicator currently is, so an unchanged result redraws nothing.
--- Without this the extmark would be deleted and recreated on every cursor
--- movement inside a line that keeps its actions, which flickers.
---@type { bufnr: integer, row: integer }|nil
local placed = nil

-- ------------------------------------------------------------------ resolving

--- Whether the indicator is on for a filetype (or globally, with no argument).
---@param ft string|nil # Filetype to resolve; nil asks for the global default.
---@return boolean
function M.enabled(ft)
  if ft ~= nil and state.filetypes[ft] ~= nil then
    return state.filetypes[ft]
  end
  return state.enable
end

---@internal
--- Is this a buffer the indicator may draw in at all? Special buffers
--- (terminals, help, the quickfix window) have no code actions and no business
--- receiving a sign column entry.
---@param bufnr integer
---@return boolean
local function drawable(bufnr)
  return api.nvim_buf_is_valid(bufnr)
    and api.nvim_buf_is_loaded(bufnr)
    and vim.bo[bufnr].buftype == ""
    and M.enabled(vim.bo[bufnr].filetype)
end

---@internal
--- Clients attached to `bufnr` that advertise `codeActionProvider`.
---@param bufnr integer
---@return vim.lsp.Client[]
local function providers(bufnr)
  ---@type vim.lsp.Client[]
  local out = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    local caps = client.server_capabilities or {}
    if caps.codeActionProvider ~= nil and caps.codeActionProvider ~= false then
      out[#out + 1] = client
    end
  end
  return out
end

---@internal
--- Does `kind` pass the allowlist? A kind matches a prefix exactly or as a
--- dotted child of it (`quickfix` covers `quickfix.foo`, not `quickfixed`),
--- which is how |lsp-code-action-kind| defines the hierarchy.
---
--- An empty allowlist means "no filtering"; a missing kind always passes (see
--- the module doc).
---@param kind string|nil
---@return boolean
local function kind_matches(kind)
  if #state.kinds == 0 then
    return true
  end
  if kind == nil or kind == "" then
    return true
  end
  for _, want in ipairs(state.kinds) do
    if kind == want or kind:sub(1, #want + 1) == (want .. ".") then
      return true
    end
  end
  return false
end

---@internal
--- How many actions in one server's response count towards the indicator.
--- Disabled actions are skipped: they come back with a reason string precisely
--- so the client does not offer them.
---@param result table|nil
---@return integer
local function countable(result)
  local n = 0
  for _, action in ipairs(result or {}) do
    if type(action) == "table" and action.disabled == nil and kind_matches(action.kind) then
      n = n + 1
    end
  end
  return n
end

-- ------------------------------------------------------------------- drawing

---@internal
--- Remove the indicator from one buffer.
---@param bufnr integer|nil # nil clears wherever it currently is.
---@return nil
local function erase(bufnr)
  bufnr = bufnr or (placed and placed.bufnr)
  if bufnr and api.nvim_buf_is_valid(bufnr) then
    api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  end
  placed = nil
end

---@internal
--- Put the indicator on one line, or leave it exactly where it is when that is
--- already the answer.
---@param bufnr integer
---@param row integer # 0-based.
---@return nil
local function draw(bufnr, row)
  if placed and placed.bufnr == bufnr and placed.row == row then
    return
  end
  erase(nil)
  if not api.nvim_buf_is_valid(bufnr) or row >= api.nvim_buf_line_count(bufnr) then
    return
  end

  ---@type table
  local opts
  if state.render == "virtual_text" then
    opts = {
      priority = state.priority,
      hl_mode = "combine",
      virt_text = { { state.text, M.HL } },
      virt_text_pos = "right_align",
    }
  else
    opts = {
      priority = state.priority,
      hl_mode = "combine",
      sign_text = state.text,
      sign_hl_group = M.HL,
    }
  end

  local ok = pcall(api.nvim_buf_set_extmark, bufnr, NS, row, 0, opts)
  placed = ok and { bufnr = bufnr, row = row } or nil
end

-- ------------------------------------------------------------------ querying

---@internal
--- The LSP-shaped diagnostics on one line, for the request context. The server
--- needs them to offer the quickfix actions that belong to them; without a
--- context most servers answer with refactors only, which the allowlist then
--- drops -- so the bulb would never light up on the case it exists for.
---@param bufnr integer
---@param row integer # 0-based.
---@return table[]
local function line_diagnostics(bufnr, row)
  ---@type table[]
  local out = {}
  for _, d in ipairs(vim.diagnostic.get(bufnr, { lnum = row })) do
    local lsp_diagnostic = d.user_data and d.user_data.lsp
    if lsp_diagnostic then
      out[#out + 1] = lsp_diagnostic
    end
  end
  return out
end

---@internal
--- Drop whatever is still on the wire from a previous cursor position.
---@return nil
local function cancel_inflight()
  for _, req in ipairs(inflight) do
    pcall(function()
      req.client:cancel_request(req.id)
    end)
  end
  inflight = {}
end

---@internal
--- Ask every capable client about the cursor position and draw once all of
--- them have answered.
---@return nil
local function refresh()
  -- The refresh `setup()` queues can outlive the state it was queued for: a
  -- `detach()`, or a second `setup()`, lands between the schedule and the turn
  -- of the loop that runs it. Drawing then puts a mark on screen that nothing
  -- is left holding, and no later refresh knows to take it away.
  if not registered then
    return
  end

  token = token + 1
  cancel_inflight()

  local bufnr = api.nvim_get_current_buf()
  local winid = api.nvim_get_current_win()

  -- Insert mode is deliberately blank: the line is mid-edit, so the answer is
  -- about text that is about to change, and a bulb blinking per keystroke is
  -- the worst version of this feature.
  if not drawable(bufnr) or vim.startswith(api.nvim_get_mode().mode, "i") then
    erase(bufnr)
    return
  end

  local clients = providers(bufnr)
  if #clients == 0 then
    erase(bufnr)
    return
  end

  local row = api.nvim_win_get_cursor(winid)[1] - 1
  local diagnostics = line_diagnostics(bufnr, row)

  local mine = token
  local pending = #clients
  local total = 0
  local settled = false

  --- Draw or erase once every client has answered. Guarded, because a client
  --- that calls its handler twice must not be able to take the indicator away
  --- after it was already decided.
  ---@return nil
  local function settle()
    if settled then
      return
    end
    settled = true
    if total > 0 then
      draw(bufnr, row)
    else
      erase(bufnr)
    end
  end

  for _, client in ipairs(clients) do
    -- `make_range_params` needs the client's own encoding: the range it builds
    -- is measured in it, and a utf-8 server handed utf-16 columns is asked
    -- about the wrong place on any line with a multi-byte character.
    local params = vim.lsp.util.make_range_params(winid, client.offset_encoding)
    params.context = {
      diagnostics = diagnostics,
      -- CodeActionTriggerKind.Automatic -- see the module doc.
      triggerKind = 2,
    }

    -- A client may answer synchronously (a cached result, or a stub in the
    -- spec suite). The flag is what keeps the refusal branch below from
    -- counting such a client a second time -- doing so would settle the round
    -- while a real request was still out, and erase an indicator that had just
    -- been drawn.
    local answered = false

    local ok, id = client:request("textDocument/codeAction", params, function(_, result)
      if mine ~= token then
        return
      end
      answered = true
      total = total + countable(result)
      pending = pending - 1
      if pending <= 0 then
        settle()
      end
    end, bufnr)

    if ok and id then
      inflight[#inflight + 1] = { client = client, id = id }
    elseif not answered then
      -- Refused outright: a client shutting down between the capability check
      -- and the send. Nothing will ever call the handler for it.
      pending = pending - 1
      if pending <= 0 then
        settle()
      end
    end
  end
end

-- --------------------------------------------------------------- normalizing

---@internal
--- Sign text must fit the sign column. An over-wide value would raise inside
--- `nvim_buf_set_extmark` on every cursor movement, which is a hard error in a
--- hot path rather than a bad-looking sign.
---@param text string
---@return string
local function fit_sign(text)
  if vim.fn.strdisplaywidth(text) <= 2 then
    return text
  end
  notify.warn(("text %q is wider than the sign column allows, truncating"):format(text))
  local out = text
  while #out > 0 and vim.fn.strdisplaywidth(out) > 2 do
    out = vim.fn.strcharpart(out, 0, vim.fn.strchars(out) - 1)
  end
  return out ~= "" and out or "*"
end

-- --------------------------------------------------------------------- setup

--- Seed the live state from the configuration and register the handlers.
---
--- Idempotent: a second `setup()` resets the augroup rather than stacking a
--- second set of identical autocommands on it.
---@param opts LspNvim.LightbulbOpts|nil
---@return nil
function M.setup(opts)
  opts = opts or {}

  state.enable = opts.enable and true or false
  state.filetypes = {}
  if type(opts.filetypes) == "table" then
    for ft, value in pairs(opts.filetypes) do
      if type(ft) == "string" and type(value) == "boolean" then
        state.filetypes[ft] = value
      end
    end
  end

  if type(opts.kinds) == "table" then
    state.kinds = {}
    for _, kind in ipairs(opts.kinds) do
      if type(kind) == "string" and kind ~= "" then
        state.kinds[#state.kinds + 1] = kind
      end
    end
  end
  state.render = (opts.render == "virtual_text") and "virtual_text" or "sign"
  if type(opts.text) == "string" and opts.text ~= "" then
    state.text = state.render == "sign" and fit_sign(opts.text) or opts.text
  end
  if type(opts.debounce_ms) == "number" and opts.debounce_ms >= 0 then
    state.debounce_ms = math.floor(opts.debounce_ms)
  end
  if type(opts.priority) == "number" and opts.priority > 0 then
    state.priority = math.floor(opts.priority)
  end

  api.nvim_set_hl(0, M.HL, { link = "Special", default = true })

  M.detach()
  scheduled = debounce.new(refresh, state.debounce_ms)

  -- Through lib.nvim rather than `vim.api.nvim_create_autocmd`, which is what
  -- every autocommand in this plugin does -- see
  -- docs/NOTES/PersonelPlugins/BINDINGS/Autocmds/lsp.nvim.md, which states it
  -- as an invariant of the plugin.
  local group = autocmd.group(M.GROUP, true)

  -- `DiagnosticChanged` is in the list because the quickfix actions the
  -- allowlist is built around are the ones attached to a diagnostic: when the
  -- diagnostic arrives a second after the cursor stopped, the position never
  -- moves again and nothing else would ask.
  autocmd.create({ "CursorMoved", "BufEnter", "InsertLeave", "DiagnosticChanged" }, function()
    if scheduled then
      scheduled.call()
    end
  end, {
    group = group,
    desc = "lsp.nvim: re-ask for code actions at the cursor (lightbulb)",
  })

  -- Not debounced: hiding is never the thing that needs rate limiting, and a
  -- bulb that outlives the mode switch by 150ms is exactly the flicker the
  -- debounce exists to prevent.
  autocmd.create("InsertEnter", function()
    if scheduled then
      scheduled.cancel()
    end
    erase(nil)
  end, {
    group = group,
    desc = "lsp.nvim: hide the code-action indicator while typing",
  })

  autocmd.create("LspAttach", function()
    if scheduled then
      scheduled.call()
    end
  end, {
    group = group,
    desc = "lsp.nvim: ask for code actions once a client attaches (lightbulb)",
  })

  registered = true

  if state.enable or next(state.filetypes) ~= nil then
    vim.schedule(refresh)
  end
end

-- -------------------------------------------------------------------- toggles

--- Set the global default, or one filetype's override.
---@param value boolean
---@param ft string|nil # nil sets the global default.
---@return boolean value # The state now in effect for that scope.
function M.set(value, ft)
  value = value and true or false

  if ft == nil then
    state.enable = value
  else
    state.filetypes[ft] = value
  end

  erase(nil)
  if scheduled then
    scheduled.call()
  end

  notify.info(
    ("code-action indicator %s%s"):format(value and "on" or "off", ft and (" for " .. ft) or "")
  )
  return value
end

--- Flip the global default, or one filetype's effective state.
---
--- Toggling a filetype writes an explicit override even when the result equals
--- the global default -- otherwise a later change to the global would silently
--- undo the toggle just made.
---@param ft string|nil
---@return boolean value
function M.toggle(ft)
  return M.set(not M.enabled(ft), ft)
end

--- Drop a filetype's override so it follows the global default again.
---@param ft string
---@return nil
function M.clear(ft)
  if state.filetypes[ft] == nil then
    notify.info(("code-action indicator: %s had no override"):format(ft))
    return
  end
  state.filetypes[ft] = nil
  erase(nil)
  if scheduled then
    scheduled.call()
  end
  notify.info(
    ("code-action indicator: %s follows the global default (%s)"):format(
      ft,
      state.enable and "on" or "off"
    )
  )
end

--- Filetypes that carry an explicit override, for command completion.
---@return string[]
function M.overridden()
  ---@type string[]
  local fts = vim.tbl_keys(state.filetypes)
  table.sort(fts)
  return fts
end

--- Human-readable lines for `:Lsp lightbulb status`.
---@return string[]
function M.status()
  local lines = {
    "lsp.nvim - code-action indicator",
    "",
    ("global:         %s"):format(state.enable and "on" or "off"),
    ("handlers:       %s"):format(registered and "registered" or "not registered"),
    ("render:         %s (%q, priority %d)"):format(state.render, state.text, state.priority),
    ("debounce:       %dms"):format(state.debounce_ms),
    ("kinds:          %s"):format(
      #state.kinds > 0 and table.concat(state.kinds, ", ") or "(unfiltered)"
    ),
  }

  local fts = M.overridden()
  lines[#lines + 1] = ""
  if #fts == 0 then
    lines[#lines + 1] = "per-filetype overrides: (none)"
  else
    lines[#lines + 1] = "per-filetype overrides"
    for _, ft in ipairs(fts) do
      lines[#lines + 1] = ("  %-16s %s"):format(ft, state.filetypes[ft] and "on" or "off")
    end
  end

  local bufnr = api.nvim_get_current_buf()
  local names = {}
  for _, client in ipairs(providers(bufnr)) do
    names[#names + 1] = client.name
  end
  lines[#lines + 1] = ""
  if #names == 0 then
    lines[#lines + 1] = "this buffer has no client advertising codeActionProvider"
  else
    lines[#lines + 1] = ("codeActionProvider in this buffer: %s"):format(table.concat(names, ", "))
  end
  lines[#lines + 1] = ("indicator currently shown: %s"):format(
    placed and ("line " .. tostring(placed.row + 1)) or "no"
  )

  return lines
end

--- How many actions in a server response would light the indicator, exposed
--- for the spec suite. It is the whole point of the feature -- the allowlist
--- is what keeps the bulb from being on permanently -- and it is the one part
--- that can be checked without a language server.
---@private
M._countable = countable

--- Remove the handlers and any indicator still on screen.
---@return nil
function M.detach()
  if scheduled then
    scheduled.cancel()
  end
  cancel_inflight()
  erase(nil)
  pcall(api.nvim_del_augroup_by_name, M.GROUP)
  registered = false
end

return M
