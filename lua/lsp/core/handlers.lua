---@module 'lsp.core.handlers'
---@brief Wraps `textDocument/publishDiagnostics`: dedup, then throttle.
---@description
--- Two problems with one server push, in the order they have to be solved.
---
--- **Dedup** collapses entries a server sends twice, through
--- `lsp.core.filter.dedup`. Nothing changed about that except what it is given
--- to compare (see the note in `filter.lua`).
---
--- **Throttle** is what this module gained for roadmap QW4. A chatty server --
--- `ts_ls` is the reference case -- publishes several times per keystroke
--- pause, and every one of those pushes re-renders virtual text, re-sorts by
--- severity and re-runs whatever is listening on `DiagnosticChanged`. The
--- payloads in between are transient: they are superseded a few milliseconds
--- later by the next one.
---
--- The window is *leading-edge*, not trailing. A pure trailing debounce would
--- delay the first diagnostics of every burst by the full interval, which is
--- the one push a user is actually waiting for -- the one right after they
--- stop typing. So the first push of a burst goes through immediately, and
--- only the ones arriving inside the window are coalesced down to the last
--- one. The visible effect is that nothing gets slower and the redraw storm
--- disappears.
---
--- Coalescing keeps the *newest* payload, never a merge: a diagnostics list is
--- a complete replacement for a file, not a delta, so merging two of them
--- would resurrect diagnostics the server had just cleared.
---
--- The window is per `(client, file)`. Per client alone would let a noisy
--- buffer throttle a quiet one; per file alone would let two servers on the
--- same file cancel each other's pushes.
---
---@see lsp.core.filter
---@see lsp.config.DEFAULTS

local M = {}

--- Default throttle window in milliseconds, used when `setup()` is called
--- without one. Also the DEFAULTS value; kept here so a direct caller that
--- bypasses the config layer gets the same behaviour.
---@type integer
M.DEFAULT_DEBOUNCE_MS = 150

---@class LspNvim.PublishWindow
---@field timer uv.uv_timer_t # Runs for the length of one window.
---@field pending table|nil # Newest payload that arrived inside it, if any.

--- Open windows, keyed `client_id .. "\0" .. uri`.
---
--- The URI is the key rather than a buffer number on purpose: resolving one
--- with `vim.uri_to_bufnr` *creates* the buffer if it does not exist, and a
--- diagnostics push for a file nobody has open must not make one appear.
---@type table<string, LspNvim.PublishWindow>
local windows = {}

--- Guards against wrapping the handler twice. `setup()` runs once per session
--- today, but a second wrap would silently double every push -- and the second
--- wrapper's window would see the first one's output, not the server's.
---@type boolean
local installed = false

---@internal
--- Dedup a diagnostics payload without mutating what the server sent.
---@param result table
---@return table result # A shallow copy, deduplicated.
local function clean(result)
  local filter_ok, filter = pcall(require, "lsp.core.filter")
  if not filter_ok then
    return result
  end
  ---@type table
  local copy = { uri = result.uri, version = result.version, diagnostics = {} }
  for i, d in ipairs(result.diagnostics) do
    copy.diagnostics[i] = d
  end
  copy.diagnostics = filter.dedup(copy.diagnostics)
  return copy
end

---@internal
--- Close a window and forget it.
---@param key string
---@return nil
local function close_window(key)
  local win = windows[key]
  if win == nil then
    return
  end
  windows[key] = nil
  pcall(function()
    win.timer:stop()
    if not win.timer:is_closing() then
      win.timer:close()
    end
  end)
end

---@internal
--- Open a window that flushes whatever arrived during it, once.
---@param key string
---@param ms integer
---@param orig function # Neovim's own publishDiagnostics handler.
---@return nil
local function open_window(key, ms, orig)
  local timer = (vim.uv or vim.loop).new_timer()
  if timer == nil then
    -- No timer available (libuv handle exhaustion). Falling back to no
    -- throttling is strictly better than dropping the payload.
    return
  end
  windows[key] = { timer = timer, pending = nil }

  timer:start(
    ms,
    0,
    vim.schedule_wrap(function()
      local win = windows[key]
      close_window(key)
      if win == nil or win.pending == nil then
        return
      end
      local p = win.pending
      -- The client may have stopped while the window was open. Handing its
      -- payload on would render diagnostics for a server that is gone.
      if vim.lsp.get_client_by_id(p.ctx.client_id) == nil then
        return
      end
      orig(p.err, p.result, p.ctx, p.conf)
    end)
  )
end

--- Wrap `textDocument/publishDiagnostics`.
---@param opts { debounce_ms?: integer }|nil # `debounce_ms = 0` turns the throttle off and restores the plain dedup-and-forward behaviour.
---@return nil
function M.setup(opts)
  if installed then
    return
  end

  opts = opts or {}
  local ms = opts.debounce_ms
  if type(ms) ~= "number" or ms < 0 then
    ms = M.DEFAULT_DEBOUNCE_MS
  end
  ms = math.floor(ms)

  local orig = vim.lsp.handlers["textDocument/publishDiagnostics"]
  if type(orig) ~= "function" then
    return
  end

  -- Capture the handler table once (avoids duplicate-field warning)
  local handlers = vim.lsp.handlers

  ---@cast handlers any
  handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, conf)
    if not (result and type(result.diagnostics) == "table") then
      return orig(err, result, ctx, conf)
    end

    local cleaned = clean(result)

    if ms == 0 or ctx == nil or ctx.client_id == nil or result.uri == nil then
      return orig(err, cleaned, ctx, conf)
    end

    local key = tostring(ctx.client_id) .. "\0" .. tostring(result.uri)
    local win = windows[key]

    if win ~= nil then
      -- Inside an open window: hold the newest payload and let the timer
      -- deliver it. Replacing rather than queueing is the point.
      win.pending = { err = err, result = cleaned, ctx = ctx, conf = conf }
      return
    end

    -- Leading edge: nothing is waiting, so this one goes through now and
    -- opens the window for whatever follows it.
    open_window(key, ms, orig)
    return orig(err, cleaned, ctx, conf)
  end

  installed = true
end

--- Drop every open window. For tests and for a teardown that wants no timer
--- outliving it; the handler wrapper itself stays in place.
---@return nil
function M.flush()
  for key in pairs(windows) do
    close_window(key)
  end
end

return M
