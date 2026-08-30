---@module 'lsp.lspdoctor.health'
---@brief `:LspDoctor startup` -- is this buffer's LSP actually working?
---@description
--- Answers one question per expected server: is it configured, is it running,
--- and if not, what to do about it. `inspect.lua` answers the wider ones
--- (`buffer` and `capabilities`: clients, diagnostics, conflicts, workspace,
--- capability sets).
---
--- The report was called `health` until 2026-08-29. It is `startup` now, and
--- the file kept its name: what it does is check whether the server started.
---
--- Which options apply here follows from that split, and it is not all of
--- them. `show_capabilities`, `show_workspace` and `show_conflicts` belong to
--- the `capabilities` report and `inspect.lua` honours them; repeating them
--- here would mean two implementations of the same report. What this module
--- honours:
---
--- - `list_limit` -- caps the per-server detail, so a filetype with a long
---   server list still produces a readable report.
--- - `show_tools` -- the "external tools summary": whether each expected
---   server's executable can actually be resolved. A server that is configured
---   and not running because its binary is missing is the single most common
---   case this report exists for, and nothing was checking it.
--- - `semantic_tokens_timeout` -- bounds the semantic-tokens probe below.
---
--- The last two used to be read by nothing at all, anywhere in the plugin:
--- documented in `@types.lua` and `README.md`, defaulted in `init.lua`,
--- consumed nowhere. They are real now.
---
---@see lsp.lspdoctor.inspect

local M = {}

local lsp = vim.lsp

--- Options handed down by `lsp.lspdoctor.setup()`.
---
--- This used to assign to a bare `Opts`, i.e. to a global.
---@type table
local Opts = {}

---@param opts table
---@return nil
function M.setup(opts)
  Opts = opts or {}
end

--- Check if server is running for buffer
---@param name string
---@param bufnr integer
---@return boolean
local function is_running(name, bufnr)
  local clients = lsp.get_clients({ bufnr = bufnr, name = name })
  return #clients > 0
end

--- Get expected servers for buffer
---@param bufnr integer
---@return string[]
local function get_expected_servers(bufnr)
  local ok, start_mod = pcall(require, "lsp.usercmds.start")
  if not ok then
    return {}
  end

  if type(start_mod.get_servers_for_buffer) == "function" then
    return start_mod.get_servers_for_buffer(bufnr)
  end

  return {}
end

---@internal
--- The resolved config for a named server, or nil.
---
--- `vim.lsp.config` is a table with an `__index` that resolves and merges the
--- config for a name -- it has no `get()`. This module used to check
--- `lsp.config.get` and bail when it was missing, which it always is, so
--- `config_exists()` reported "no config" for every server including the ones
--- that were running. Wrapped in pcall because indexing an unknown name goes
--- through that resolver.
---@param name string
---@return table|nil
local function config_for(name)
  if type(lsp.config) ~= "table" then
    return nil
  end
  local ok, cfg = pcall(function()
    return lsp.config[name]
  end)
  if ok and type(cfg) == "table" then
    return cfg
  end
  return nil
end

--- Check if config exists
---@param name string
---@return boolean
local function config_exists(name)
  return config_for(name) ~= nil
end

--- Get server state/attempts
---@param name string
---@return integer attempts, string|nil last_error
local function get_server_state(name)
  local ok, state_mod = pcall(require, "lsp.usercmds.state")
  if not ok or type(state_mod.state) ~= "table" then
    return 0, nil
  end

  local state = state_mod.state
  local attempts = (state.attempts and state.attempts[name]) or 0
  local last_error = (state.last_error and state.last_error[name]) or nil

  return attempts, last_error
end

---@internal
--- Where a server's executable resolves to, if at all.
---
--- Reads the command out of the resolved config rather than guessing from the
--- server name: `lua_ls` is `lua-language-server`, `ts_ls` is
--- `typescript-language-server`, and a config may pin an absolute path.
---@param name string
---@return boolean found
---@return string detail # resolved path, or the command that could not be found
local function executable_for(name)
  local cfg = config_for(name)
  if cfg == nil then
    return false, "no config"
  end

  local cmd = cfg.cmd
  if type(cmd) == "function" then
    -- A command built at start time cannot be probed without starting it.
    return true, "built dynamically (cmd is a function)"
  end

  local binary = (type(cmd) == "table") and cmd[1] or cmd
  if type(binary) ~= "string" or binary == "" then
    return false, "no command in config"
  end

  local path = vim.fn.exepath(binary)
  if path ~= "" then
    return true, path
  end
  return false, binary
end

---@internal
--- Does a running client that advertises semantic tokens actually answer?
---
--- "Advertises the capability and never responds" is a failure mode that looks
--- like nothing at all -- highlighting is simply duller than it should be --
--- so it is worth one bounded request. `semantic_tokens_timeout` is the bound;
--- a server busy indexing a large project legitimately needs more than the
--- default 300ms, which is why it is an option rather than a constant.
---@param name string
---@param bufnr integer
---@return string|nil line # nil when the server does not advertise the capability
local function semantic_tokens_probe(name, bufnr)
  local clients = lsp.get_clients({ bufnr = bufnr, name = name })
  local client = clients[1]
  if client == nil then
    return nil
  end

  local provider = client.server_capabilities and client.server_capabilities.semanticTokensProvider
  if not provider then
    return nil
  end

  local timeout = Opts.semantic_tokens_timeout or 300
  local ok, responses = pcall(
    lsp.buf_request_sync,
    bufnr,
    "textDocument/semanticTokens/full",
    { textDocument = lsp.util.make_text_document_params(bufnr) },
    timeout
  )

  if not ok or responses == nil then
    return ("  Semantic tokens: ❌ no answer within %dms"):format(timeout)
  end
  for _, response in pairs(responses) do
    if response.result ~= nil then
      return ("  Semantic tokens: ✅ answered within %dms"):format(timeout)
    end
    if response.error ~= nil then
      return ("  Semantic tokens: ❌ error: %s"):format(tostring(response.error.message))
    end
  end
  return ("  Semantic tokens: ❌ no answer within %dms"):format(timeout)
end

--- Perform health check
---@param bufnr integer
---@return string[] lines, table results
function M.check(bufnr)
  local lines = {}
  local results = {}

  local expected = get_expected_servers(bufnr)

  if #expected == 0 then
    table.insert(lines, "⚠️  No LSP servers configured for this buffer")
    table.insert(lines, "   Filetype: " .. vim.bo[bufnr].filetype)
    return lines, results
  end

  -- `list_limit` caps the detail, not the summary: the counts below still
  -- cover every expected server, so a truncated report never misreports how
  -- many are running.
  local limit = Opts.list_limit or 10
  local detailed = 0

  for _, name in ipairs(expected) do
    local running = is_running(name, bufnr)
    local has_config = config_exists(name)
    local attempts, last_error = get_server_state(name)

    table.insert(results, {
      name = name,
      running = running,
      config_exists = has_config,
      attempts = attempts,
      last_error = last_error,
    })

    if detailed < limit then
      detailed = detailed + 1

      -- Build status line
      table.insert(lines, "")
      table.insert(lines, string.format("**%s**", name))
      table.insert(lines, string.format("  Running: %s", running and "✅ Yes" or "❌ No"))
      table.insert(lines, string.format("  Config: %s", has_config and "✅ Yes" or "❌ No"))
      table.insert(lines, string.format("  Attempts: %d", attempts))

      if Opts.show_tools ~= false then
        local found, detail = executable_for(name)
        table.insert(lines, string.format("  Executable: %s %s", found and "✅" or "❌", detail))
      end

      if last_error then
        table.insert(lines, string.format("  Error: `%s`", last_error))
      end

      if running then
        local probe = semantic_tokens_probe(name, bufnr)
        if probe then
          table.insert(lines, probe)
        end
      end

      -- Diagnostic hints
      if not running then
        if not has_config then
          table.insert(
            lines,
            "  💡 **Action**: Server not configured - check `lsp.config` or registry"
          )
        elseif Opts.show_tools ~= false and not executable_for(name) then
          -- Checked before the generic hints: "the binary is not on $PATH" is
          -- both the commonest cause and the only one with a different fix.
          table.insert(
            lines,
            "  💡 **Action**: Executable not found - install it (`:Mason`) or fix $PATH"
          )
        elseif attempts > 0 then
          table.insert(lines, "  💡 **Action**: Start failed - check `:LspLog` or `:messages`")
        else
          table.insert(lines, "  💡 **Action**: Not started - use `:Lsp start " .. name .. "`")
        end
      end
    end
  end

  if #expected > detailed then
    table.insert(lines, "")
    table.insert(
      lines,
      string.format(
        "… %d more expected server(s) not detailed (list_limit = %d)",
        #expected - detailed,
        limit
      )
    )
  end

  -- Summary
  local running_count = 0
  for _, r in ipairs(results) do
    if r.running then
      running_count = running_count + 1
    end
  end

  table.insert(lines, 1, "")
  table.insert(lines, 1, string.format("Summary: %d/%d servers running", running_count, #expected))
  table.insert(lines, 1, string.rep("─", 50))

  return lines, results
end

return M
