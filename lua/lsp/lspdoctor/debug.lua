---@module 'lsp.lspdoctor.debug'
---@brief Debug LSP configuration and registration

local M = {}

local lsp = vim.lsp

--- Servers registered for this buffer's filetype.
---
--- Through `lsp.usercmds.start`, which is where `:LspDoctor startup` and
--- `:Lsp start` get the same answer. This file used to keep its own hardcoded
--- table of eighteen filetypes -- the very table `usercmds/start.lua` documents
--- as discredited and replaced: it named five servers this plugin does not
--- configure (`eslint`, `cssls`, `jsonls`, `omnisharp`, `zls`), missed ones it
--- does, and answered "none mapped" for every filetype outside the eighteen
--- whatever was actually attached.
---
--- That left the two halves of one command disagreeing about one question:
--- `resolve` is the report for "where does the filetype -> server chain break",
--- and it was walking a different chain than the plugin does.
---@param bufnr integer
---@return string[]
local function get_expected_servers(bufnr)
  local ok, start_mod = pcall(require, "lsp.usercmds.start")
  if ok and type(start_mod.get_servers_for_buffer) == "function" then
    return start_mod.get_servers_for_buffer(bufnr)
  end
  return {}
end

--- Get configured servers from registry
---@return string[]
local function get_configured_servers()
  local ok, reg = pcall(require, "lsp.core.registry")
  if ok and type(reg) == "table" and type(reg.ACTIVE) == "table" then
    return vim.deepcopy(reg.ACTIVE)
  end
  return {}
end

--- Names registered with `vim.lsp.config`.
---
--- Through `lsp.core.supervisor`, which owns the defensive read of that store.
--- This used to be `lsp.config.get()`, guarded by `not lsp.config.get` --
--- `vim.lsp.config` is a table with an `__index` resolver and has no `get`, so
--- the guard fired on every call and this list was *always* empty.
---
--- It is the same mistake as `health.lua`'s `config_exists` (roadmap B16,
--- fixed 2026-08-23); the twin in this file was not. And it mattered more
--- here: an empty list prints "❌ (none - THIS IS THE PROBLEM!)" in section 3,
--- and the Diagnosis below opens on `#registered == 0`, so `:LspDoctor
--- resolve` always closed with "❌ Critical: No servers registered in
--- vim.lsp.config" and could never reach any other verdict -- including the
--- ✅ one. Verified against three genuinely registered configs.
---
--- Two lists, because "registered" and "enabled" are different stages of the
--- chain this report exists to walk. A config that is registered and never
--- enabled would otherwise be indistinguishable from one that was never
--- registered, and the Diagnosis would send the reader to
--- `registry` initialization for a problem that is one `vim.lsp.enable` away.
---@return string[] registered, string[] enabled
local function get_registered_configs()
  local ok, supervisor = pcall(require, "lsp.core.supervisor")
  if not ok or type(supervisor.registered_names) ~= "function" then
    return {}, {}
  end
  local registered = supervisor.registered_names(true)
  local enabled = supervisor.registered_names()
  table.sort(registered)
  return registered, enabled
end

--- Get running clients
---@param bufnr integer
---@return string[]
local function get_running_clients(bufnr)
  local clients = lsp.get_clients({ bufnr = bufnr })
  local names = {}
  for _, c in ipairs(clients) do
    names[#names + 1] = c.name
  end
  table.sort(names)
  return names
end

--- Get completion candidates (what `:Lsp start` would offer)
---@param expected string[]
---@param running string[]
---@param configured string[]
---@return string[]
local function get_completion_candidates(expected, running, configured)
  local candidates = {}
  local seen = {}

  -- Add expected servers that aren't running
  for _, name in ipairs(expected) do
    local is_running = false
    for _, r in ipairs(running) do
      if r == name then
        is_running = true
        break
      end
    end
    if not is_running and not seen[name] then
      candidates[#candidates + 1] = name
      seen[name] = true
    end
  end

  -- Add configured servers that aren't running
  for _, name in ipairs(configured) do
    local is_running = false
    for _, r in ipairs(running) do
      if r == name then
        is_running = true
        break
      end
    end
    if not is_running and not seen[name] then
      candidates[#candidates + 1] = name
      seen[name] = true
    end
  end

  table.sort(candidates)
  return candidates
end

--- Generate debug info
---@param bufnr integer
---@return string[] lines, Lsp.Doctor.ResolveInfo info
function M.info(bufnr)
  local lines = {}
  local ft = vim.bo[bufnr].filetype
  local expected = get_expected_servers(bufnr)
  local configured = get_configured_servers()
  local registered, enabled = get_registered_configs()
  local running = get_running_clients(bufnr)
  local completion = get_completion_candidates(expected, running, configured)

  -- Header
  table.insert(lines, string.format("Buffer: `%d`", bufnr))
  table.insert(lines, string.format("Filetype: `%s`", ft or "none"))
  table.insert(lines, "")

  -- Expected servers
  table.insert(lines, "### 1. Expected servers for this filetype")
  if #expected > 0 then
    for _, name in ipairs(expected) do
      table.insert(lines, string.format("   • `%s`", name))
    end
  else
    table.insert(lines, "   *(no registered config declares this filetype)*")
  end
  table.insert(lines, "")

  -- Configured servers
  table.insert(lines, "### 2. Configured servers (registry.ACTIVE)")
  if #configured > 0 then
    for _, name in ipairs(configured) do
      table.insert(lines, string.format("   • `%s`", name))
    end
  else
    table.insert(lines, "   ⚠️  *(none - check registry initialization)*")
  end
  table.insert(lines, "")

  -- Registered configs
  table.insert(lines, "### 3. Registered configs (vim.lsp.config)")
  if #registered > 0 then
    for _, name in ipairs(registered) do
      local is_enabled = false
      for _, e in ipairs(enabled) do
        if e == name then
          is_enabled = true
          break
        end
      end
      table.insert(
        lines,
        string.format(
          "   • `%s`%s",
          name,
          is_enabled and "" or "  ⚠️  registered, not enabled"
        )
      )
    end
  else
    table.insert(lines, "   ❌ **(none - THIS IS THE PROBLEM!)**")
    table.insert(lines, "   💡 **Fix**: Ensure `lsp.config.add()` is called for each server")
  end
  table.insert(lines, "")

  -- Currently running
  table.insert(lines, "### 4. Currently running clients")
  if #running > 0 then
    for _, name in ipairs(running) do
      table.insert(lines, string.format("   • `%s`", name))
    end
  else
    table.insert(lines, "   *(none)*")
  end
  table.insert(lines, "")

  -- Completion candidates
  table.insert(lines, "### 5. Completion would show for `:Lsp start`")
  if #completion > 0 then
    for _, name in ipairs(completion) do
      table.insert(lines, string.format("   • `%s`", name))
    end
  else
    table.insert(lines, "   *(none - all running or nothing configured)*")
  end

  -- Diagnosis
  table.insert(lines, "")
  table.insert(lines, "### Diagnosis")

  if #registered == 0 then
    table.insert(lines, "❌ **Critical**: No servers registered in `vim.lsp.config`")
    table.insert(lines, "   This means configs were never added. Check:")
    table.insert(lines, "   1. `lsp.core.registry` initialization")
    table.insert(lines, "   2. `lsp.core.setup` registration loop")
    table.insert(lines, "   3. Call stack: `setup() -> register() -> config.add()`")
  elseif #enabled == 0 then
    table.insert(lines, "⚠️  **Warning**: Configs are registered but none is enabled")
    table.insert(lines, "   `vim.lsp.enable` is what attaches them on FileType")
  elseif #configured == 0 then
    table.insert(lines, "⚠️  **Warning**: No servers in registry.ACTIVE")
    table.insert(lines, "   Configs exist but registry is empty")
  elseif #expected > 0 and #running == 0 then
    table.insert(lines, "⚠️  **Warning**: Servers expected but none running")
    table.insert(lines, "   Try: `:Lsp start` or check autostart configuration")
  elseif #running > 0 then
    table.insert(lines, "✅ **OK**: LSP clients running normally")
  end

  local info = {
    filetype = ft,
    expected = expected,
    configured = configured,
    registered = registered,
    enabled = enabled,
    running = running,
    completion = completion,
  }

  return lines, info
end

return M
