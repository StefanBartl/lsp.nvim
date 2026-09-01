---@module 'lsp.tools.lsp_signature.show_hover'
--- Request hover from one or multiple LSP clients and display it in a floating preview.
--- Accepts either a single client object or a list (array) of clients.
--- If given multiple clients, it queries them in order and shows the first hover result
--- that yields displayable lines. Operations are asynchronous; the function schedules UI
--- updates and uses an optional callback to notify when a floating preview was created.
---
--- Return value: boolean indicating that at least one request was scheduled (not that a preview was necessarily shown).
---
--- ## The cache
---
--- `<C-b>` is a toggle, so "look at this again" is close → open → wait for the
--- server. The answer cannot have changed if the buffer has not: hover for a
--- position is a function of the text, and the text is versioned by
--- `changedtick`. So the *displayable lines* -- past the request and past
--- `format_hover` -- are kept in an LRU from `lib.lua.memo`, and a repeat on
--- an unedited buffer renders without a roundtrip.
---
--- The key is `(bufnr, changedtick, row, col, client ids)`. The first four are
--- what makes the answer what it is. The client ids are there because they are
--- what makes it *stale* otherwise: restart a server and the buffer has not
--- changed, so `changedtick` still matches, but the new client has a new id --
--- so the key moves on its own and the old entry is simply never asked for
--- again. That is a cheaper correctness story than an invalidation autocmd,
--- and it cannot drift out of sync with one.
local M = {}

local open_floating_preview = require("lsp.tools.lsp_signature.open_floating_preview")
local format_hover = require("lsp.tools.lsp_signature.format_hover")
local state = require("lsp.tools.lsp_signature.state")
local memo = require("lib.lua.memo")
local api = vim.api
local schedule = vim.schedule

--- How many (buffer, version, position) answers to keep.
---
--- Small on purpose: an entry is only ever reachable while its buffer is
--- unedited, so a large cache would hold entries that can no longer be hit.
local CACHE_CAPACITY = 32

local cache = memo.lru.new(CACHE_CAPACITY)

---@internal
--- Stable key for one hover answer, or nil when it cannot be formed.
---
--- nil means "do not cache this one" rather than "cache it under a guessed
--- key": a missing position or a dead buffer would otherwise collapse
--- different questions onto one entry, and a hover cache that answers the
--- wrong position is worse than no cache.
---@param bufnr integer
---@param params table
---@param clients table[]
---@return string|nil
local function cache_key(bufnr, params, clients)
  if type(bufnr) ~= "number" or not api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local position = params and params.position
  if type(position) ~= "table" or position.line == nil or position.character == nil then
    return nil
  end

  local ids = {}
  for _, client in ipairs(clients) do
    ids[#ids + 1] = tostring(client and client.id or "?")
  end
  table.sort(ids)

  return table.concat({
    bufnr,
    api.nvim_buf_get_changedtick(bufnr),
    position.line,
    position.character,
    table.concat(ids, ","),
  }, "\31")
end

---@internal
--- Open the preview for a set of already-formatted lines.
---
--- Shared by the cached and the uncached path so the two cannot drift into
--- showing the popup differently.
---@param lines string[]
---@param opts table
---@return nil
local function present(lines, opts)
  local buf, win = open_floating_preview(lines)
  state.set(buf, win)
  if opts.mode == "n" and win and api.nvim_win_is_valid(win) then
    api.nvim_set_current_win(win)
  end
  if opts.callback and buf and win then
    opts.callback(buf, win)
  end
end

--- Internal single-client handler creator.
--- Calls the client and invokes `on_result` when result processed (true if preview shown).
---@param _client table # Unused
---@param _params table # Unused
---@param opts table|nil
---@param on_result fun(shown: boolean, lines: string[]|nil)
---@diagnostic disable-next-line: unused-local
local function make_client_request_handler(_client, _params, opts, on_result)
  opts = opts or {}

  return function(_, result)
    if not result then
      -- no hover result for this client
      schedule(function()
        -- Do not notify here to avoid spamming when multiple clients are queried.
      end)
      on_result(false, nil)
      return
    end

    local lines = format_hover(result)
    if not lines or #lines == 0 then
      schedule(function()
        -- no displayable lines for this client
      end)
      on_result(false, nil)
      return
    end

    schedule(function()
      present(lines, opts)
      on_result(true, lines)
    end)
  end
end

--- send request to a single client (safely)
---@param client table
---@param params table
---@param opts table|nil
---@param on_result fun(shown: boolean, lines: string[]|nil)
local function request_one_client(client, params, opts, on_result)
  local handler = make_client_request_handler(client, params, opts, on_result)
  -- protect the request call; some clients may disconnect
  pcall(
    client.request,
    client,
    "textDocument/hover",
    params,
    handler,
    vim.api.nvim_get_current_buf()
  )
end

--- Drop every cached hover answer.
---
--- Nothing in this plugin needs it -- the key retires its own entries -- but a
--- cache with no way to empty it is a cache one cannot debug.
---@return nil
function M.clear_cache()
  cache = memo.lru.new(CACHE_CAPACITY)
end

--- show_hover accepts either:
---   - client: single client object
---   - clients: table/array of client objects
--- opts:
---   - mode: "n" or nil
---   - callback: fun(buf,win) optional callback
---   - bufnr: integer, the buffer the position belongs to (default: current)
--- Returns true when at least one request was scheduled, or when a cached
--- answer was shown without one.
---@param client_or_clients table|table[]
---@param params table
---@param opts table|nil
---@return boolean
function M.show_hover(client_or_clients, params, opts)
  opts = opts or {}
  ---@type table[]
  local clients

  -- normalize to list of clients
  if client_or_clients == nil then
    return false
  end
  if
    type(client_or_clients) == "table"
    and #client_or_clients > 0
    and client_or_clients[1] ~= nil
    and type(client_or_clients[1]) == "table"
  then
    clients = client_or_clients
  else
    clients = { client_or_clients }
  end

  local bufnr = opts.bufnr or api.nvim_get_current_buf()
  local key = cache_key(bufnr, params, clients)
  if key then
    local hit = cache:get(key)
    if hit then
      schedule(function()
        present(hit, opts)
      end)
      return true
    end
  end

  local scheduled_any = false
  local ci = 1

  -- recursive iterator over clients: try next client when current yields nothing
  local function try_next_client()
    local client = clients[ci]
    ci = ci + 1
    if not client then
      -- exhausted clients without showing hover
      return
    end

    scheduled_any = true
    -- on_result will be called with true when a preview was shown, false otherwise
    local function on_result(shown, lines)
      if shown then
        -- stop further attempts
        if key and lines then
          cache:put(key, lines)
        end
        return
      else
        -- try next client
        try_next_client()
      end
    end

    -- fire request for this client
    request_one_client(client, params, opts, on_result)
  end

  try_next_client()

  return scheduled_any
end

return M
