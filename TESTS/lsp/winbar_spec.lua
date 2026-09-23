--- Covers `lsp.core.winbar`: which parts the breadcrumb has, when a window
--- gets one, and what happens to a `'winbar'` that is not this module's.
---
--- Two rules carry the design and are pinned here. The depth cap (`markdown`
--- shows the file's own top heading and nothing below it) is what keeps a
--- nested outline from becoming a table of contents. The ownership rule --
--- written over whatever is in an eligible window, but only *cleared* when the
--- string in it is this module's -- is what lets it share the option with a
--- plugin that puts its own text on a help or terminal window.
---
--- The language server is a stub: `vim.lsp.get_clients` answers with a client
--- whose `request` calls back at once. What is under test is what the module
--- does with an answer, and the request path is covered by `symbols_spec`.

local winbar = require("lsp.core.winbar")
local symbols = require("lsp.core.symbols")

---@param name string
---@param kind integer
---@param from integer[]
---@param to integer[]
---@param children? table[]
---@return table
local function sym(name, kind, from, to, children)
  local range = {
    start = { line = from[1], character = from[2] },
    ["end"] = { line = to[1], character = to[2] },
  }
  return { name = name, kind = kind, range = range, selectionRange = range, children = children }
end

---@param parts LspWinbar.Part[]
---@return string[]
local function texts(parts)
  return vim.tbl_map(function(part)
    return part.text
  end, parts)
end

--- Nodes as the module receives them, from a plain `DocumentSymbol` list.
---@param items table[]
---@return LspSymbols.Node[]
local function tree(items)
  return symbols.normalize(items)
end

describe("lsp.core.winbar", function()
  after_each(function()
    winbar.detach()
    symbols.reset()
  end)

  describe("parts", function()
    it("is the folder, the file and then the symbols, outermost first", function()
      winbar.setup({})
      local path =
        tree({ sym("Repo", 5, { 0, 0 }, { 5, 0 }, { sym("find", 6, { 1, 0 }, { 2, 0 }) }) })
      local flat = { path[1], path[1].children[1] }

      local parts =
        winbar.parts({ name = "/proj/src/repo.ts", filetype = "typescript", path = flat })
      assert.are.same({ "src", "repo.ts", "Repo", "find" }, texts(parts))
      assert.are.same(
        { "folder", "file", "symbol", "symbol" },
        vim.tbl_map(function(p)
          return p.role
        end, parts)
      )
    end)

    it("shows `folder_level` directories", function()
      winbar.setup({ folder_level = 2 })
      local parts = winbar.parts({ name = "/a/b/c/file.lua", filetype = "lua", path = {} })
      assert.are.same({ "b", "c", "file.lua" }, texts(parts))

      winbar.setup({ folder_level = 0 })
      parts = winbar.parts({ name = "/a/b/c/file.lua", filetype = "lua", path = {} })
      assert.are.same({ "file.lua" }, texts(parts))
    end)

    it("leaves out the path when show_file is off", function()
      winbar.setup({ show_file = false })
      local path = tree({ sym("Repo", 5, { 0, 0 }, { 5, 0 }) })
      local parts = winbar.parts({ name = "/x/y.lua", filetype = "lua", path = path })
      assert.are.same({ "Repo" }, texts(parts))
    end)

    it("does not fail on a buffer with no name", function()
      winbar.setup({})
      local parts = winbar.parts({ name = "", filetype = "", path = {} })
      assert.are.same({ "[No Name]" }, texts(parts))
    end)

    it("does not fail on a file in the root of a drive", function()
      winbar.setup({})
      local parts = winbar.parts({ name = "/file.lua", filetype = "lua", path = {} })
      assert.are.same({ "file.lua" }, texts(parts))
    end)

    it("skips a symbol with no name instead of drawing an empty chip", function()
      winbar.setup({})
      local path = tree({ sym("", 12, { 0, 0 }, { 1, 0 }) })
      local parts = winbar.parts({ name = "/x/y.lua", filetype = "lua", path = path })
      assert.are.same({ "x", "y.lua" }, texts(parts))
    end)

    describe("the depth cap", function()
      local headings = tree({
        sym("H1", 15, { 0, 0 }, { 9, 0 }, {
          sym("H2", 15, { 2, 0 }, { 8, 0 }, { sym("H3", 15, { 4, 0 }, { 7, 0 }) }),
        }),
      })
      local chain = { headings[1], headings[1].children[1], headings[1].children[1].children[1] }

      it("cuts markdown to the top heading by default", function()
        winbar.setup({})
        local parts = winbar.parts({ name = "/d/notes.md", filetype = "markdown", path = chain })
        assert.are.same({ "d", "notes.md", "H1" }, texts(parts))
      end)

      it("does not cap a filetype it does not name", function()
        winbar.setup({})
        local parts = winbar.parts({ name = "/d/notes.lua", filetype = "lua", path = chain })
        assert.are.same({ "d", "notes.lua", "H1", "H2", "H3" }, texts(parts))
      end)

      it("takes a cap per filetype, and lets one lift the markdown default", function()
        winbar.setup({ max_symbols = { lua = 1, markdown = false } })
        local lua = winbar.parts({ name = "/d/a.lua", filetype = "lua", path = chain })
        assert.are.same({ "d", "a.lua", "H1" }, texts(lua))
        local md = winbar.parts({ name = "/d/a.md", filetype = "markdown", path = chain })
        assert.are.same({ "d", "a.md", "H1", "H2", "H3" }, texts(md))
      end)

      it("a cap of zero shows the path and no symbol at all", function()
        winbar.setup({ max_symbols = { markdown = 0 } })
        local parts = winbar.parts({ name = "/d/a.md", filetype = "markdown", path = chain })
        assert.are.same({ "d", "a.md" }, texts(parts))
      end)
    end)
  end)

  describe("resolution", function()
    it("is on by default and follows the global switch", function()
      winbar.setup({})
      assert.is_true(winbar.enabled(nil))
      assert.is_true(winbar.enabled("lua"))
      winbar.setup({ enable = false })
      assert.is_false(winbar.enabled("lua"))
    end)

    it("lets a filetype say 'off here' against a global on, and 'on here' against off", function()
      winbar.setup({ enable = true, filetypes = { markdown = false } })
      assert.is_false(winbar.enabled("markdown"))
      assert.is_true(winbar.enabled("lua"))

      winbar.setup({ enable = false, filetypes = { lua = true } })
      assert.is_true(winbar.enabled("lua"))
      assert.is_false(winbar.enabled("go"))
    end)

    it("toggling a filetype writes an override even when it equals the global", function()
      winbar.setup({ enable = true })
      winbar.toggle("lua") -- off for lua
      winbar.toggle("lua") -- and on again: an explicit override, not the default
      assert.are.same({ "lua" }, winbar.overridden())
      winbar.set(false) -- a later global change must not undo it
      assert.is_true(winbar.enabled("lua"))
      winbar.clear("lua")
      assert.is_false(winbar.enabled("lua"))
    end)

    it("ignores filetypes entries that are not string = boolean", function()
      winbar.setup({ filetypes = { lua = "yes", [1] = true, go = false } })
      assert.are.same({ "go" }, winbar.overridden())
    end)
  end)

  describe("in a window", function()
    local real_get_clients
    ---@type integer
    local bufnr
    ---@type integer
    local win
    ---@type string
    local dir

    ---@return table
    local function stub_client()
      local client = {
        id = 1,
        name = "stub",
        offset_encoding = "utf-8",
        server_capabilities = { documentSymbolProvider = true },
      }
      function client:request(_, _, handler)
        handler(nil, {
          sym("Repo", 5, { 0, 0 }, { 4, 1 }, { sym("find", 6, { 1, 2 }, { 3, 3 }) }),
        })
        return true, 1
      end
      function client:cancel_request() end
      return client
    end

    ---@return string
    local function bar()
      return vim.wo[win].winbar
    end

    before_each(function()
      real_get_clients = vim.lsp.get_clients
      symbols.reset()
      dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      local file = dir .. "/repo.ts"
      vim.fn.writefile({ "class Repo {", "  find() {", "    x", "  }", "}" }, file)
      vim.cmd("edit " .. vim.fn.fnameescape(file))
      bufnr = vim.api.nvim_get_current_buf()
      win = vim.api.nvim_get_current_win()
      vim.bo[bufnr].filetype = "typescript"
      vim.wo[win].winbar = ""
    end)

    after_each(function()
      vim.lsp.get_clients = real_get_clients
      vim.wo[win].winbar = ""
      vim.fn.delete(dir, "rf")
    end)

    ---@param fn fun(): boolean
    local function wait_for(fn)
      vim.wait(2000, fn, 10)
    end

    it("draws the path alone when a client attaches, then the symbols under the cursor", function()
      local client = stub_client()
      vim.lsp.get_clients = function()
        return { client }
      end
      winbar.setup({ chips = false })
      vim.api.nvim_win_set_cursor(win, { 3, 4 })

      vim.api.nvim_exec_autocmds("LspAttach", { buffer = bufnr, data = { client_id = 1 } })
      wait_for(function()
        return bar():find("find", 1, true) ~= nil
      end)

      local line = bar()
      assert.is_truthy(line:find("repo.ts", 1, true))
      assert.is_truthy(line:find("Repo", 1, true))
      assert.is_truthy(line:find("find", 1, true))
    end)

    it("follows the cursor out of a method and back", function()
      local client = stub_client()
      vim.lsp.get_clients = function()
        return { client }
      end
      winbar.setup({ chips = false, debounce_ms = 0 })
      vim.api.nvim_win_set_cursor(win, { 3, 4 })
      vim.api.nvim_exec_autocmds("LspAttach", { buffer = bufnr, data = { client_id = 1 } })
      wait_for(function()
        return bar():find("find", 1, true) ~= nil
      end)

      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = bufnr })
      wait_for(function()
        return bar():find("find", 1, true) == nil
      end)
      assert.is_truthy(bar():find("Repo", 1, true))
      assert.is_nil(bar():find("find", 1, true))
    end)

    it("draws nothing for a buffer with no client attached", function()
      vim.lsp.get_clients = function()
        return {}
      end
      winbar.setup({})
      vim.api.nvim_exec_autocmds("LspAttach", { buffer = bufnr, data = { client_id = 1 } })
      vim.wait(100)
      assert.are.equal("", bar())
    end)

    -- `code_actions.gitsigns = true` attaches an in-process client to every
    -- buffer gitsigns tracks. It provides no symbols, so a buffer that has only
    -- that client is a buffer with no language server: no path-only bar.
    it("draws nothing for a buffer that only lsp.nvim's in-process client is on", function()
      vim.lsp.get_clients = function()
        return {
          {
            id = 7,
            name = "lsp.nvim-gitsigns",
            server_capabilities = { codeActionProvider = true },
          },
        }
      end
      winbar.setup({})
      vim.api.nvim_exec_autocmds("LspAttach", { buffer = bufnr, data = { client_id = 7 } })
      vim.wait(100)
      assert.are.equal("", bar())
    end)

    it("takes its breadcrumb back off when switched off, and only its own", function()
      local client = stub_client()
      vim.lsp.get_clients = function()
        return { client }
      end
      winbar.setup({ chips = false })
      vim.api.nvim_exec_autocmds("LspAttach", { buffer = bufnr, data = { client_id = 1 } })
      wait_for(function()
        return bar():find("Repo", 1, true) ~= nil
      end)

      winbar.set(false)
      wait_for(function()
        return bar() == ""
      end)
      assert.are.equal("", bar())
    end)

    it("leaves a winbar it did not write alone when it stops qualifying", function()
      local client = stub_client()
      vim.lsp.get_clients = function()
        return { client }
      end
      winbar.setup({})
      -- Someone else's text on a window this module never drew on.
      vim.wo[win].winbar = "someone else's bar"
      winbar.set(false)
      winbar.detach()
      assert.are.equal("someone else's bar", bar())
    end)

    it("writes over another plugin's bar on a window it does own, like lspsaga did", function()
      local client = stub_client()
      vim.lsp.get_clients = function()
        return { client }
      end
      winbar.setup({ chips = false })
      vim.wo[win].winbar = "foreign"
      vim.api.nvim_exec_autocmds("LspAttach", { buffer = bufnr, data = { client_id = 1 } })
      wait_for(function()
        return bar() ~= "foreign"
      end)
      assert.is_truthy(bar():find("repo.ts", 1, true))
    end)

    it("never draws on a floating window", function()
      local client = stub_client()
      vim.lsp.get_clients = function()
        return { client }
      end
      winbar.setup({})
      local float = vim.api.nvim_open_win(bufnr, false, {
        relative = "editor",
        row = 1,
        col = 1,
        width = 30,
        height = 5,
      })
      vim.api.nvim_exec_autocmds("LspAttach", { buffer = bufnr, data = { client_id = 1 } })
      vim.wait(100)
      assert.are.equal("", vim.wo[float].winbar)
      vim.api.nvim_win_close(float, true)
    end)

    it("never draws on a special buffer", function()
      local client = stub_client()
      vim.lsp.get_clients = function()
        return { client }
      end
      winbar.setup({})
      vim.bo[bufnr].buftype = "nofile"
      vim.api.nvim_exec_autocmds("LspAttach", { buffer = bufnr, data = { client_id = 1 } })
      vim.wait(100)
      assert.are.equal("", bar())
      vim.bo[bufnr].buftype = ""
    end)

    it("reports its state", function()
      winbar.setup({ filetypes = { lua = false } })
      local text = table.concat(winbar.status(), "\n")
      assert.is_truthy(text:find("global:%s+on"))
      assert.is_truthy(text:find("lua", 1, true))
      assert.is_truthy(text:find("depth caps:%s+markdown=1"))
      assert.is_truthy(text:find("align:%s+left"))
    end)

    it("defaults to left alignment, and draws the built-in right-align item for right", function()
      local client = stub_client()
      vim.lsp.get_clients = function()
        return { client }
      end

      winbar.setup({ chips = false })
      vim.api.nvim_exec_autocmds("LspAttach", { buffer = bufnr, data = { client_id = 1 } })
      wait_for(function()
        return bar():find("Repo", 1, true) ~= nil
      end)
      assert.are_not.equal("%=", bar():sub(1, 2))
      assert.is_truthy(table.concat(winbar.status(), "\n"):find("align:%s+left"))

      winbar.setup({ chips = false, align = "right" })
      vim.api.nvim_exec_autocmds("LspAttach", { buffer = bufnr, data = { client_id = 1 } })
      wait_for(function()
        return bar():find("Repo", 1, true) ~= nil
      end)
      assert.are.equal("%=", bar():sub(1, 2))
      assert.is_truthy(table.concat(winbar.status(), "\n"):find("align:%s+right"))
    end)

    it("ignores an align value that is neither left nor right", function()
      winbar.setup({ align = "center" })
      assert.is_truthy(table.concat(winbar.status(), "\n"):find("align:%s+left"))
    end)
  end)
end)
