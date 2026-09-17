---@module 'lsp.tools.lsp_signature.show_hover'
--- Request hover from one or multiple LSP clients and display it in a floating preview.
--- Accepts either a single client object or a list (array) of clients.
--- If given multiple clients, it asks all of them at once and shows the first
--- answer that yields displayable lines; the later ones are dropped. Operations are
--- asynchronous; the function schedules UI updates and uses an optional callback to
--- notify when a floating preview was created.
---
--- Asking them all at once rather than one after the other is not about latency.
--- A sequential chain advances on an *answer*, so a client that never produces one
--- ends the search at itself -- and "one attached client is silent" is the normal
--- state of affairs for a buffer with a linter and a language server on it.
---
--- Return value: boolean indicating that at least one client accepted the request
--- (not that a preview was necessarily shown).
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
  -- Close whatever is tracked before opening. `state` holds exactly one
  -- popup, so a second one opened over it is untrackable from that moment on:
  -- measured with two `<C-b>` presses while the first request was still in
  -- flight, both answers presented and `nvim_list_wins()` ended with two
  -- floats `{1003, 1002}` while `state` knew only 1003 -- the toggle then
  -- closed 1003 and left 1002 on screen with no way to reach it, because its
  -- only closer is an autocommand on its own buffer that cannot fire while
  -- that buffer is displayed.
  state.close()
  -- `focus` was never passed here, so every hover popup came out
  -- `focusable = false` -- including in normal mode, where the module
  -- documents a popup that "takes focus, so it can be scrolled and copied
  -- from". The signature path next door has always passed it.
  local buf, win = open_floating_preview(lines, { focus = opts.mode == "n" })
  state.set(buf, win)
  if opts.mode == "n" and win and api.nvim_win_is_valid(win) then
    api.nvim_set_current_win(win)
  end
  if opts.callback and buf and win then
    opts.callback(buf, win)
  end
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
---   - params_for: fun(client): table|nil, per-client position parameters.
---     Falls back to the shared `params` when absent or when it returns
---     nothing, so a caller with one encoding to worry about can ignore it.
--- Returns true when at least one client accepted the request, or when a
--- cached answer was shown without one.
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

  -- One popup per call, whoever gets there first.
  --
  -- The clients used to be asked one at a time, the next one only after the
  -- previous had answered -- which meant any client that did not answer ended
  -- the search. Measured with two stubs where the second held the hover text:
  -- with the first raising from `request` (a client that is shutting down),
  -- with it returning `false` (a server not ready yet), and with it simply
  -- staying silent, the second client was asked 0 times in all three cases and
  -- no popup ever opened -- while `show_hover` returned `true`, so the caller
  -- went on believing an answer was on its way.
  --
  -- So: ask everyone at once and take the first displayable answer. `settled`
  -- is set in the handler rather than in the scheduled callback, because two
  -- answers can arrive before the loop turns and both would otherwise open a
  -- popup.
  local settled = false
  local sent = 0

  ---@return fun(err: any, result: any)
  local function handler_for()
    -- One answer per client. A handler that fires twice -- a server sending a
    -- duplicate response, or a request we already gave up on -- must not draw
    -- over an answer that is already on screen.
    local answered = false
    return function(_, result)
      if answered or settled then
        return
      end
      answered = true

      local lines = result and format_hover(result) or nil
      if not lines or #lines == 0 then
        -- Nothing displayable from this client. No notify: with every client
        -- asked at once that would be one message per silent server.
        return
      end

      settled = true
      schedule(function()
        present(lines, opts)
        if key then
          cache:put(key, lines)
        end
      end)
    end
  end

  for _, client in ipairs(clients) do
    -- `params_for` lets the caller encode the position per client: the column
    -- in a position parameter is counted in the encoding *that* server
    -- negotiated, and two clients on one buffer need not agree.
    local client_params = params
    if opts.params_for then
      local ok, per_client = pcall(opts.params_for, client)
      if ok and type(per_client) == "table" then
        client_params = per_client
      end
    end

    -- `pcall`: `request` raises on a client that is closing. Counting only
    -- the requests that were actually accepted is what makes the return value
    -- mean something -- see the measurement above.
    local ok, accepted =
      pcall(client.request, client, "textDocument/hover", client_params, handler_for(), bufnr)
    if ok and accepted ~= false then
      sent = sent + 1
    end
  end

  return sent > 0
end

return M
