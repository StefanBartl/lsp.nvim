--- Covers `lsp.core.util`'s notion of lsp.nvim's *own* clients: the in-process
--- ones (today `lsp.nvim-gitsigns`) that answer a request or two without being a
--- language server.
---
--- They are real clients as far as Neovim is concerned, so every consumer of
--- `vim.lsp.get_clients()` sees them: the winbar's "is a server attached" guard,
--- `:Lsp stop` / `:Lsp restart`, the stop completion. What those consumers want
--- is the language servers, and this is the one place that says which is which.

local util = require("lsp.core.util")
local gs_actions = require("lsp.core.gitsigns_actions")

describe("lsp.core.util internal clients", function()
  describe("is_internal_name", function()
    it("recognises the prefix, and only the prefix", function()
      assert.is_true(util.is_internal_name("lsp.nvim-gitsigns"))
      assert.is_true(util.is_internal_name("lsp.nvim-anything-else"))
      assert.is_false(util.is_internal_name("lua_ls"))
      assert.is_false(util.is_internal_name("lsp.nvim"))
      assert.is_false(util.is_internal_name("my-lsp.nvim-thing"))
    end)

    it("is false for what is not a name", function()
      assert.is_false(util.is_internal_name(nil))
      assert.is_false(util.is_internal_name(42))
      assert.is_false(util.is_internal_name({}))
    end)

    it("knows the gitsigns client by the name it starts under", function()
      assert.is_true(util.is_internal_name(gs_actions.NAME))
    end)
  end)

  describe("is_internal", function()
    it("reads the client's name", function()
      assert.is_true(util.is_internal({ name = "lsp.nvim-gitsigns" }))
      assert.is_false(util.is_internal({ name = "ts_ls" }))
    end)

    it("is false for a client without a name, and for nil", function()
      assert.is_false(util.is_internal({}))
      assert.is_false(util.is_internal(nil))
    end)
  end)

  describe("server_clients", function()
    local real_get_clients

    before_each(function()
      real_get_clients = vim.lsp.get_clients
    end)

    after_each(function()
      vim.lsp.get_clients = real_get_clients
    end)

    it("drops the in-process clients and keeps the language servers, in order", function()
      local asked
      vim.lsp.get_clients = function(filter)
        asked = filter
        return {
          { id = 1, name = "lsp.nvim-gitsigns" },
          { id = 2, name = "lua_ls" },
          { id = 3, name = "marksman" },
        }
      end

      local got = util.server_clients(5)

      assert.are.equal(5, asked.bufnr)
      assert.are.same(
        { "lua_ls", "marksman" },
        vim.tbl_map(function(client)
          return client.name
        end, got)
      )
    end)

    it("defaults to the current buffer, like get_clients does with 0", function()
      local asked
      vim.lsp.get_clients = function(filter)
        asked = filter
        return {}
      end
      util.server_clients()
      assert.are.equal(0, asked.bufnr)
    end)
  end)
end)
