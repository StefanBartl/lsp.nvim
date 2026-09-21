---@module 'lsp.core.symbols'
---@brief Document symbols for a buffer: one request, one cache, one path lookup.
---@description
--- The winbar breadcrumb and the implementation markers both need the answer
--- to `textDocument/documentSymbol`, and both need it whenever the buffer has
--- changed. Asking twice per edit is the waste this module exists to avoid, so
--- the request lives here once, is cached per buffer against `changedtick`,
--- and is handed out to whoever subscribed.
---
--- Two response shapes exist in the protocol and both are normalized into one
--- tree of |LspSymbols.Node|:
---
--- * `DocumentSymbol[]` -- hierarchical, what lua_ls, ts_ls, gopls and
---   marksman send.
--- * `SymbolInformation[]` -- flat, with a `location`. The tree is rebuilt
---   from range containment, so a breadcrumb over a flat server still nests.
---
--- **Where the cursor is.** `path_at()` returns the chain of symbols that
--- contain a position, outermost first. Containment is decided by line, with
--- the column consulted only where the line alone would be wrong: on a symbol
--- that starts and ends on the same line, and on the last line of one. A
--- cursor anywhere on the header line of a function counts as inside it,
--- including in the indentation before the keyword -- which is what a
--- breadcrumb reader expects, and what testing the column on the start line
--- would break.
---
--- A range that ends at column 0 of a later line is treated as ending on the
--- line before: that is how a section-shaped symbol (a Markdown heading) says
--- "up to, not including, the next heading", and reading it inclusively puts
--- the cursor on `## Next` inside the previous section as well.
---
--- The cache is stale-while-revalidate on purpose. After an edit `get()` keeps
--- returning the previous tree until the new answer arrives, so the breadcrumb
--- does not blink out while the server thinks.
---
---@see lsp.core.winbar
---@see lsp.core.implement

local autocmd = require("lib.nvim.bindings.autocmd")

local api = vim.api

local M = {}

---@class LspSymbols.Node
---@field name string
---@field kind integer # `lsp.SymbolKind`.
---@field detail string|nil
---@field lnum integer # 0-based start line of the whole symbol.
---@field col integer # Start character, in the client's offset encoding.
---@field end_lnum integer
---@field end_col integer
---@field sel_lnum integer # 0-based line of the symbol's name (`selectionRange`).
---@field sel_col integer
---@field children LspSymbols.Node[]

---@class LspSymbols.Entry
---@field tick integer # `changedtick` the answer was requested at.
---@field nodes LspSymbols.Node[]
---@field encoding string # Offset encoding of the client that answered.
---@field client_id integer

---@class LspSymbols.Pending
---@field tick integer
---@field client vim.lsp.Client
---@field id integer|nil
---@field waiters (fun(nodes: LspSymbols.Node[]|nil))[]

--- Augroup for the buffer clean-up handlers.
---@type string
M.GROUP = "lsp_nvim_symbols"

---@type table<integer, LspSymbols.Entry>
local cache = {}

---@type table<integer, LspSymbols.Pending>
local pending = {}

---@type (fun(bufnr: integer))[]
local subscribers = {}

---@type boolean
local wired = false

-- ---------------------------------------------------------------- normalizing

---@internal
---@param item table
---@return LspSymbols.Node|nil
local function node_from(item)
  local range = item.range or (item.location and item.location.range)
  if type(range) ~= "table" or not range.start or not range["end"] then
    return nil
  end
  local sel = item.selectionRange or range
  return {
    name = tostring(item.name or ""),
    kind = tonumber(item.kind) or 0,
    detail = type(item.detail) == "string" and item.detail or nil,
    lnum = range.start.line,
    col = range.start.character,
    end_lnum = range["end"].line,
    end_col = range["end"].character,
    sel_lnum = sel.start.line,
    sel_col = sel.start.character,
    children = {},
  }
end

---@internal
--- Convert a hierarchical `DocumentSymbol[]`.
---@param items table[]
---@return LspSymbols.Node[]
local function from_hierarchy(items)
  ---@type LspSymbols.Node[]
  local out = {}
  for _, item in ipairs(items) do
    local node = node_from(item)
    if node then
      if type(item.children) == "table" then
        node.children = from_hierarchy(item.children)
      end
      out[#out + 1] = node
    end
  end
  return out
end

---@internal
--- `a` starts before `b`, or at the same place and ends after it -- so a
--- container sorts ahead of the symbols inside it.
---@param a LspSymbols.Node
---@param b LspSymbols.Node
---@return boolean
local function outer_first(a, b)
  if a.lnum ~= b.lnum then
    return a.lnum < b.lnum
  end
  if a.col ~= b.col then
    return a.col < b.col
  end
  if a.end_lnum ~= b.end_lnum then
    return a.end_lnum > b.end_lnum
  end
  return a.end_col > b.end_col
end

---@internal
--- Does `outer` fully contain `inner`? By range, not by the column-lenient
--- cursor rule below: nesting has to be exact or siblings swallow each other.
---@param outer LspSymbols.Node
---@param inner LspSymbols.Node
---@return boolean
local function encloses(outer, inner)
  local starts = outer.lnum < inner.lnum or (outer.lnum == inner.lnum and outer.col <= inner.col)
  local ends = outer.end_lnum > inner.end_lnum
    or (outer.end_lnum == inner.end_lnum and outer.end_col >= inner.end_col)
  return starts and ends
end

---@internal
--- Rebuild a tree from a flat `SymbolInformation[]`.
---@param items table[]
---@return LspSymbols.Node[]
local function from_flat(items)
  ---@type LspSymbols.Node[]
  local flat = {}
  for _, item in ipairs(items) do
    local node = node_from(item)
    if node then
      flat[#flat + 1] = node
    end
  end
  table.sort(flat, outer_first)

  ---@type LspSymbols.Node[]
  local roots = {}
  ---@type LspSymbols.Node[]
  local open = {}
  for _, node in ipairs(flat) do
    while #open > 0 and not encloses(open[#open], node) do
      open[#open] = nil
    end
    local parent = open[#open]
    local siblings = parent and parent.children or roots
    siblings[#siblings + 1] = node
    open[#open + 1] = node
  end
  return roots
end

--- Normalize a `textDocument/documentSymbol` result into a node tree.
---
--- A `nil`, empty or malformed result is an empty tree, never an error: a
--- server answering `null` means "no symbols here", and every caller would
--- otherwise repeat the same nil check.
---@param result table|nil
---@return LspSymbols.Node[]
function M.normalize(result)
  if type(result) ~= "table" or #result == 0 then
    return {}
  end
  if result[1].location ~= nil then
    return from_flat(result)
  end
  return from_hierarchy(result)
end

-- ---------------------------------------------------------------- path lookup

---@internal
---@param node LspSymbols.Node
---@param line integer # 0-based.
---@param col integer # In the same encoding the node's columns are in.
---@return boolean
local function contains(node, line, col)
  local end_lnum, end_col = node.end_lnum, node.end_col
  if end_col == 0 and end_lnum > node.lnum then
    -- "Up to the start of that line": see the module doc.
    end_lnum = end_lnum - 1
    end_col = math.huge
  end

  if line < node.lnum or line > end_lnum then
    return false
  end
  if node.lnum == end_lnum then
    return col >= node.col and col <= end_col
  end
  if line == node.lnum then
    return true
  end
  if line == end_lnum then
    return col <= end_col
  end
  return true
end

--- The chain of symbols containing a position, outermost first.
---@param nodes LspSymbols.Node[]
---@param line integer # 0-based.
---@param col integer # Character offset, in the encoding of the answering client.
---@return LspSymbols.Node[]
function M.path_at(nodes, line, col)
  ---@type LspSymbols.Node[]
  local out = {}
  local level = nodes
  while true do
    ---@type LspSymbols.Node|nil
    local found
    for _, node in ipairs(level) do
      if contains(node, line, col) then
        found = node
        break
      end
    end
    if not found then
      return out
    end
    out[#out + 1] = found
    level = found.children
  end
end

--- Depth-first walk over every node, parents before children.
---@param nodes LspSymbols.Node[]
---@param fn fun(node: LspSymbols.Node, depth: integer)
---@param depth? integer
---@return nil
function M.walk(nodes, fn, depth)
  depth = depth or 1
  for _, node in ipairs(nodes) do
    fn(node, depth)
    M.walk(node.children, fn, depth + 1)
  end
end

-- -------------------------------------------------------------------- clients

--- The client that answers document-symbol requests for a buffer: the
--- lowest-numbered one advertising the capability, so the choice does not
--- change between two calls.
---@param bufnr integer
---@return vim.lsp.Client|nil
function M.provider(bufnr)
  local best
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    local caps = client.server_capabilities or {}
    local provides = caps.documentSymbolProvider
    if provides ~= nil and provides ~= false and (best == nil or client.id < best.id) then
      best = client
    end
  end
  return best
end

--- Is any client attached to the buffer at all?
---@param bufnr integer
---@return boolean
function M.attached(bufnr)
  return #vim.lsp.get_clients({ bufnr = bufnr }) > 0
end

--- The cursor as an LSP character offset in the buffer's answering client's
--- encoding. Falls back to the byte column when the conversion is not
--- available, which is exact for ASCII and off by a few columns otherwise --
--- and columns only matter on the boundary lines of a symbol.
---@param win integer
---@param encoding? string
---@return integer line # 0-based.
---@return integer col
function M.cursor(win, encoding)
  local pos = api.nvim_win_get_cursor(win)
  local line, byte = pos[1] - 1, pos[2]
  local bufnr = api.nvim_win_get_buf(win)
  local text = api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
  if encoding == nil or encoding == "utf-8" then
    return line, byte
  end
  local ok, col = pcall(vim.str_utfindex, text, encoding, byte)
  return line, ok and col or byte
end

-- ---------------------------------------------------------------------- cache

---@internal
---@param bufnr integer
---@return nil
local function forget(bufnr)
  cache[bufnr] = nil
  local req = pending[bufnr]
  if req then
    if req.id then
      pcall(function()
        req.client:cancel_request(req.id)
      end)
    end
    pending[bufnr] = nil
  end
end

---@internal
--- Drop a buffer's state when it goes away. Registered lazily, on the first
--- request, so requiring this module costs nothing at startup.
---@return nil
local function wire()
  if wired then
    return
  end
  wired = true
  local group = autocmd.group(M.GROUP, true)
  autocmd.create({ "BufWipeout", "BufUnload" }, function(args)
    forget(args.buf)
  end, {
    group = group,
    desc = "lsp.nvim: drop the cached document symbols of a buffer that went away",
  })
  autocmd.create("LspDetach", function(args)
    -- The answering client may be the one leaving; the next refresh picks
    -- another provider or finds none.
    local entry = cache[args.buf]
    if entry and entry.client_id == args.data.client_id then
      forget(args.buf)
    end
  end, {
    group = group,
    desc = "lsp.nvim: drop document symbols that came from a client that detached",
  })
end

--- What is cached for a buffer, fresh or not. `nil` before the first answer.
---@param bufnr integer
---@return LspSymbols.Node[]|nil nodes
---@return string|nil encoding
function M.get(bufnr)
  local entry = cache[bufnr]
  if entry == nil then
    return nil, nil
  end
  return entry.nodes, entry.encoding
end

--- Is the cached answer for the buffer as it is now?
---@param bufnr integer
---@return boolean
function M.fresh(bufnr)
  local entry = cache[bufnr]
  return entry ~= nil
    and api.nvim_buf_is_valid(bufnr)
    and entry.tick == api.nvim_buf_get_changedtick(bufnr)
end

--- Call `fn(bufnr)` whenever a new answer lands in the cache.
---@param fn fun(bufnr: integer)
---@return fun() unsubscribe
function M.subscribe(fn)
  subscribers[#subscribers + 1] = fn
  return function()
    for i, existing in ipairs(subscribers) do
      if existing == fn then
        table.remove(subscribers, i)
        return
      end
    end
  end
end

---@internal
---@param bufnr integer
---@return nil
local function announce(bufnr)
  -- A copy, so a subscriber that unsubscribes from inside its callback does
  -- not skip the one after it.
  for _, fn in ipairs(vim.list_slice(subscribers, 1, #subscribers)) do
    pcall(fn, bufnr)
  end
end

--- Ask for the buffer's symbols, unless the cache already answers for the
--- current text. `cb` is called with the nodes, or `nil` when the buffer has no
--- provider -- synchronously when the cache is fresh, later otherwise.
---
--- A request for a buffer that already has one in flight for the same text
--- joins it instead of sending a second.
---@param bufnr integer
---@param cb? fun(nodes: LspSymbols.Node[]|nil)
---@return nil
function M.refresh(bufnr, cb)
  if not api.nvim_buf_is_valid(bufnr) then
    if cb then
      cb(nil)
    end
    return
  end
  wire()

  local tick = api.nvim_buf_get_changedtick(bufnr)
  local entry = cache[bufnr]
  if entry and entry.tick == tick then
    if cb then
      cb(entry.nodes)
    end
    return
  end

  local client = M.provider(bufnr)
  if client == nil then
    if cb then
      cb(nil)
    end
    return
  end

  local req = pending[bufnr]
  if req and req.tick == tick and req.client.id == client.id then
    if cb then
      req.waiters[#req.waiters + 1] = cb
    end
    return
  end
  ---@type (fun(nodes: LspSymbols.Node[]|nil))[]
  local waiters = {}
  if req then
    -- Superseded: the text it asked about is gone. Whoever was waiting on it
    -- still wants an answer, and the new request is the one that will give it.
    waiters = req.waiters
    if req.id then
      local old = req
      pcall(function()
        old.client:cancel_request(old.id)
      end)
    end
  end
  if cb then
    waiters[#waiters + 1] = cb
  end

  ---@type LspSymbols.Pending
  local mine = { tick = tick, client = client, id = nil, waiters = waiters }
  pending[bufnr] = mine

  local ok, id = client:request("textDocument/documentSymbol", {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
  }, function(err, result)
    if pending[bufnr] ~= mine then
      return -- superseded, or the buffer went away
    end
    pending[bufnr] = nil

    ---@type LspSymbols.Node[]|nil
    local nodes = nil
    if not err then
      nodes = M.normalize(result)
      cache[bufnr] = {
        tick = tick,
        nodes = nodes,
        encoding = client.offset_encoding or "utf-16",
        client_id = client.id,
      }
    end
    if nodes ~= nil then
      announce(bufnr)
    end
    for _, waiter in ipairs(mine.waiters) do
      pcall(waiter, nodes)
    end
  end, bufnr)

  if ok and id then
    mine.id = id
  elseif pending[bufnr] == mine then
    -- Refused outright (a client shutting down): nothing will ever call back.
    pending[bufnr] = nil
    if cb then
      cb(nil)
    end
  end
end

--- Forget everything cached. For the spec suite and for `setup()` re-runs.
---@return nil
function M.reset()
  for bufnr in pairs(vim.tbl_extend("force", cache, pending)) do
    forget(bufnr)
  end
  cache = {}
  pending = {}
  subscribers = {}
end

return M
