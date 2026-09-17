---@module 'lsp.usercmds.completion'
--- Intelligent completion for LSP usercommands
--- Filters suggestions based on filetype and running state
---
--- Everything offered for `:Lsp start` comes from the registered configs, for
--- one reason: `lsp.usercmds.start` refuses any other name ("No registered LSP
--- configuration for '%s'"), so offering a name it cannot start is offering a
--- dead end. Two sources used to feed this list and neither was the registry.
---
--- The first was `lsp.core.registry.ACTIVE`, which does not exist -- that
--- module exports `setup_all` and nothing else, so the `type(reg.ACTIVE) ==
--- "table"` guard never held and the "fallback" list of six names was the only
--- thing this ever returned. The second was a hardcoded filetype table, a copy
--- of the one `lsp.usercmds.start` was rewritten to get rid of. Measured on an
--- `html` buffer: the list offered `emmet_ls` (unconfigured, unstartable) and
--- never offered `tailwindcss`, which is configured for `html` and was the
--- server the user was reaching for. `omnisharp` and `tailwindcss` were
--- unreachable from completion at every filetype.

local M = {}

local lsp = vim.lsp
local start = require("lsp.usercmds.start")
local supervisor = require("lsp.core.supervisor")

--- Every server this plugin has a configuration for, sorted.
---@return string[]
local function get_configured_servers()
  local names = vim.deepcopy(supervisor.registered_names())
  table.sort(names)
  return names
end

--- Get clients attached to buffer
---@param bufnr integer|nil
---@return vim.lsp.Client[]
local function get_buffer_clients(bufnr)
  return lsp.get_clients({ bufnr = bufnr or 0 })
end

--- Check if server is running for buffer
---@param server_name string
---@param bufnr integer|nil
---@return boolean
local function is_server_running(server_name, bufnr)
  local clients = get_buffer_clients(bufnr)
  for _, c in ipairs(clients) do
    if c.name == server_name then
      return true
    end
  end
  return false
end

--- Filter candidates by arglead
---@param candidates string[]
---@param arglead string
---@return string[]
local function filter_by_arglead(candidates, arglead)
  if not arglead or arglead == "" then
    return candidates
  end

  local filtered = {}
  for _, name in ipairs(candidates) do
    if name:match("^" .. vim.pesc(arglead)) then
      filtered[#filtered + 1] = name
    end
  end
  return filtered
end

--- Completion for LspStartHere
--- Shows: filetype-relevant servers first, then the rest of the configured ones
--- Excludes: already running servers
---@param arglead string
---@param _cmdline string
---@param _cursorpos integer
---@return string[]
---@diagnostic disable-next-line: unused-local
function M.complete_start(arglead, _cmdline, _cursorpos)
  -- Wrap in pcall to avoid breaking completion on errors
  local ok, result = pcall(function()
    local bufnr = 0
    local candidates = {}
    local seen = {}

    -- Priority 1: Servers registered for this buffer's filetype (not running).
    -- Same answer `:Lsp start` with no argument acts on, and the same answer
    -- `:Lsp info` and `:LspDoctor startup` report.
    for _, name in ipairs(start.get_servers_for_buffer(bufnr)) do
      if not is_server_running(name, bufnr) and not seen[name] then
        candidates[#candidates + 1] = name
        seen[name] = true
      end
    end

    -- Priority 2: Every other configured server (not running). Starting a
    -- server outside the buffer's filetype is unusual but legitimate, and it
    -- is the only other name `start_lsp` accepts.
    for _, name in ipairs(get_configured_servers()) do
      if not is_server_running(name, bufnr) and not seen[name] then
        candidates[#candidates + 1] = name
        seen[name] = true
      end
    end

    table.sort(candidates)
    return filter_by_arglead(candidates, arglead)
  end)

  if ok then
    return result
  else
    -- Fallback: return empty list instead of breaking
    return {}
  end
end

--- Completion for LspStopHere
--- Shows: only running servers
---@param arglead string
---@param _cmdline string
---@param _cursorpos integer
---@return string[]
---@diagnostic disable-next-line: unused-local
function M.complete_stop(arglead, _cmdline, _cursorpos)
  local clients = get_buffer_clients(0)
  local names = {}
  local seen = {}

  -- Deduplicated: two clients can share a name, and the command takes a name,
  -- so offering it twice offers the same command twice.
  for _, c in ipairs(clients) do
    if not seen[c.name] then
      names[#names + 1] = c.name
      seen[c.name] = true
    end
  end

  table.sort(names)
  return filter_by_arglead(names, arglead)
end

--- Completion for LspRestartHere
--- Shows: only running servers
---@param arglead string
---@param cmdline string
---@param cursorpos integer
---@return string[]
function M.complete_restart(arglead, cmdline, cursorpos)
  -- Same as stop - only running servers can be restarted
  return M.complete_stop(arglead, cmdline, cursorpos)
end

return M
