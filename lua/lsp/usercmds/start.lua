---@module 'lsp.usercmds.start'
---@brief `:Lsp start`, and the answer to "which servers belong to this buffer".
---@description
--- `M.get_servers_for_buffer` is the more important half: `lspdoctor/health`
--- calls it for the expected-server list that `:LspDoctor startup` reports and
--- that `:Lsp recover` starts from, so whatever it says is what those two
--- believe.
---
--- It used to say it from a hardcoded table of seventeen filetypes. That table
--- named five servers this plugin does not configure (`eslint`, `cssls`,
--- `jsonls`, `omnisharp`, `zls`), missed ones it does (`tailwindcss`), and got
--- two names wrong in the other direction -- `servers = { "csharp" }`
--- registers as `omnisharp` and `"zig"` as `zls`, so the table happened to be
--- right about those two names and wrong about which option produced them.
--- Every filetype outside the seventeen answered "no LSP configured", whatever
--- was actually running.
---
--- It is derived now: the registered configs, filtered to the ones that
--- declare this buffer's filetype. That is the same data `vim.lsp.enable`
--- attaches from, so the report and the reality cannot drift.
---
---@see lsp.core.supervisor
---@see lsp.lspdoctor.health

local M = {}

local notify = require("lib.nvim.notify").create("[LSP.Start] ")
local supervisor = require("lsp.core.supervisor")
local lsp = vim.lsp

--- Servers registered for this buffer's filetype.
---
--- Derived from `vim.lsp.config`, not from a list kept here: a server declares
--- its own `filetypes`, and that declaration is what Neovim attaches from.
---@param bufnr integer|nil
---@return string[]
function M.get_servers_for_buffer(bufnr)
  bufnr = bufnr or 0
  local ft = vim.bo[bufnr].filetype
  if not ft or ft == "" then
    return {}
  end

  ---@type string[]
  local names = {}
  for _, name in ipairs(supervisor.registered_names()) do
    local cfg = supervisor.config_for(name)
    for _, declared in ipairs((cfg and cfg.filetypes) or {}) do
      if declared == ft then
        names[#names + 1] = name
        break
      end
    end
  end
  return names
end

--- Check if server is running for buffer
---@param server_name string
---@param bufnr integer|nil
---@return boolean
local function is_server_running(server_name, bufnr)
  local clients = lsp.get_clients({ bufnr = bufnr or 0 })
  for _, c in ipairs(clients) do
    if c.name == server_name then
      return true
    end
  end
  return false
end

--- Start LSP server by name with async attachment check
---@param name string
---@param bufnr integer|nil
---@return boolean success
local function start_lsp(name, bufnr)
  bufnr = bufnr or 0

  if not name or name == "" then
    notify.warn("No LSP name provided")
    return false
  end

  -- Check if already running
  if is_server_running(name, bufnr) then
    notify.info(string.format("LSP '%s' already running", name))
    return true
  end

  -- Not `vim.lsp.enable`: that arms an autocommand and launches a client the
  -- next time a matching buffer event fires, which for a buffer that is
  -- already open never comes. It is why this command used to end in "setup
  -- completed but not yet attached. Try :edit" -- the `:edit` was the event.
  -- `supervisor.start` attaches to the buffer in hand.
  if supervisor.config_for(name) == nil then
    notify.error(string.format("No registered LSP configuration for '%s'", name))
    return false
  end

  if not supervisor.start(name, bufnr) then
    notify.error(string.format("Failed to start LSP '%s' -- check :LspLog", name))
    return false
  end

  notify.info(string.format("LSP '%s' starting...", name))

  -- Check attachment after short delay (LSP startup is async).
  -- The buffer handle is captured here; revalidate it before use because the
  -- buffer may have been deleted during the 1.5s window (deferred-handle guard).
  vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    if is_server_running(name, bufnr) then
      notify.info(string.format("✓ LSP '%s' attached successfully", name))
    else
      -- Now a real failure rather than the expected outcome: the client was
      -- created against this buffer, so if it is not here it did not survive.
      notify.warn(
        string.format("⚠ LSP '%s' started but did not stay attached -- check :LspLog", name)
      )
    end
  end, 1500) -- 1.5s delay for server startup

  return true
end

--- Execute LspStartHere command
---@param args table vim.api.nvim_create_user_command args
---@return nil
function M.execute(args)
  local bufnr = vim.api.nvim_get_current_buf()

  if args.args and args.args ~= "" then
    -- Start specific server
    start_lsp(args.args, bufnr)
  else
    -- Auto-detect based on filetype
    local servers = M.get_servers_for_buffer(bufnr)
    if #servers == 0 then
      local ft = vim.bo[bufnr].filetype
      notify.warn(string.format("No LSP configured for filetype '%s'", ft or "none"))
      return
    end

    local started = 0
    for _, name in ipairs(servers) do
      if start_lsp(name, bufnr) then
        started = started + 1
      end
    end

    notify.info(string.format("Started %d/%d LSP server(s)", started, #servers))
  end
end

return M
