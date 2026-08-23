---@module 'lsp.usercmds.completion'
--- Intelligent completion for LSP usercommands
--- Filters suggestions based on filetype and running state

local M = {}

local lsp = vim.lsp

--- Get all configured servers from registry
---@return string[]
local function get_configured_servers()
  local ok, reg = pcall(require, "lsp.core.registry")
  if ok and type(reg) == "table" and type(reg.ACTIVE) == "table" then
    return vim.deepcopy(reg.ACTIVE)
  end
  -- Fallback
  return { "lua_ls", "ts_ls", "gopls", "marksman", "html", "bashls" }
end

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

--- Get servers for current buffer's filetype
---@param bufnr integer|nil
---@return string[]
local function get_servers_for_filetype(bufnr)
  bufnr = bufnr or 0
  local ft = vim.bo[bufnr].filetype
  if not ft or ft == "" then
    return {}
  end

  local map = get_filetype_server_map()
  return map[ft] or {}
end

--- Get list of installed LSPs via Mason
---@return string[]
local function get_installed_lsps()
  local ok, registry = pcall(require, "mason-registry")
  if not ok then
    return {}
  end

  local lsps = {}
  for _, pkg in ipairs(registry.get_installed_packages()) do
    if pkg:is_installed() then
      local categories = pkg.spec.categories or {}
      for _, cat in ipairs(categories) do
        if cat == "LSP" then
          lsps[#lsps + 1] = pkg.name
          break
        end
      end
    end
  end

  table.sort(lsps)
  return lsps
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
--- Shows: filetype-relevant servers + configured servers + mason servers
--- Excludes: already running servers
---@param arglead string
---@param cmdline string
---@param cursorpos integer
---@return string[]
---@diagnostic disable-next-line: unused-local
function M.complete_start(arglead, cmdline, cursorpos)
  -- Wrap in pcall to avoid breaking completion on errors
  local ok, result = pcall(function()
    local bufnr = 0
    local candidates = {}
    local seen = {}

    -- Priority 1: Servers for current filetype (not running)
    local ft_servers = get_servers_for_filetype(bufnr)
    for _, name in ipairs(ft_servers) do
      if not is_server_running(name, bufnr) and not seen[name] then
        candidates[#candidates + 1] = name
        seen[name] = true
      end
    end

    -- Priority 2: Configured servers (not running)
    local configured = get_configured_servers()
    for _, name in ipairs(configured) do
      if not is_server_running(name, bufnr) and not seen[name] then
        candidates[#candidates + 1] = name
        seen[name] = true
      end
    end

    -- Priority 3: Mason servers (not running)
    local installed = get_installed_lsps()
    for _, name in ipairs(installed) do
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
---@param cmdline string
---@param cursorpos integer
---@return string[]
---@diagnostic disable-next-line: unused-local
function M.complete_stop(arglead, cmdline, cursorpos)
  local clients = get_buffer_clients(0)
  local names = {}

  for _, c in ipairs(clients) do
    names[#names + 1] = c.name
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
