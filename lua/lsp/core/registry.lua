---@module 'lsp.core.registry'
--- Resolves configured server names to their `lsp.servers.*` modules.
---
--- `setup_all(shared, servers)` tries the plain and the `webdev.`-prefixed
--- path for each name and returns the ones that loaded. The list itself is
--- configuration (`servers` in `config/DEFAULTS.lua`), not a constant in here:
--- it used to be a hardcoded `ACTIVE` table, which made turning a server on or
--- off an edit to this module (roadmap finding B7).

local notify = require("lib.nvim.notify").create("[lsp.core.registry]")

local M = {}

local desc_tag = "[lsp.registry] "

--- Set up every configured server with the shared capabilities/attach table.
---@param shared table # capabilities, on_attach, on_init, formatter
---@param servers string[] # server names, from `config.get().servers`
---@return string[] enabled # the names whose module loaded and set up cleanly
function M.setup_all(shared, servers)
  if type(shared) ~= "table" or type(servers) ~= "table" then
    return {}
  end

  -- macOS used to append "mobiledev.sourcekit" here. That belongs in the
  -- `servers` option now, per platform, not in this loop.

  local enabled = {}

  for _, name in ipairs(servers) do
    -- Versuche beide Pfade: direkter Name und webdev-Präfix
    local paths = {
      "lsp.servers." .. name,
    }

    -- Falls Name kein Punkt enthält, auch webdev-Variante versuchen
    if not name:match("%.") then
      paths[#paths + 1] = "lsp.servers.webdev." .. name
    end

    -- if not name:match("%.") then
    --   paths[#paths + 1] = "lsp.servers.mobiledev." .. name
    -- end

    local loaded = false
    local last_error = nil

    for _, mod_path in ipairs(paths) do
      local ok, srv = pcall(require, mod_path)
      if ok and type(srv) == "table" and type(srv.setup) == "function" then
        local ok_setup, err = pcall(srv.setup, shared)
        if ok_setup then
          enabled[#enabled + 1] = name
          loaded = true
          break
        else
          last_error = err
        end
      end
    end

    if not loaded then
      if last_error then
        notify.warn((desc_tag .. "setup failed for '%s': %s"):format(name, last_error or "?"))
      else
        -- This used to read `("… '%s' unavailable"):format()):format(name)` --
        -- an inner `format()` with no argument for its `%s`, which raises
        -- "bad argument #1 to 'format'". Nothing here is pcall-wrapped, so a
        -- single configured server without a module aborted the whole loop and
        -- took `setup()` with it. It never fired only because every configured
        -- name happened to resolve.
        notify.info((desc_tag .. "server module '%s' unavailable"):format(name))
      end
    end
  end

  return enabled
end

return M
