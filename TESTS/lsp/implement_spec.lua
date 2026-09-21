--- Covers `lsp.core.implement`: which symbols it asks about, how it reads the
--- answers, and that it says nothing where it has nothing to say.
---
--- The request cost is the reason this feature is off by default, so the
--- guards that keep it cheap are what is worth pinning: a buffer with no
--- server that implements `textDocument/implementation` sends nothing at all,
--- and `max_requests` caps a round. The server is a stub whose `request`
--- answers at once, keyed by the symbol's line.

local implement = require("lsp.core.implement")
local symbols = require("lsp.core.symbols")

---@param name string
---@param kind integer
---@param line integer
---@return table
local function sym(name, kind, line)
  local range = {
    start = { line = line, character = 0 },
    ["end"] = { line = line + 1, character = 0 },
  }
  return { name = name, kind = kind, range = range, selectionRange = range }
end

describe("lsp.core.implement", function()
  after_each(function()
    implement.detach()
    symbols.reset()
  end)

  describe("count", function()
    it("counts a single Location as one", function()
      assert.are.equal(1, implement.count({ uri = "file:///a", range = {} }))
    end)

    it("counts a list, LocationLinks included", function()
      assert.are.equal(3, implement.count({ { uri = "a" }, { uri = "b" }, { targetUri = "c" } }))
    end)

    it("counts nothing for nil, vim.NIL and an empty answer", function()
      assert.are.equal(0, implement.count(nil))
      assert.are.equal(0, implement.count(vim.NIL))
      assert.are.equal(0, implement.count({}))
    end)
  end)

  describe("candidates", function()
    local tree = symbols.normalize({
      sym("Repo", 11, 0),
      sym("Impl", 5, 3),
      sym("Other", 11, 6),
      sym("Third", 11, 9),
    })

    it("picks the symbols of the wanted kinds, in document order", function()
      local out = implement.candidates(tree, { [11] = true }, 10)
      assert.are.same(
        { "Repo", "Other", "Third" },
        vim.tbl_map(function(n)
          return n.name
        end, out)
      )
    end)

    it("stops at the limit", function()
      assert.are.equal(2, #implement.candidates(tree, { [11] = true }, 2))
    end)

    it("finds a wanted kind nested inside another symbol", function()
      local nested = symbols.normalize({
        {
          name = "ns",
          kind = 3,
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 9, character = 0 } },
          selectionRange = {
            start = { line = 0, character = 0 },
            ["end"] = { line = 0, character = 2 },
          },
          children = { sym("Inner", 11, 2) },
        },
      })
      assert.are.equal(1, #implement.candidates(nested, { [11] = true }, 10))
    end)

    it("picks nothing when no kind is wanted", function()
      assert.are.equal(0, #implement.candidates(tree, {}, 10))
    end)
  end)

  describe("resolution", function()
    it("is off by default, like the cost says", function()
      implement.setup({})
      assert.is_false(implement.enabled(nil))
      assert.is_false(implement.enabled("typescript"))
    end)

    it("lets a filetype turn it on against a global off", function()
      implement.setup({ enable = false, filetypes = { typescript = true } })
      assert.is_true(implement.enabled("typescript"))
      assert.is_false(implement.enabled("lua"))
    end)

    it("toggles and clears a filetype override", function()
      implement.setup({ enable = false })
      implement.toggle("go")
      assert.is_true(implement.enabled("go"))
      assert.are.same({ "go" }, implement.overridden())
      implement.clear("go")
      assert.is_false(implement.enabled("go"))
    end)

    it("reads kinds by name and ignores names it does not know", function()
      implement.setup({ enable = true, kinds = { Interface = true, Class = true, Nonsense = true } })
      local text = table.concat(implement.status(), "\n")
      assert.is_truthy(text:find("kinds:%s+Class, Interface"))
    end)
  end)

  describe("in a buffer", function()
    local real_get_clients
    ---@type integer
    local bufnr
    ---@type integer
    local ns
    ---@type table[]
    local sent
    --- Every request with the buffer it was for, in order.
    ---@type { method: string, bufnr: integer|nil, line: integer|nil }[]
    local asked

    ---@param implementations table<integer, integer> # line -> how many implement it
    ---@param with_implementation? boolean # whether the client advertises the method
    ---@return table
    local function stub_client(implementations, with_implementation)
      local client = {
        id = 1,
        name = "stub",
        offset_encoding = "utf-8",
        server_capabilities = {
          documentSymbolProvider = true,
          implementationProvider = with_implementation ~= false or nil,
        },
        -- Lines the symbols sit below where they are in the buffer's first text:
        -- a case that types above them moves the answer to match.
        shift = 0,
        -- While set, the symbol request is kept instead of answered, and its
        -- handler waits in `held` for the case to release it.
        hold = false,
        ---@type function|nil
        held = nil,
      }
      function client:request(method, params, handler, bufnr_)
        sent[#sent + 1] = method
        asked[#asked + 1] = {
          method = method,
          bufnr = bufnr_,
          line = params and params.position and params.position.line,
        }
        if method == "textDocument/documentSymbol" then
          if self.hold then
            self.held = handler
            return true, 1000 + #sent
          end
          handler(nil, {
            sym("Repo", 11, 0 + self.shift),
            sym("Impl", 5, 2 + self.shift),
            sym("Cache", 11, 4 + self.shift),
          })
        else
          local n = implementations[params.position.line] or 0
          local result = {}
          for i = 1, n do
            result[i] = { uri = "file:///impl" .. i, range = {} }
          end
          handler(nil, result)
        end
        return true, #sent
      end
      function client:cancel_request() end
      return client
    end

    ---@return table[]
    local function marks()
      return vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
    end

    before_each(function()
      real_get_clients = vim.lsp.get_clients
      symbols.reset()
      sent = {}
      asked = {}
      ns = vim.api.nvim_create_namespace("lsp_nvim_implement")
      -- `setup()` refreshes every loaded buffer, so the ones earlier cases left
      -- behind would answer to this case's stub and inflate its request count.
      vim.cmd("enew!")
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if b ~= vim.api.nvim_get_current_buf() then
          pcall(vim.api.nvim_buf_delete, b, { force = true })
        end
      end
      vim.cmd("enew!")
      bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "interface Repo {}",
        "",
        "class Impl {}",
        "",
        "interface Cache {}",
        "",
      })
      vim.bo[bufnr].filetype = "typescript"
    end)

    after_each(function()
      vim.lsp.get_clients = real_get_clients
    end)

    ---@param opts table
    ---@param client table
    local function run(opts, client)
      -- Honours `method`, like the real one: it filters on the capability, and
      -- "does any client implement this" is exactly what the module asks.
      vim.lsp.get_clients = function(filter)
        if
          filter
          and filter.method == "textDocument/implementation"
          and not client.server_capabilities.implementationProvider
        then
          return {}
        end
        return { client }
      end
      implement.setup(vim.tbl_extend("force", { debounce_ms = 0 }, opts))
      vim.api.nvim_exec_autocmds("BufEnter", { buffer = bufnr })
    end

    it("marks an interface that something implements, with the count", function()
      run({ enable = true }, stub_client({ [0] = 3 }))
      vim.wait(2000, function()
        return #marks() > 0
      end, 10)

      local found = marks()
      assert.are.equal(1, #found, "Cache has none, Impl is not an interface")
      assert.are.equal(0, found[1][2])
      assert.are.equal(" 3 impl", found[1][4].virt_text[1][1])
    end)

    it("marks every interface that has implementations", function()
      run({ enable = true }, stub_client({ [0] = 1, [4] = 2 }))
      vim.wait(2000, function()
        return #marks() == 2
      end, 10)
      assert.are.equal(2, #marks())
    end)

    it("uses the configured text", function()
      run({ enable = true, text = " (%d implementations)" }, stub_client({ [0] = 2 }))
      vim.wait(2000, function()
        return #marks() > 0
      end, 10)
      assert.are.equal(" (2 implementations)", marks()[1][4].virt_text[1][1])
    end)

    it("keeps the default text when the configured one has no %d to print a count in", function()
      run({ enable = true, text = "impl" }, stub_client({ [0] = 2 }))
      vim.wait(2000, function()
        return #marks() > 0
      end, 10)
      assert.are.equal(" 2 impl", marks()[1][4].virt_text[1][1])
    end)

    -- The text goes through `string.format` on every answer, inside a request
    -- handler nothing catches: a stray `%` in it would raise there each time
    -- and no marker would ever be drawn, for a value `setup()` had accepted.
    it("keeps the default text when the configured one cannot format a count", function()
      run({ enable = true, text = " %d% impl" }, stub_client({ [0] = 2 }))
      vim.wait(2000, function()
        return #marks() > 0
      end, 10)
      assert.are.equal(" 2 impl", marks()[1][4].virt_text[1][1])
    end)

    it("takes a literal percent sign in the text, written as %%", function()
      run({ enable = true, text = " %d%% impl" }, stub_client({ [0] = 2 }))
      vim.wait(2000, function()
        return #marks() > 0
      end, 10)
      assert.are.equal(" 2% impl", marks()[1][4].virt_text[1][1])
    end)

    -- One debounce handle keeps the arguments of the *last* call only, so a
    -- single one shared by every buffer drops the refresh of the buffer that
    -- changed first: switching to another window inside the window leaves the
    -- first one's markers describing text it no longer has.
    it("refreshes every buffer that changed inside one debounce window", function()
      local other = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_lines(other, 0, -1, false, { "interface Other {}", "" })
      vim.bo[other].filetype = "typescript"

      run({ enable = true, debounce_ms = 100 }, stub_client({}))
      vim.wait(500)
      asked = {}

      vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "" })
      vim.api.nvim_buf_set_lines(other, 0, 0, false, { "" })
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = bufnr })
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = other })

      ---@type table<integer, true>
      local refreshed = {}
      vim.wait(1500, function()
        for _, req in ipairs(asked) do
          if req.method == "textDocument/documentSymbol" and req.bufnr then
            refreshed[req.bufnr] = true
          end
        end
        return refreshed[bufnr] and refreshed[other]
      end, 10)
      assert.is_true(refreshed[bufnr] == true, "the first buffer's refresh was dropped")
      assert.is_true(refreshed[other] == true, "the second buffer's refresh was dropped")
    end)

    -- An answer describes the text it was asked about. When it lands after the
    -- buffer changed (typing in Insert mode fires no `TextChanged`), drawing it
    -- marks the wrong lines -- and, because a round is "handled" per
    -- `changedtick`, a stale round that got as far as the requests would also
    -- mark the *current* text as handled and turn the right round away.
    it(
      "does not act on an answer for text that has changed, and asks again for the new text",
      function()
        local client = stub_client({ [1] = 3 }) -- `Repo` is on line 1 once the text has shifted
        client.hold = true
        run({ enable = true }, client)
        vim.wait(1000, function()
          return client.held ~= nil
        end, 10)
        assert.is_not_nil(client.held, "the symbol request was never sent")

        -- One line typed above the interfaces while the request is on the wire.
        vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "" })

        -- From here the server answers for the new text (`Repo` on line 1, `Cache`
        -- on line 5) -- and the answer already on the wire arrives late, still
        -- describing the old one (lines 0 and 4).
        client.hold = false
        client.shift = 1
        client.held(nil, {
          sym("Repo", 11, 0),
          sym("Impl", 5, 2),
          sym("Cache", 11, 4),
        })

        -- Leaving Insert mode is what asks again.
        vim.api.nvim_exec_autocmds("InsertLeave", { buffer = bufnr })
        vim.wait(2000, function()
          return #marks() > 0
        end, 10)

        for _, req in ipairs(asked) do
          if req.method == "textDocument/implementation" then
            assert.is_true(
              req.line == 1 or req.line == 5,
              ("asked about line %s, which held something else when the text changed"):format(
                tostring(req.line)
              )
            )
          end
        end
        assert.are.equal(1, #marks())
        assert.are.equal(1, marks()[1][2], "the marker is not on the line of `Repo`")
      end
    )

    it("sends nothing at all when no client implements the method", function()
      run({ enable = true }, stub_client({ [0] = 3 }, false))
      vim.wait(200)
      assert.are.same({}, sent)
      assert.are.equal(0, #marks())
    end)

    it("sends nothing while it is off", function()
      run({ enable = false }, stub_client({ [0] = 3 }))
      vim.wait(200)
      assert.are.same({}, sent)
    end)

    it("caps one round at max_requests", function()
      run({ enable = true, max_requests = 1 }, stub_client({ [0] = 1, [4] = 1 }))
      vim.wait(2000, function()
        return #marks() > 0
      end, 10)
      vim.wait(100)
      local implementation_requests = 0
      for _, method in ipairs(sent) do
        if method == "textDocument/implementation" then
          implementation_requests = implementation_requests + 1
        end
      end
      assert.are.equal(1, implementation_requests)
    end)

    it("takes its markers off when switched off", function()
      run({ enable = true }, stub_client({ [0] = 3 }))
      vim.wait(2000, function()
        return #marks() > 0
      end, 10)
      implement.set(false)
      assert.are.equal(0, #marks())
    end)

    it("removes its markers when detached", function()
      run({ enable = true }, stub_client({ [0] = 3 }))
      vim.wait(2000, function()
        return #marks() > 0
      end, 10)
      implement.detach()
      assert.are.equal(0, #marks())
    end)

    it("reports its state", function()
      run({ enable = true }, stub_client({}))
      local text = table.concat(implement.status(), "\n")
      assert.is_truthy(text:find("global:%s+on"))
      assert.is_truthy(text:find("implementationProvider in this buffer: stub", 1, true))
    end)
  end)
end)
