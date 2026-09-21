--- Covers `lsp.core.gitsigns_actions`: gitsigns' hunk actions arriving as code
--- actions from an in-process language server.
---
--- The server is exercised for real -- `vim.lsp.start` with the module's own
--- `cmd` function, no process involved -- because "does Neovim accept this as a
--- server, and does `codeAction` reach it and come back" is the part a stub
--- cannot answer. gitsigns is stubbed: the case is about what the server does
--- with the hunks gitsigns reports, not about gitsigns.

local gs_actions = require("lsp.core.gitsigns_actions")

describe("lsp.core.gitsigns_actions", function()
  ---@type integer
  local bufnr
  ---@type string[]
  local ran
  ---@type table[]
  local hunks

  before_each(function()
    ran = {}
    hunks = {}
    package.loaded["gitsigns"] = {
      get_hunks = function()
        return hunks
      end,
      stage_hunk = function()
        ran[#ran + 1] = "stage"
      end,
      reset_hunk = function()
        ran[#ran + 1] = "reset"
      end,
      preview_hunk = function()
        ran[#ran + 1] = "preview"
      end,
    }
    vim.cmd("enew!")
    bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d", "e", "f" })
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ".lua")
  end)

  after_each(function()
    gs_actions.detach()
    package.loaded["gitsigns"] = nil
    for _, client in ipairs(vim.lsp.get_clients({ name = gs_actions.NAME })) do
      client:stop(true)
    end
  end)

  describe("touches_hunk", function()
    it("is true for a line inside an added hunk, and false just outside", function()
      hunks = { { added = { start = 3, count = 2 } } } -- 1-based lines 3..4 = 0-based 2..3
      assert.is_true(gs_actions.touches_hunk(bufnr, 2, 2))
      assert.is_true(gs_actions.touches_hunk(bufnr, 3, 3))
      assert.is_false(gs_actions.touches_hunk(bufnr, 1, 1))
      assert.is_false(gs_actions.touches_hunk(bufnr, 4, 4))
    end)

    it("counts a pure deletion as the one line it sits on", function()
      hunks = { { added = { start = 4, count = 0 }, removed = { start = 4, count = 2 } } }
      assert.is_true(gs_actions.touches_hunk(bufnr, 3, 3))
      assert.is_false(gs_actions.touches_hunk(bufnr, 2, 2))
    end)

    -- gitsigns' own `find_hunk` has both of these as special cases (and so do
    -- its signs): a deletion above the first line is `added.start == 0`, drawn
    -- and acted on at line 1, and one after the last line is `line_count + 1`,
    -- acted on from the last line. The hunk is real in both, and `Stage hunk`
    -- works there -- it just was not offered.
    it("counts a deletion above the first line as line 1", function()
      hunks = {
        { type = "delete", added = { start = 0, count = 0 }, removed = { start = 1, count = 2 } },
      }
      assert.is_true(gs_actions.touches_hunk(bufnr, 0, 0))
      assert.is_false(gs_actions.touches_hunk(bufnr, 1, 1))
    end)

    it("counts a deletion after the last line as the last line", function()
      -- Six lines: the sign of a deletion past the end is `added.start == 7`.
      hunks = {
        { type = "delete", added = { start = 7, count = 0 }, removed = { start = 7, count = 1 } },
      }
      assert.is_true(gs_actions.touches_hunk(bufnr, 5, 5))
      assert.is_false(gs_actions.touches_hunk(bufnr, 4, 4))
    end)

    it("is true when a selection overlaps a hunk", function()
      hunks = { { added = { start = 3, count = 1 } } }
      assert.is_true(gs_actions.touches_hunk(bufnr, 0, 5))
      assert.is_false(gs_actions.touches_hunk(bufnr, 0, 1))
    end)

    it("is false without hunks, without gitsigns, and when gitsigns raises", function()
      hunks = {}
      assert.is_false(gs_actions.touches_hunk(bufnr, 0, 5))

      package.loaded["gitsigns"] = {
        get_hunks = function()
          error("boom")
        end,
      }
      assert.is_false(gs_actions.touches_hunk(bufnr, 0, 5))

      package.loaded["gitsigns"] = nil
      package.preload["gitsigns"] = function()
        error("not installed")
      end
      assert.is_false(gs_actions.touches_hunk(bufnr, 0, 5))
      package.preload["gitsigns"] = nil
    end)
  end)

  describe("code_actions", function()
    ---@param first integer
    ---@param last integer
    ---@return table
    local function params(first, last)
      return {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        range = {
          start = { line = first, character = 0 },
          ["end"] = { line = last, character = 0 },
        },
        context = { diagnostics = {} },
      }
    end

    it("offers stage, reset and preview on a hunk, as commands", function()
      hunks = { { added = { start = 3, count = 1 } } }
      local out = gs_actions.code_actions(params(2, 2))
      assert.are.equal(3, #out)
      assert.are.same(
        { "Stage hunk", "Reset hunk", "Preview hunk" },
        vim.tbl_map(function(a)
          return a.command.title
        end, out)
      )
      for _, action in ipairs(out) do
        assert.is_truthy(action.title:find("gitsigns", 1, true))
        assert.is_truthy(action.command.command:find("^lsp_nvim%.gitsigns%."))
      end
    end)

    -- The kind is what keeps the code-action indicator from lighting on every
    -- changed line: it lights on quickfix and source, and treats no kind at all
    -- as a match.
    it("uses a kind the indicator's default allowlist does not light on", function()
      hunks = { { added = { start = 3, count = 1 } } }
      local lightbulb = require("lsp.core.lightbulb")
      lightbulb.setup({ enable = true, kinds = { "quickfix", "source" } })
      local out = gs_actions.code_actions(params(2, 2))
      assert.are.equal(0, lightbulb._countable(out))
      lightbulb.detach()
    end)

    it("offers nothing off a hunk", function()
      hunks = { { added = { start = 3, count = 1 } } }
      assert.are.same({}, gs_actions.code_actions(params(0, 0)))
    end)
  end)

  describe("as a language server", function()
    ---@return vim.lsp.Client
    local function start()
      local id = vim.lsp.start({
        name = gs_actions.NAME,
        cmd = gs_actions.server,
        root_dir = nil,
      }, { bufnr = bufnr })
      assert.is_number(id)
      return assert(vim.lsp.get_client_by_id(id))
    end

    it("initializes and advertises only code actions", function()
      local client = start()
      assert.is_truthy(client.server_capabilities.codeActionProvider)
      assert.is_nil(client.server_capabilities.hoverProvider)
      assert.is_nil(client.server_capabilities.documentSymbolProvider)
    end)

    it("answers textDocument/codeAction through Neovim's own client", function()
      hunks = { { added = { start = 3, count = 1 } } }
      local client = start()
      local response = client:request_sync("textDocument/codeAction", {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        range = {
          start = { line = 2, character = 0 },
          ["end"] = { line = 2, character = 0 },
        },
        context = { diagnostics = {} },
      }, 2000, bufnr)
      assert.is_not_nil(response)
      assert.is_nil(response.err)
      assert.are.equal(3, #response.result)
    end)

    -- Neovim tells a synchronous in-process server's requests apart from
    -- pending ones by the fourth argument of `request`, called once the reply
    -- is out. A server that never calls it leaves every request registered as
    -- pending on `client.requests` -- one entry per code-action query, and the
    -- lightbulb asks on every CursorHold -- and `LspRequest` never sees one
    -- complete.
    it("leaves no request pending on Neovim's client once it has answered", function()
      hunks = { { added = { start = 3, count = 1 } } }
      local client = start()
      for _ = 1, 3 do
        local response = client:request_sync("textDocument/codeAction", {
          textDocument = { uri = vim.uri_from_bufnr(bufnr) },
          range = {
            start = { line = 2, character = 0 },
            ["end"] = { line = 2, character = 0 },
          },
          context = { diagnostics = {} },
        }, 2000, bufnr)
        assert.is_not_nil(response)
      end
      assert.are.equal(0, vim.tbl_count(client.requests))
    end)

    it("answers an unknown request with an error, not silence", function()
      local client = start()
      local response = client:request_sync("textDocument/hover", {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        position = { line = 0, character = 0 },
      }, 2000, bufnr)
      assert.is_not_nil(response)
      assert.is_not_nil(response.err)
      assert.are.equal(-32601, response.err.code)
    end)

    it("shows up among the buffer's code-action providers", function()
      start()
      local providers = vim.lsp.get_clients({
        bufnr = bufnr,
        method = "textDocument/codeAction",
      })
      assert.are.equal(gs_actions.NAME, providers[1].name)
    end)
  end)

  describe("setup", function()
    it("does nothing while code_actions.gitsigns is off", function()
      gs_actions.setup({ gitsigns = false })
      vim.b[bufnr].gitsigns_status_dict = {}
      vim.api.nvim_exec_autocmds("User", {
        pattern = "GitSignsUpdate",
        data = { buffer = bufnr },
      })
      vim.wait(100)
      assert.are.equal(0, #vim.lsp.get_clients({ name = gs_actions.NAME, bufnr = bufnr }))
    end)

    it("attaches to a buffer gitsigns reports on, once, and runs its actions", function()
      gs_actions.setup({ gitsigns = true })
      vim.b[bufnr].gitsigns_status_dict = {}
      vim.api.nvim_exec_autocmds("User", {
        pattern = "GitSignsUpdate",
        data = { buffer = bufnr },
      })
      vim.api.nvim_exec_autocmds("User", {
        pattern = "GitSignsUpdate",
        data = { buffer = bufnr },
      })
      vim.wait(2000, function()
        return #vim.lsp.get_clients({ name = gs_actions.NAME, bufnr = bufnr }) > 0
      end, 10)

      local clients = vim.lsp.get_clients({ name = gs_actions.NAME })
      assert.are.equal(1, #clients)

      -- The real command handler, the one `attach` registered.
      for _, command in ipairs({ "stage_hunk", "reset_hunk", "preview_hunk" }) do
        clients[1]:exec_cmd({
          title = command,
          command = "lsp_nvim.gitsigns." .. command,
        }, { bufnr = bufnr })
      end
      vim.wait(1000, function()
        return #ran == 3
      end, 10)
      assert.are.same({ "stage", "reset", "preview" }, ran)
    end)

    it("does not attach to a buffer gitsigns is not attached to", function()
      gs_actions.setup({ gitsigns = true })
      vim.api.nvim_exec_autocmds("User", {
        pattern = "GitSignsUpdate",
        data = { buffer = bufnr },
      })
      vim.wait(100)
      -- This buffer, not the client: an earlier case's buffer still carries
      -- `gitsigns_status_dict`, and `setup()` attaches to every buffer that does.
      assert.are.equal(0, #vim.lsp.get_clients({ name = gs_actions.NAME, bufnr = bufnr }))
    end)

    it("stops its client on detach", function()
      gs_actions.setup({ gitsigns = true })
      vim.b[bufnr].gitsigns_status_dict = {}
      vim.api.nvim_exec_autocmds("User", {
        pattern = "GitSignsUpdate",
        data = { buffer = bufnr },
      })
      vim.wait(2000, function()
        return #vim.lsp.get_clients({ name = gs_actions.NAME }) > 0
      end, 10)
      gs_actions.detach()
      vim.wait(2000, function()
        return #vim.lsp.get_clients({ name = gs_actions.NAME }) == 0
      end, 10)
      assert.are.equal(0, #vim.lsp.get_clients({ name = gs_actions.NAME }))
    end)
  end)
end)
