---@module 'lsp.core.supervisor'
---@brief Bring a crashed language server back, with backoff -- and own the
---@brief attempt bookkeeping the rest of the plugin reports on.
---@description
--- A server that dies mid-session is invisible: hover stops answering,
--- completion goes empty, diagnostics freeze at whatever they last said. It
--- reads as slowness, and the usual reaction is to keep working for a while
--- and eventually type `:Lsp restart`. This module notices instead, and brings
--- the server back before the next keypress needs it.
---
--- **Crash versus intent is the whole difficulty.** `on_exit` cannot tell them
--- apart on its own: `vim.lsp.stop_client(id, true)` sends SIGTERM, so a
--- deliberate `:Lsp restart` looks exactly like a server killed by the OOM
--- killer. So intent is *declared*: every deliberate stop in this plugin calls
--- `expect_stop(id)` first, and an exit with a mark against it is not a crash.
--- The alternative -- guessing from the exit code -- would either fight the
--- user (restarting what they just stopped) or miss the case the module exists
--- for.
---
--- Two further exits are deliberately not crashes:
---
--- * **A clean exit nobody asked for** (`code == 0`, no signal). Ambiguous by
---   construction, and restarting on it risks a loop against a server that has
---   decided it is done. Neovim logs it either way.
--- * **A client that died before it ever attached.** Nothing here saw it, so
---   there is no name and no buffer to bring it back onto -- and a server that
---   fails *at startup* is the one case where an automatic retry loop is a
---   real hazard. That case has an owner already: `:Lsp recover`.
---
--- **The backoff is per server and exponential**, capped, and reset by
--- survival rather than by success: a relaunched client that is still alive
--- `reset_after_ms` later clears the counter. Resetting on attach instead
--- would turn a server that crashes two seconds after every attach into an
--- infinite restart loop, since each attach would forgive the previous crash.
---
--- **It also owns the attempt counter**, and that is not incidental.
--- `lspdoctor/health.lua` reports "Attempts: N" and a last error per server;
--- it used to read them from `lsp.usercmds.state`, a module that does not
--- exist, so the number was always 0 while `usercmds/recovery.lua` counted
--- into a table nothing read. One owner, one number, one place the report
--- comes from.
---
--- Hooked in through `vim.lsp.config("*", { on_exit = ... })` rather than
--- through each server module: `*` is merged into every named config, so a
--- server added tomorrow is supervised without remembering to wire it. A
--- server config that sets its own `on_exit` wins over this one -- none does
--- today, and one that did would be opting out on purpose.
---
--- Driven by `:Lsp autorestart [on|off|toggle|status]`.
---
---@see lsp.config.DEFAULTS
---@see lsp.usercmds.recovery
---@see lsp.lspdoctor.health

local notify = require("lib.nvim.notify").create("[lsp.core.supervisor]")
local autocmd = require("lib.nvim.bindings.autocmd")

local api = vim.api
local lsp = vim.lsp

local M = {}

--- Augroup for the attach bookkeeping. Its own, for the same reason
--- `lsp.core.inlay_hints` keeps one: `lsp_nvim` belongs to the keymap layer
--- and is cleared with it.
---@type string
M.GROUP = "lsp_nvim_supervisor"

---@class LspSupervisor.Options
---@field enable boolean
---@field max_attempts integer
---@field initial_delay_ms integer
---@field max_delay_ms integer
---@field reset_after_ms integer

---@type LspSupervisor.Options
local cfg = {
  enable = true,
  max_attempts = 4,
  initial_delay_ms = 1000,
  max_delay_ms = 30000,
  reset_after_ms = 60000,
}

--- Per-server bookkeeping. Read by `:LspDoctor startup` through
--- `M.attempts()` / `M.last_error()`, and by `usercmds/recovery.lua`, which
--- counts its own start attempts into the same table.
---@type { attempts: table<string, integer>, last_error: table<string, string>, last_exit: table<string, string> }
local state = {
  attempts = {},
  last_error = {},
  last_exit = {},
}

--- What each attached client is, so `on_exit` -- which is handed a client id
--- and nothing else, at a point where the client is on its way out -- can
--- still answer "which server, and which buffers wanted it".
---@type table<integer, { name: string, buffers: table<integer, true>, started_at: integer }>
local tracked = {}

--- Client ids whose exit was asked for. See the module doc.
---@type table<integer, true>
local expected = {}

---@type boolean
local registered = false

--- Set from `VimLeavePre`. `vim.v.exiting` is only populated once Neovim is
--- actually tearing down, and clients are stopped a shade before that.
---@type boolean
local leaving = false

-- --------------------------------------------------------------- bookkeeping

--- How many consecutive attempts to get this server up have failed.
---@param name string
---@return integer
function M.attempts(name)
  return state.attempts[name] or 0
end

--- Record one more attempt and return the new count.
---@param name string
---@return integer
function M.note_attempt(name)
  state.attempts[name] = (state.attempts[name] or 0) + 1
  return state.attempts[name]
end

--- Record why the last attempt failed.
---@param name string
---@param msg string
---@return nil
function M.note_error(name, msg)
  state.last_error[name] = tostring(msg)
end

--- Why the last attempt failed, if one did.
---@param name string
---@return string|nil
function M.last_error(name)
  return state.last_error[name]
end

--- Forget a server's failure history -- it is up, or someone took over.
---@param name string
---@return nil
function M.reset(name)
  state.attempts[name] = nil
  state.last_error[name] = nil
end

--- Declare that this client's exit is wanted, so it is not read as a crash.
---
--- Call it *before* stopping. A mark left behind by a client that then does
--- not exit is harmless: ids are never reused within a session, so it can only
--- ever match the stop it was set for.
---@param client_id integer|integer[]
---@return nil
function M.expect_stop(client_id)
  for _, id in ipairs(type(client_id) == "table" and client_id or { client_id }) do
    if type(id) == "number" then
      expected[id] = true
    end
  end
end

-- ------------------------------------------------------------------ starting

--- The registered configuration for a server name, resolved.
---
--- `vim.lsp.config[name]` and not `vim.lsp.config.get()`: the latter does not
--- exist on Neovim 0.12 (checked against 0.12.2), which is why the restart
--- command that used it stopped its client and then silently failed to bring
--- it back -- `get()` was nil, the lookup fell through to an empty table, and
--- "no config found" is indistinguishable from "restart failed" at the call
--- site.
---@param name string
---@return table|nil
function M.config_for(name)
  if type(lsp.config) ~= "table" and type(lsp.config) ~= "function" then
    return nil
  end
  local ok, resolved = pcall(function()
    return lsp.config[name]
  end)
  if ok and type(resolved) == "table" and resolved.cmd ~= nil then
    return resolved
  end
  return nil
end

--- Start a registered server and attach it to a buffer.
---
--- `vim.lsp.start` reuses a client with the same name and root rather than
--- spawning a second one, so calling this when the server is already back is
--- an attach, not a duplicate.
---@param name string
---@param bufnr integer
---@return boolean started
function M.start(name, bufnr)
  if type(name) ~= "string" or name == "" then
    return false
  end
  if not api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local server_config = M.config_for(name)
  if server_config == nil then
    return false
  end

  -- The resolved config is built elsewhere; LuaLS still checks it against
  -- `vim.lsp.start`'s meta, the same case as in `servers/lua_ls/reload.lua`.
  ---@diagnostic disable-next-line: missing-fields
  local ok, client_id = pcall(lsp.start, server_config, { bufnr = bufnr })
  return ok and client_id ~= nil
end

-- ------------------------------------------------------------------ restarts

---@internal
--- Is a client with this name attached to this buffer?
---@param name string
---@param bufnr integer
---@return boolean
local function running_on(name, bufnr)
  for _, client in ipairs(lsp.get_clients({ bufnr = bufnr })) do
    if client.name == name then
      return true
    end
  end
  return false
end

---@internal
--- The first buffer from a crashed client's set that is still worth restarting
--- into. A buffer that has since been wiped is not one.
---@param buffers table<integer, true>
---@return integer|nil
local function surviving_buffer(buffers)
  for bufnr in pairs(buffers) do
    if api.nvim_buf_is_valid(bufnr) and api.nvim_buf_is_loaded(bufnr) then
      return bufnr
    end
  end
  return nil
end

---@internal
--- How long to wait before attempt `n`. Exponential from `initial_delay_ms`,
--- capped at `max_delay_ms`.
---@param n integer # 1-based attempt number.
---@return integer ms
local function backoff(n)
  local ms = cfg.initial_delay_ms * (2 ^ math.max(0, n - 1))
  return math.floor(math.min(ms, cfg.max_delay_ms))
end

---@internal
--- Bring one server back onto one of the buffers that had it.
---@param name string
---@param buffers table<integer, true>
---@return nil
local function relaunch(name, buffers)
  local bufnr = surviving_buffer(buffers)
  if bufnr == nil then
    -- Every buffer that wanted this server is gone. Nothing to restore, and
    -- the counter should not outlive the incident.
    M.reset(name)
    return
  end

  if running_on(name, bufnr) then
    -- Something else got there first (`:Lsp restart`, a fresh FileType).
    M.reset(name)
    return
  end

  if not M.start(name, bufnr) then
    M.note_error(name, "restart failed: no usable configuration for " .. name)
    notify.error(("could not restart %s -- see :LspLog"):format(name))
    return
  end

  notify.info(("%s restarted (attempt %d)"):format(name, M.attempts(name)))

  -- Survival, not success, clears the counter: a server that comes up and
  -- dies again two seconds later has not recovered, and forgiving it on
  -- attach would let it restart forever.
  vim.defer_fn(function()
    if running_on(name, bufnr) then
      M.reset(name)
    end
  end, cfg.reset_after_ms)
end

---@internal
--- Decide what an exited client means, on the main loop.
---@param code integer
---@param signal integer
---@param client_id integer
---@return nil
local function handle_exit(code, signal, client_id)
  local info = tracked[client_id]
  tracked[client_id] = nil

  if expected[client_id] then
    expected[client_id] = nil
    if info then
      M.reset(info.name)
    end
    return
  end

  if leaving or vim.v.exiting ~= vim.NIL then
    return
  end
  if not cfg.enable then
    return
  end
  -- Never attached: no name, no buffer, and a startup crash loop is the one
  -- this must not enter. `:Lsp recover` owns that case.
  if info == nil then
    return
  end
  -- A clean exit nobody asked for. See the module doc.
  if code == 0 and signal == 0 then
    return
  end

  local name = info.name
  local reason = ("exited with code %d, signal %d"):format(code, signal)
  state.last_exit[name] = reason

  local n = M.note_attempt(name)
  M.note_error(name, reason)

  if n > cfg.max_attempts then
    notify.error(
      ("%s keeps crashing (%s); gave up after %d attempts -- see :LspLog"):format(
        name,
        reason,
        cfg.max_attempts
      )
    )
    return
  end

  local delay = backoff(n)
  notify.warn(
    ("%s %s; restarting in %dms (attempt %d/%d)"):format(name, reason, delay, n, cfg.max_attempts)
  )

  local buffers = info.buffers
  vim.defer_fn(function()
    relaunch(name, buffers)
  end, delay)
end

---@internal
--- `on_exit` runs in a fast event (verified on 0.12.2: `vim.in_fast_event()`
--- is true inside it), where most of the API is off limits. Capture the three
--- numbers and decide on the main loop.
---@param code integer
---@param signal integer
---@param client_id integer
---@return nil
local function on_exit(code, signal, client_id)
  vim.schedule(function()
    handle_exit(code, signal, client_id)
  end)
end

-- --------------------------------------------------------------------- setup

--- Seed the options and register the hooks.
---
--- Idempotent: a second `setup()` resets the augroup rather than stacking a
--- second set of autocommands on it, and re-registering the same `on_exit` on
--- `"*"` is a merge, not an accumulation.
---@param opts LspNvim.AutoRestartOpts|nil
---@return nil
function M.setup(opts)
  opts = opts or {}

  cfg.enable = opts.enable ~= false
  for _, key in ipairs({ "max_attempts", "initial_delay_ms", "max_delay_ms", "reset_after_ms" }) do
    local value = opts[key]
    if type(value) == "number" and value > 0 then
      cfg[key] = math.floor(value)
    end
  end

  M.detach()

  -- Through lib.nvim rather than `vim.api.nvim_create_autocmd`, which is what
  -- every autocommand in this plugin does -- see
  -- docs/NOTES/PersonelPlugins/BINDINGS/Autocmds/lsp.nvim.md, which states it
  -- as an invariant of the plugin.
  local group = autocmd.group(M.GROUP, true)

  autocmd.create("LspAttach", function(args)
    local client = lsp.get_client_by_id(args.data and args.data.client_id)
    if client == nil then
      return
    end
    local entry = tracked[client.id]
    if entry == nil then
      entry = { name = client.name, buffers = {}, started_at = vim.uv.now() }
      tracked[client.id] = entry
    end
    entry.buffers[args.buf] = true
  end, {
    group = group,
    desc = "lsp.nvim: remember which server a client is, for crash recovery",
  })

  autocmd.create("VimLeavePre", function()
    leaving = true
  end, {
    group = group,
    desc = "lsp.nvim: stop treating client exits as crashes while quitting",
  })

  if type(lsp.config) == "function" or type(lsp.config) == "table" then
    -- `"*"` is merged into every named config, including ones registered
    -- later (resolution is lazy -- verified on 0.12.2), so this reaches
    -- servers that do not exist yet.
    pcall(lsp.config, "*", { on_exit = on_exit })
  end

  registered = true
end

--- Whether a crashed server is brought back automatically.
---@return boolean
function M.enabled()
  return cfg.enable
end

--- Turn automatic restarts on or off for this session.
---@param value boolean
---@return boolean value
function M.set(value)
  cfg.enable = value and true or false
  notify.info(("auto-restart %s"):format(cfg.enable and "on" or "off"))
  return cfg.enable
end

--- Flip it.
---@return boolean value
function M.toggle()
  return M.set(not cfg.enable)
end

--- Human-readable lines for `:Lsp autorestart status`.
---@return string[]
function M.status()
  local lines = {
    "lsp.nvim - automatic restart after a crash",
    "",
    ("enabled:        %s"):format(cfg.enable and "yes" or "no"),
    ("hooks:          %s"):format(registered and "registered" or "not registered"),
    ("max attempts:   %d"):format(cfg.max_attempts),
    ("backoff:        %dms, doubling, capped at %dms"):format(
      cfg.initial_delay_ms,
      cfg.max_delay_ms
    ),
    ("counter resets: after %dms of survival"):format(cfg.reset_after_ms),
  }

  ---@type string[]
  local names = {}
  for name in pairs(state.attempts) do
    names[#names + 1] = name
  end
  table.sort(names)

  lines[#lines + 1] = ""
  if #names == 0 then
    lines[#lines + 1] = "no server has a failed attempt on record"
  else
    lines[#lines + 1] = "servers with attempts on record"
    for _, name in ipairs(names) do
      lines[#lines + 1] = ("  %-20s %d attempt(s)"):format(name, state.attempts[name])
      local reason = state.last_error[name]
      if reason then
        lines[#lines + 1] = ("  %-20s %s"):format("", reason)
      end
    end
  end

  ---@type string[]
  local live = {}
  for _, entry in pairs(tracked) do
    live[#live + 1] = entry.name
  end
  table.sort(live)
  lines[#lines + 1] = ""
  lines[#lines + 1] = #live == 0 and "no attached client is being watched"
    or ("watched clients: " .. table.concat(live, ", "))

  return lines
end

--- Drop the hooks and the per-client bookkeeping. The attempt counters stay:
--- they are what `:LspDoctor startup` reports, and detaching the supervisor is
--- not the same as declaring the failures never happened.
---@return nil
function M.detach()
  pcall(api.nvim_del_augroup_by_name, M.GROUP)
  tracked = {}
  expected = {}
  leaving = false
  registered = false
end

--- Exposed for the spec suite: the exit classifier, without the `vim.schedule`
--- hop that `on_exit` needs and a test does not.
---@private
M._handle_exit = handle_exit

--- Exposed for the spec suite.
---@private
M._backoff = backoff

return M
