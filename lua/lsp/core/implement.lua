---@module 'lsp.core.implement'
---@brief Implementation markers: a count at the end of the line of an interface
---@brief that something implements.
---@description
--- Reading `interface Repository` there is no way to know, without asking, that
--- three classes implement it. This asks: for every symbol of a configured kind
--- (by default `Interface`) in the buffer it sends
--- `textDocument/implementation` and, when the answer is not empty, puts a
--- virtual-text count at the end of the symbol's line -- `interface Repository
--- 3 impl`. lspsaga had it as `implement`.
---
--- **Off by default, and why.** It is one request per marked symbol per edit
--- pause. That is the same shape of load that was measured expensive for the
--- code-action indicator (~214ms in a startup sample), and it only earns its
--- keep in languages that have interfaces -- TypeScript, Go, Java, C#. Markdown's
--- server (marksman) has no `implementationProvider`, which is checked before a
--- single request is sent; lua_ls has one but reports no `Interface` symbols,
--- so there is nothing to ask about. Measured against those servers.
---
--- The symbols come from `lsp.core.symbols`, the same cache the winbar
--- breadcrumb reads, so turning this on adds the implementation requests and
--- not a second document-symbol request per edit. `max_requests` caps one
--- round, so a generated file with two hundred interfaces costs twenty
--- requests, not two hundred.
---
--- Structure mirrors `lsp.core.lightbulb`: global default plus per-filetype
--- overrides, its own augroup, `on/off/toggle/status/clear` through
--- `:Lsp implement`.
---
---@see lsp.core.symbols
---@see lsp.core.lightbulb

local notify = require("lib.nvim.notify").create("[lsp.core.implement]")
local autocmd = require("lib.nvim.bindings.autocmd")
local debounce = require("lib.nvim.debounce")
local symbols = require("lsp.core.symbols")

local api = vim.api

local M = {}

---@type string
M.GROUP = "lsp_nvim_implement"

--- Highlight group for the marker. Linked to `Comment`: it is metadata about
--- the line, and should read as such next to a diagnostic at the same place.
---@type string
M.HL = "LspNvimImplement"

---@type integer
local NS = api.nvim_create_namespace("lsp_nvim_implement")

--- SymbolKind names, by number, for `kinds` in the configuration.
---@type table<string, integer>
M.KIND_NUMBERS = {
  File = 1,
  Module = 2,
  Namespace = 3,
  Package = 4,
  Class = 5,
  Method = 6,
  Property = 7,
  Field = 8,
  Constructor = 9,
  Enum = 10,
  Interface = 11,
  Function = 12,
  Variable = 13,
  Constant = 14,
  String = 15,
  Number = 16,
  Boolean = 17,
  Array = 18,
  Object = 19,
  Key = 20,
  Null = 21,
  EnumMember = 22,
  Struct = 23,
  Event = 24,
  Operator = 25,
  TypeParameter = 26,
}

---@class LspImplement.State
---@field enable boolean
---@field filetypes table<string, boolean>
---@field kinds table<integer, true>
---@field text string
---@field debounce_ms integer
---@field max_requests integer

--- A fresh state at the documented defaults; see `lsp.core.winbar`'s of the
--- same name for why `setup()` starts from it.
---@return LspImplement.State
local function defaults()
  return {
    enable = false,
    filetypes = {},
    kinds = { [11] = true },
    text = " %d impl",
    debounce_ms = 600,
    max_requests = 20,
  }
end

---@type LspImplement.State
local state = defaults()

---@type boolean
local registered = false

---@type Lib.Debounce.Handle|nil
local scheduled = nil

--- Bumped on every round. A response carrying an older token describes text
--- that has since changed, and drawing it would mark the wrong line.
---@type table<integer, integer>
local tokens = {}

---@type table<integer, { client: vim.lsp.Client, id: integer }[]>
local inflight = {}

--- The `changedtick` each buffer's markers were last asked for. Several events
--- lead to the same round (entering the buffer, an attach, the schedule in
--- `setup()`), and without this each of them would send the same requests
--- again for text that has not changed.
---@type table<integer, integer>
local handled = {}

-- ------------------------------------------------------------------ resolving

--- Whether the markers are on for a filetype (or globally, with no argument).
---@param ft string|nil
---@return boolean
function M.enabled(ft)
  if ft ~= nil and state.filetypes[ft] ~= nil then
    return state.filetypes[ft]
  end
  return state.enable
end

---@internal
---@param bufnr integer
---@return vim.lsp.Client|nil
local function implementation_client(bufnr)
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/implementation" })
  table.sort(clients, function(a, b)
    return a.id < b.id
  end)
  return clients[1]
end

---@internal
---@param bufnr integer
---@return nil
local function cancel(bufnr)
  for _, req in ipairs(inflight[bufnr] or {}) do
    pcall(function()
      req.client:cancel_request(req.id)
    end)
  end
  inflight[bufnr] = nil
end

---@internal
---@param bufnr integer
---@return nil
local function erase(bufnr)
  cancel(bufnr)
  handled[bufnr] = nil
  tokens[bufnr] = (tokens[bufnr] or 0) + 1
  if api.nvim_buf_is_valid(bufnr) then
    api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  end
end

--- How many implementations one server answer names.
---@param result table|nil
---@return integer
function M.count(result)
  if type(result) ~= "table" then
    return 0
  end
  if result.uri or result.targetUri then
    return 1 -- a single Location
  end
  return #result
end

--- The symbols worth asking about, in document order, capped.
---@param nodes LspSymbols.Node[]
---@param kinds table<integer, true>
---@param limit integer
---@return LspSymbols.Node[]
function M.candidates(nodes, kinds, limit)
  ---@type LspSymbols.Node[]
  local out = {}
  symbols.walk(nodes, function(node)
    if #out < limit and kinds[node.kind] then
      out[#out + 1] = node
    end
  end)
  return out
end

---@internal
--- Ask about every candidate and draw the answers once they are all in.
---
--- Drawn together at the end, not one by one: the old markers stay until the
--- new round has something to say, so an edit does not blink every marker off
--- and on again.
---@param bufnr integer
---@param nodes LspSymbols.Node[]
---@return nil
local function run(bufnr, nodes)
  if
    not registered
    or not api.nvim_buf_is_valid(bufnr)
    or not M.enabled(vim.bo[bufnr].filetype)
  then
    return
  end
  local client = implementation_client(bufnr)
  if client == nil then
    erase(bufnr)
    return
  end
  local todo = M.candidates(nodes, state.kinds, state.max_requests)
  if #todo == 0 then
    erase(bufnr)
    return
  end

  local tick = api.nvim_buf_get_changedtick(bufnr)
  if handled[bufnr] == tick then
    return
  end
  handled[bufnr] = tick

  cancel(bufnr)
  tokens[bufnr] = (tokens[bufnr] or 0) + 1
  local mine = tokens[bufnr]

  ---@type { node: LspSymbols.Node, n: integer }[]
  local answers = {}
  local pending = #todo
  local uri = vim.uri_from_bufnr(bufnr)

  ---@return nil
  local function settle()
    if tokens[bufnr] ~= mine or not api.nvim_buf_is_valid(bufnr) then
      return
    end
    inflight[bufnr] = nil
    api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
    local line_count = api.nvim_buf_line_count(bufnr)
    for _, answer in ipairs(answers) do
      if answer.n > 0 and answer.node.sel_lnum < line_count then
        pcall(api.nvim_buf_set_extmark, bufnr, NS, answer.node.sel_lnum, 0, {
          virt_text = { { state.text:format(answer.n), M.HL } },
          virt_text_pos = "eol",
          hl_mode = "combine",
        })
      end
    end
  end

  inflight[bufnr] = {}
  for _, node in ipairs(todo) do
    local answered = false
    local ok, id = client:request("textDocument/implementation", {
      textDocument = { uri = uri },
      position = { line = node.sel_lnum, character = node.sel_col },
    }, function(_, result)
      if tokens[bufnr] ~= mine then
        return
      end
      answered = true
      answers[#answers + 1] = { node = node, n = M.count(result) }
      pending = pending - 1
      if pending <= 0 then
        settle()
      end
    end, bufnr)

    if ok and id then
      -- A client may answer before `request` returns (a cached result), which
      -- settles the round and clears the list this appends to.
      if inflight[bufnr] then
        table.insert(inflight[bufnr], { client = client, id = id })
      end
    elseif not answered then
      -- Refused outright: nothing will ever call the handler for it.
      pending = pending - 1
      if pending <= 0 then
        settle()
      end
    end
  end
end

---@internal
--- One round for a buffer: symbols first (from the shared cache), then the
--- implementation requests.
---@param bufnr integer
---@return nil
local function refresh(bufnr)
  if not registered or not api.nvim_buf_is_valid(bufnr) then
    return
  end
  if vim.bo[bufnr].buftype ~= "" or not M.enabled(vim.bo[bufnr].filetype) then
    erase(bufnr)
    return
  end
  -- Nothing to ask without a server that implements the method: checked
  -- before the symbol request, so Lua and Markdown pay nothing.
  if implementation_client(bufnr) == nil then
    erase(bufnr)
    return
  end
  symbols.refresh(bufnr, function(nodes)
    if nodes then
      run(bufnr, nodes)
    end
  end)
end

-- ---------------------------------------------------------------------- setup

--- Seed the live state from the configuration and register the handlers.
---@param opts LspNvim.ImplementOpts|nil
---@return nil
function M.setup(opts)
  opts = opts or {}

  state = defaults()
  state.enable = opts.enable and true or false
  if type(opts.filetypes) == "table" then
    for ft, value in pairs(opts.filetypes) do
      if type(ft) == "string" and type(value) == "boolean" then
        state.filetypes[ft] = value
      end
    end
  end
  if type(opts.kinds) == "table" then
    state.kinds = {}
    for name, on in pairs(opts.kinds) do
      local number = M.KIND_NUMBERS[name]
      if number and on == true then
        state.kinds[number] = true
      end
    end
  end
  if type(opts.text) == "string" and opts.text:find("%d", 1, true) then
    state.text = opts.text
  end
  if type(opts.debounce_ms) == "number" and opts.debounce_ms >= 0 then
    state.debounce_ms = math.floor(opts.debounce_ms)
  end
  if type(opts.max_requests) == "number" and opts.max_requests > 0 then
    state.max_requests = math.floor(opts.max_requests)
  end

  api.nvim_set_hl(0, M.HL, { link = "Comment", default = true })

  M.detach()
  registered = true
  scheduled = debounce.new(refresh, state.debounce_ms)
  local group = autocmd.group(M.GROUP, true)
  autocmd.create({ "TextChanged", "InsertLeave", "BufEnter", "LspAttach" }, function(args)
    if scheduled and M.enabled(vim.bo[args.buf].filetype) then
      scheduled.call(args.buf)
    end
  end, {
    group = group,
    desc = "lsp.nvim: re-ask for implementations after an edit (implementation markers)",
  })
  autocmd.create("BufWipeout", function(args)
    cancel(args.buf)
    tokens[args.buf] = nil
    handled[args.buf] = nil
  end, {
    group = group,
    desc = "lsp.nvim: forget the implementation-marker state of a wiped buffer",
  })

  if state.enable or next(state.filetypes) ~= nil then
    vim.schedule(function()
      for _, bufnr in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_loaded(bufnr) then
          refresh(bufnr)
        end
      end
    end)
  end
end

-- -------------------------------------------------------------------- toggles

---@internal
---@return nil
local function reapply()
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(bufnr) then
      if M.enabled(vim.bo[bufnr].filetype) then
        refresh(bufnr)
      else
        erase(bufnr)
      end
    end
  end
end

--- Set the global default, or one filetype's override.
---@param value boolean
---@param ft string|nil
---@return boolean value
function M.set(value, ft)
  value = value and true or false
  if ft == nil then
    state.enable = value
  else
    state.filetypes[ft] = value
  end
  reapply()
  notify.info(
    ("implementation markers %s%s"):format(value and "on" or "off", ft and (" for " .. ft) or "")
  )
  return value
end

--- Flip the global default, or one filetype's effective state.
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
    notify.info(("implementation markers: %s had no override"):format(ft))
    return
  end
  state.filetypes[ft] = nil
  reapply()
  notify.info(
    ("implementation markers: %s follows the global default (%s)"):format(
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

--- Human-readable lines for `:Lsp implement status`.
---@return string[]
function M.status()
  local names = {}
  for name, number in pairs(M.KIND_NUMBERS) do
    if state.kinds[number] then
      names[#names + 1] = name
    end
  end
  table.sort(names)

  local lines = {
    "lsp.nvim - implementation markers",
    "",
    ("global:         %s"):format(state.enable and "on" or "off"),
    ("handlers:       %s"):format(registered and "registered" or "not registered"),
    ("kinds:          %s"):format(#names > 0 and table.concat(names, ", ") or "(none)"),
    ("debounce:       %dms, at most %d request(s) per round"):format(
      state.debounce_ms,
      state.max_requests
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
  local client = implementation_client(bufnr)
  lines[#lines + 1] = ""
  lines[#lines + 1] = client and ("implementationProvider in this buffer: %s"):format(client.name)
    or "this buffer has no client advertising implementationProvider"
  local marks = api.nvim_buf_get_extmarks(bufnr, NS, 0, -1, {})
  lines[#lines + 1] = ("markers currently shown: %d"):format(#marks)
  return lines
end

--- Remove the handlers and every marker still on screen.
---@return nil
function M.detach()
  if scheduled then
    scheduled.cancel()
    scheduled = nil
  end
  pcall(api.nvim_del_augroup_by_name, M.GROUP)
  registered = false
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(bufnr) then
      cancel(bufnr)
      handled[bufnr] = nil
      api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
    end
  end
end

return M
