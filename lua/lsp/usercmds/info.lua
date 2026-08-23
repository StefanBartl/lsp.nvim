---@module 'lsp.usercmds.info'
--- LspInfo command implementation

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

--- Get servers for current buffer's filetype
---@param bufnr integer|nil
---@return string[]
local function get_servers_for_buffer(bufnr)
  bufnr = bufnr or 0
  local ft = vim.bo[bufnr].filetype
  if not ft or ft == "" then
    return {}
  end

  local map = get_filetype_server_map()
  return map[ft] or {}
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

--- Execute LspInfo command
---@return nil
function M.execute()
  local bufnr = 0
  local ft = vim.bo[bufnr].filetype
  local clients = get_buffer_clients(bufnr)
  local expected = get_servers_for_buffer(bufnr)

  local lines = {
    "LSP Information",
    "===============",
    "",
    string.format("Buffer:   %d", bufnr),
    string.format("Filetype: %s", ft or "none"),
    "",
    "Expected servers for this filetype:",
  }

  if #expected > 0 then
    for _, name in ipairs(expected) do
      local running = is_server_running(name, bufnr)
      table.insert(
        lines,
        string.format("  • %s [%s]", name, running and "✓ running" or "✗ not running")
      )
    end
  else
    table.insert(lines, "  (none configured)")
  end

  table.insert(lines, "")
  table.insert(lines, "Currently attached clients:")

  if #clients > 0 then
    for _, c in ipairs(clients) do
      local root = c.config and c.config.root_dir or "unknown"
      table.insert(lines, string.format("  • %s (id: %d)", c.name, c.id))
      table.insert(lines, string.format("    root: %s", root))
    end
  else
    table.insert(lines, "  (none)")
  end

  require("lib.nvim.ui.kit").viewer({
    lines = lines,
    title = " LSP Info ",
    width = math.min(80, vim.o.columns - 4),
    height = math.min(#lines + 2, vim.o.lines - 4),
    filetype = "markdown",
  })
end

return M
