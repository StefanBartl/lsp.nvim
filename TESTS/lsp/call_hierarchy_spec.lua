--- Covers `lsp.core.call_hierarchy`: the on-demand documentation.nvim fallback
--- for `lsc`/`lsC` in a Lua buffer lua_ls cannot answer call hierarchy for.
---
--- Everything documentation.nvim-shaped is stubbed through `package.loaded` --
--- the real plugin is not a dependency of lsp.nvim's CI. What is pinned here
--- is the *contract*: which root gets asked for, that a client already
--- attached skips the whole detour, and that a buffer open before `install()`
--- ran still gets the client without the user reloading it by hand.

local call_hierarchy = require("lsp.core.call_hierarchy")

--- Collect what the actions notify, without touching the real notifier.
---@return string[] said
---@return function restore
local function capture_notify()
  ---@type string[]
  local said = {}
  local real = package.loaded["lib.nvim.notify"]
  package.loaded["lib.nvim.notify"] = {
    create = function()
      return setmetatable({}, {
        __index = function(_, level)
          return function(msg)
            said[#said + 1] = level .. ": " .. tostring(msg)
          end
        end,
      })
    end,
  }
  return said, function()
    package.loaded["lib.nvim.notify"] = real
  end
end

describe("lsp.core.call_hierarchy", function()
  local bufnr
  local said, restore_notify
  local real_get_clients

  before_each(function()
    said, restore_notify = capture_notify()
    real_get_clients = vim.lsp.get_clients
    vim.cmd("enew!")
    bufnr = vim.api.nvim_get_current_buf()
    vim.bo[bufnr].filetype = "lua"
  end)

  after_each(function()
    restore_notify()
    vim.lsp.get_clients = real_get_clients
    package.loaded["documentation"] = nil
    package.loaded["lazy"] = nil
    package.loaded["fzf-lua"] = nil
    package.loaded["lsp.servers.lua_ls.rootresolver"] = nil
  end)

  it("skips documentation.nvim entirely when a client already answers", function()
    vim.lsp.get_clients = function(filter)
      if filter and filter.method == "textDocument/prepareCallHierarchy" then
        return { {} }
      end
      return {}
    end
    local opened = {}
    package.loaded["fzf-lua"] = {
      lsp_incoming_calls = function()
        opened[#opened + 1] = "in"
      end,
      lsp_outgoing_calls = function()
        opened[#opened + 1] = "out"
      end,
    }
    -- documentation.nvim deliberately left unstubbed: if this were reached,
    -- `require("documentation")` would fail and the case would notify instead.
    call_hierarchy.incoming()
    call_hierarchy.outgoing()
    assert.are.same({ "in", "out" }, opened)
    assert.are.same({}, said)
  end)

  it("says so, without a picker, in a non-Lua buffer with no answering client", function()
    vim.bo[bufnr].filetype = "typescript"
    vim.lsp.get_clients = function()
      return {}
    end
    local opened = false
    package.loaded["fzf-lua"] = {
      lsp_incoming_calls = function()
        opened = true
      end,
    }
    call_hierarchy.incoming()
    assert.is_false(opened)
    assert.are.equal(1, #said)
    assert.is_truthy(said[1]:find("no attached server", 1, true))
  end)

  it("says documentation.nvim is needed when it cannot be found at all", function()
    vim.lsp.get_clients = function()
      return {}
    end
    call_hierarchy.incoming()
    assert.are.equal(1, #said)
    assert.is_truthy(said[1]:find("documentation.nvim", 1, true))
  end)

  it("installs a handle for the buffer's own root and opens the picker", function()
    vim.lsp.get_clients = function(filter)
      if filter and filter.method == "textDocument/prepareCallHierarchy" then
        return {}
      end
      return {}
    end
    package.loaded["lsp.servers.lua_ls.rootresolver"] = function(b)
      assert.are.equal(bufnr, b)
      return "/project/root"
    end
    local install_opts
    package.loaded["documentation"] = {
      install = function(opts)
        install_opts = opts
        return { root = opts.root }
      end,
    }
    local exec_autocmds_calls = {}
    local real_exec = vim.api.nvim_exec_autocmds
    vim.api.nvim_exec_autocmds = function(event, opts)
      exec_autocmds_calls[#exec_autocmds_calls + 1] = { event = event, opts = opts }
      -- Simulate documentation.nvim's own BufReadPost handler attaching now.
      vim.lsp.get_clients = function(filter)
        if filter and filter.method == "textDocument/prepareCallHierarchy" then
          return { {} }
        end
        return {}
      end
    end
    local opened = {}
    package.loaded["fzf-lua"] = {
      lsp_incoming_calls = function()
        opened[#opened + 1] = "in"
      end,
    }

    call_hierarchy.incoming()
    vim.api.nvim_exec_autocmds = real_exec

    assert.are.same({ root = "/project/root", callhierarchy = true }, install_opts)
    assert.are.equal(1, #exec_autocmds_calls)
    assert.are.same({ "BufReadPost", "BufNewFile" }, exec_autocmds_calls[1].event)
    assert.are.equal(bufnr, exec_autocmds_calls[1].opts.buffer)
    assert.are.same({ "in" }, opened)
  end)

  it("force-loads a lazy documentation.nvim through lazy.nvim before requiring it", function()
    vim.lsp.get_clients = function()
      return {}
    end
    package.loaded["lsp.servers.lua_ls.rootresolver"] = function()
      return "/project/root"
    end
    local loaded_plugins
    package.loaded["lazy"] = {
      load = function(opts)
        loaded_plugins = opts.plugins
        -- Once lazy.nvim has "loaded" it, a bare require would succeed.
        package.loaded["documentation"] = {
          install = function()
            return {}
          end,
        }
      end,
    }
    local real_exec = vim.api.nvim_exec_autocmds
    vim.api.nvim_exec_autocmds = function() end

    call_hierarchy.incoming()
    vim.api.nvim_exec_autocmds = real_exec

    assert.are.same({ "documentation.nvim" }, loaded_plugins)
  end)

  it("warns instead of raising when install() itself fails", function()
    vim.lsp.get_clients = function()
      return {}
    end
    package.loaded["lsp.servers.lua_ls.rootresolver"] = function()
      return "/project/root"
    end
    package.loaded["documentation"] = {
      install = function()
        error("scan failed")
      end,
    }
    call_hierarchy.incoming()
    local warned = false
    for _, line in ipairs(said) do
      if line:find("^warn:") then
        warned = true
      end
    end
    assert.is_true(warned)
  end)
end)
