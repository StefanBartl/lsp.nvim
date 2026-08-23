---@module 'lsp.lspdoctor.debug'
---@brief Debug LSP configuration and registration

local M = {}

local lsp = vim.lsp

--- Get filetype-to-server mapping
---@return table<string, string[]>
local function get_filetype_server_map()
  return {
    lua = { "lua_ls" },
    javascript = { "ts_ls", "eslint" },
    typescript = { "ts_ls", "eslint" },
    javascriptreact = { "ts_ls", "eslint" },
    typescriptreact = { "ts_ls", "eslint" },
    go = { "gopls" },
    markdown = { "marksman" },
    ["markdown.mdx"] = { "marksman" },
    html = { "html", "emmet_ls" },
    css = { "cssls" },
    json = { "jsonls" },
    sh = { "bashls" },
    bash = { "bashls" },
    zsh = { "bashls" },
    c = { "clangd" },
    cpp = { "clangd" },
    cs = { "omnisharp" },
    zig = { "zls" },
  }
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

--- Get registered configs
---@return string[]
local function get_registered_configs()
  if type(lsp.config) ~= "table" or not lsp.config.get then
    return {}
  end

  local configs = lsp.config.get() or {}
  local names = {}
  for _, cfg in pairs(configs) do
    if cfg.name then
      names[#names + 1] = cfg.name
    end
  end
  table.sort(names)
  return names
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

--- Get completion candidates (what would be shown in :LspStart completion)
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
---@return string[] lines, table info
function M.info(bufnr)
  local lines = {}
  local ft = vim.bo[bufnr].filetype
  local map = get_filetype_server_map()
  local expected = map[ft] or {}
  local configured = get_configured_servers()
  local registered = get_registered_configs()
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
    table.insert(lines, "   *(none mapped)*")
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
      table.insert(lines, string.format("   • `%s`", name))
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
  table.insert(lines, "### 5. Completion would show for :LspStart")
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
  elseif #configured == 0 then
    table.insert(lines, "⚠️  **Warning**: No servers in registry.ACTIVE")
    table.insert(lines, "   Configs exist but registry is empty")
  elseif #expected > 0 and #running == 0 then
    table.insert(lines, "⚠️  **Warning**: Servers expected but none running")
    table.insert(lines, "   Try: `:LspStart` or check autostart configuration")
  elseif #running > 0 then
    table.insert(lines, "✅ **OK**: LSP clients running normally")
  end

  local info = {
    filetype = ft,
    expected = expected,
    configured = configured,
    registered = registered,
    running = running,
    completion = completion,
  }

  return lines, info
end

return M
