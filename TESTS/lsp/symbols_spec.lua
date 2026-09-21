--- Covers `lsp.core.symbols`: the two response shapes it normalizes, the
--- cursor-to-path lookup, and the cache around the request.
---
--- The lookup is where the bugs would be, and each of its rules exists because
--- reading it the obvious way is wrong in one specific case: a range that ends
--- at column 0 of a later line (how a Markdown section says "up to the next
--- heading"), a symbol that starts and ends on one line, and a cursor in the
--- indentation of a header line. Every case below fixes one of them.
---
--- The request itself runs against a stub client, since there is no language
--- server in the harness -- what needs to be right is what is done with the
--- answer: caching against `changedtick`, joining an in-flight request, and
--- not dropping a waiter when a newer request supersedes it.

local symbols = require("lsp.core.symbols")

--- A `DocumentSymbol`.
---@param name string
---@param kind integer
---@param from integer[] # { line, col }
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

describe("lsp.core.symbols", function()
  describe("normalize", function()
    it("turns nil, an empty answer and garbage into an empty tree", function()
      assert.are.same({}, symbols.normalize(nil))
      assert.are.same({}, symbols.normalize({}))
      assert.are.same({}, symbols.normalize(vim.NIL))
    end)

    it("keeps a hierarchical answer's nesting", function()
      local tree = symbols.normalize({
        sym("Repo", 5, { 0, 0 }, { 9, 1 }, {
          sym("find", 6, { 1, 2 }, { 3, 3 }),
          sym("save", 6, { 4, 2 }, { 8, 3 }),
        }),
      })
      assert.are.equal(1, #tree)
      assert.are.equal("Repo", tree[1].name)
      assert.are.same({ "find", "save" }, {
        tree[1].children[1].name,
        tree[1].children[2].name,
      })
    end)

    it("rebuilds the nesting of a flat SymbolInformation answer by containment", function()
      local function info(name, kind, from, to)
        return {
          name = name,
          kind = kind,
          location = {
            uri = "file:///x",
            range = {
              start = { line = from[1], character = from[2] },
              ["end"] = { line = to[1], character = to[2] },
            },
          },
        }
      end
      -- Deliberately out of order: a flat answer promises nothing about it.
      local tree = symbols.normalize({
        info("save", 6, { 4, 2 }, { 8, 3 }),
        info("Repo", 5, { 0, 0 }, { 9, 1 }),
        info("find", 6, { 1, 2 }, { 3, 3 }),
        info("Other", 5, { 11, 0 }, { 14, 1 }),
      })
      assert.are.equal(2, #tree)
      assert.are.equal("Repo", tree[1].name)
      assert.are.equal(2, #tree[1].children)
      assert.are.equal("find", tree[1].children[1].name)
      assert.are.equal("Other", tree[2].name)
      assert.are.equal(0, #tree[2].children)
    end)

    it("drops an item with no usable range instead of raising", function()
      local tree = symbols.normalize({ { name = "broken", kind = 12 } })
      assert.are.same({}, tree)
    end)

    it("uses selectionRange for the name position and range for the extent", function()
      local item = sym("f", 12, { 2, 0 }, { 6, 3 })
      item.selectionRange =
        { start = { line = 2, character = 9 }, ["end"] = { line = 2, character = 10 } }
      local node = symbols.normalize({ item })[1]
      assert.are.equal(2, node.lnum)
      assert.are.equal(2, node.sel_lnum)
      assert.are.equal(9, node.sel_col)
      assert.are.equal(6, node.end_lnum)
    end)
  end)

  describe("path_at", function()
    local tree = symbols.normalize({
      sym("Repo", 5, { 0, 0 }, { 9, 1 }, {
        sym("find", 6, { 1, 4 }, { 3, 5 }),
        sym("save", 6, { 5, 4 }, { 8, 5 }),
      }),
    })

    ---@param path LspSymbols.Node[]
    ---@return string[]
    local function names(path)
      return vim.tbl_map(function(node)
        return node.name
      end, path)
    end

    it("returns the chain of containers, outermost first", function()
      assert.are.same({ "Repo", "find" }, names(symbols.path_at(tree, 2, 6)))
      assert.are.same({ "Repo", "save" }, names(symbols.path_at(tree, 6, 0)))
    end)

    it("is empty outside every symbol", function()
      assert.are.same({}, symbols.path_at(tree, 20, 0))
    end)

    it("stops at the container between two children", function()
      assert.are.same({ "Repo" }, names(symbols.path_at(tree, 4, 0)))
    end)

    -- The column is ignored on the first line of a multi-line symbol: a cursor
    -- in the indentation before `function` is on the function's line.
    it("counts the whole header line, indentation included", function()
      assert.are.same({ "Repo", "find" }, names(symbols.path_at(tree, 1, 0)))
    end)

    it("uses the column on the last line, where `end` closes the symbol", function()
      assert.are.same({ "Repo", "find" }, names(symbols.path_at(tree, 3, 5)))
      assert.are.same({ "Repo" }, names(symbols.path_at(tree, 3, 6)))
    end)

    it("uses the column for a symbol that starts and ends on one line", function()
      local one = symbols.normalize({
        sym("a", 13, { 0, 0 }, { 0, 5 }),
        sym("b", 13, { 0, 6 }, { 0, 11 }),
      })
      assert.are.same({ "a" }, names(symbols.path_at(one, 0, 2)))
      assert.are.same({ "b" }, names(symbols.path_at(one, 0, 8)))
      assert.are.same({}, names(symbols.path_at(one, 0, 20)))
    end)

    -- How a section-shaped symbol (a Markdown heading) says "up to, not
    -- including, the next heading": it ends at column 0 of the next heading's
    -- line. Read inclusively, the cursor on `## Next` is in `# First` as well.
    it("treats a range ending at column 0 as ending on the line before", function()
      local doc = symbols.normalize({
        sym("First", 15, { 0, 0 }, { 4, 0 }),
        sym("Next", 15, { 4, 0 }, { 8, 0 }),
      })
      assert.are.same({ "First" }, names(symbols.path_at(doc, 3, 0)))
      assert.are.same({ "Next" }, names(symbols.path_at(doc, 4, 0)))
    end)
  end)

  describe("walk", function()
    it("visits parents before children, with the depth", function()
      local tree = symbols.normalize({
        sym("A", 5, { 0, 0 }, { 5, 0 }, { sym("a1", 6, { 1, 0 }, { 2, 0 }) }),
        sym("B", 5, { 6, 0 }, { 9, 0 }),
      })
      ---@type string[]
      local seen = {}
      symbols.walk(tree, function(node, depth)
        seen[#seen + 1] = node.name .. depth
      end)
      assert.are.same({ "A1", "a12", "B1" }, seen)
    end)
  end)

  describe("the request", function()
    local real_get_clients
    ---@type table[]
    local sent
    ---@type table
    local answer

    --- A client that answers document-symbol requests from `answer`, either at
    --- once or when `flush()` is called.
    ---@param defer boolean
    ---@return table client, fun() flush
    local function stub_client(defer)
      ---@type function[]
      local queue = {}
      local client = {
        id = 1,
        name = "stub",
        offset_encoding = "utf-8",
        server_capabilities = { documentSymbolProvider = true },
        cancelled = {},
      }
      function client:request(method, params, handler)
        sent[#sent + 1] = { method = method, params = params }
        local id = #sent
        if defer then
          queue[#queue + 1] = function()
            handler(nil, answer)
          end
        else
          handler(nil, answer)
        end
        return true, id
      end
      function client:cancel_request(id)
        self.cancelled[#self.cancelled + 1] = id
      end
      return client,
        function()
          local pending = queue
          queue = {}
          for _, fn in ipairs(pending) do
            fn()
          end
        end
    end

    ---@type integer
    local bufnr

    before_each(function()
      symbols.reset()
      real_get_clients = vim.lsp.get_clients
      sent = {}
      answer = { sym("Repo", 5, { 0, 0 }, { 1, 0 }) }
      vim.cmd("enew!")
      bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b" })
    end)

    after_each(function()
      vim.lsp.get_clients = real_get_clients
      symbols.reset()
    end)

    it("says nil, without asking anyone, when no client provides symbols", function()
      vim.lsp.get_clients = function()
        return {}
      end
      local got = "unset"
      symbols.refresh(bufnr, function(nodes)
        got = nodes
      end)
      assert.is_nil(got)
      assert.are.equal(0, #sent)
    end)

    -- Measured against the real config with `code_actions.gitsigns = true`: the
    -- in-process client `lsp.nvim-gitsigns` is attached to every buffer gitsigns
    -- tracks, so a `.txt` or `.json` file with no language server got a
    -- breadcrumb -- the very case the winbar's own guard exists to refuse.
    it("does not count lsp.nvim's own in-process clients as attached", function()
      vim.lsp.get_clients = function()
        return { { id = 7, name = "lsp.nvim-gitsigns" } }
      end
      assert.is_false(symbols.attached(bufnr))
    end)

    it("counts a language server that sits next to an in-process client", function()
      local client = stub_client(false)
      vim.lsp.get_clients = function()
        return { { id = 7, name = "lsp.nvim-gitsigns" }, client }
      end
      assert.is_true(symbols.attached(bufnr))
    end)

    it("asks the provider, caches the answer and hands it to the callback", function()
      local client = stub_client(false)
      vim.lsp.get_clients = function()
        return { client }
      end

      local got
      symbols.refresh(bufnr, function(nodes)
        got = nodes
      end)
      assert.are.equal(1, #sent)
      assert.are.equal("textDocument/documentSymbol", sent[1].method)
      assert.are.equal("Repo", got[1].name)

      local cached, encoding = symbols.get(bufnr)
      assert.are.equal("Repo", cached[1].name)
      assert.are.equal("utf-8", encoding)
      assert.is_true(symbols.fresh(bufnr))
    end)

    it("does not ask again while the text is unchanged", function()
      local client = stub_client(false)
      vim.lsp.get_clients = function()
        return { client }
      end
      symbols.refresh(bufnr)
      symbols.refresh(bufnr)
      symbols.refresh(bufnr)
      assert.are.equal(1, #sent)
    end)

    it("asks again after an edit, and keeps the old tree until the new answer lands", function()
      local client, flush = stub_client(true)
      vim.lsp.get_clients = function()
        return { client }
      end
      symbols.refresh(bufnr)
      flush()
      assert.is_true(symbols.fresh(bufnr))

      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "changed" })
      assert.is_false(symbols.fresh(bufnr))
      -- Stale-while-revalidate: the breadcrumb must not blink out mid-edit.
      assert.are.equal("Repo", symbols.get(bufnr)[1].name)

      symbols.refresh(bufnr)
      assert.are.equal(2, #sent)
    end)

    it("joins a request that is already in flight instead of sending a second", function()
      local client, flush = stub_client(true)
      vim.lsp.get_clients = function()
        return { client }
      end
      local calls = 0
      symbols.refresh(bufnr, function()
        calls = calls + 1
      end)
      symbols.refresh(bufnr, function()
        calls = calls + 1
      end)
      assert.are.equal(1, #sent)
      flush()
      assert.are.equal(2, calls)
    end)

    it("does not lose a waiter when a newer request supersedes its request", function()
      local client, flush = stub_client(true)
      vim.lsp.get_clients = function()
        return { client }
      end
      local first, second = 0, 0
      symbols.refresh(bufnr, function()
        first = first + 1
      end)
      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "edited while waiting" })
      symbols.refresh(bufnr, function()
        second = second + 1
      end)
      assert.are.equal(2, #sent)
      assert.are.equal(1, #client.cancelled)

      flush() -- answers both; only the newer one may count
      assert.are.equal(1, first, "the waiter of the superseded request was dropped")
      assert.are.equal(1, second)
    end)

    it("tells subscribers when an answer lands, and stops after unsubscribe", function()
      local client = stub_client(false)
      vim.lsp.get_clients = function()
        return { client }
      end
      local heard = {}
      local off = symbols.subscribe(function(b)
        heard[#heard + 1] = b
      end)
      symbols.refresh(bufnr)
      assert.are.same({ bufnr }, heard)

      off()
      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "again" })
      symbols.refresh(bufnr)
      assert.are.same({ bufnr }, heard)
    end)

    it("picks the same provider every time: the lowest client id", function()
      local a = stub_client(false)
      a.id = 7
      local b = stub_client(false)
      b.id = 3
      vim.lsp.get_clients = function()
        return { a, b }
      end
      assert.are.equal(3, symbols.provider(bufnr).id)
    end)

    it("forgets a buffer that was wiped", function()
      local client = stub_client(false)
      vim.lsp.get_clients = function()
        return { client }
      end
      symbols.refresh(bufnr)
      assert.is_not_nil(symbols.get(bufnr))
      vim.cmd("enew!")
      vim.api.nvim_buf_delete(bufnr, { force = true })
      assert.is_nil(symbols.get(bufnr))
    end)
  end)
end)
