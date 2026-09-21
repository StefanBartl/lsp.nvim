--- Covers `lsp.core.peek`: what a definition answer is reduced to, and what
--- the float does to the editor around it.
---
--- The float is real -- a real window over a real buffer of a real temp file --
--- because everything that can go wrong with a peek is a side effect: a key
--- left mapped on a buffer after the window closed, a buffer that stays loaded
--- ten peeks later, focus that does not come back, a "take it" that leaves a
--- window behind. None of that shows up in a stubbed call.
---
--- The language server is stubbed (`vim.lsp.get_clients` and
--- `vim.lsp.buf_request_all`): the request path is one call into Neovim, and
--- what is worth pinning is the merge of the answers and the choice between
--- opening at once and asking which.

local peek = require("lsp.core.peek")
local beacon = require("lsp.core.peek.beacon")

---@param path string
---@param line? integer # 0-based.
---@param char? integer
---@return LspPeek.Target
local function target(path, line, char)
  return {
    uri = vim.uri_from_fname(path),
    lnum = line or 0,
    char = char or 0,
    encoding = "utf-8",
  }
end

describe("lsp.core.peek", function()
  ---@type string
  local dir
  ---@type string
  local src
  ---@type string
  local dst
  ---@type integer
  local main

  before_each(function()
    require("lsp.config").setup({})
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    src = dir .. "/src.lua"
    dst = dir .. "/dst.lua"
    vim.fn.writefile({ "local function main()", "  return helper()", "end" }, src)
    vim.fn.writefile({ "-- helper", "local function helper()", "  return 42", "end" }, dst)
    vim.cmd("only!")
    vim.cmd("edit " .. vim.fn.fnameescape(src))
    main = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    peek.close_all()
    vim.wait(50)
    vim.cmd("only!")
    vim.fn.delete(dir, "rf")
  end)

  describe("flatten", function()
    ---@param id integer
    ---@return table
    local function client(id)
      return { id = id, offset_encoding = "utf-16" }
    end

    local real
    before_each(function()
      real = vim.lsp.get_client_by_id
      vim.lsp.get_client_by_id = client
    end)
    after_each(function()
      vim.lsp.get_client_by_id = real
    end)

    local range = {
      start = { line = 3, character = 4 },
      ["end"] = { line = 3, character = 8 },
    }

    it("reads a single Location, a list, and LocationLinks", function()
      local out = peek.flatten({
        [1] = { result = { uri = "file:///a", range = range } },
        [2] = { result = { { uri = "file:///b", range = range } } },
        [3] = {
          result = {
            { targetUri = "file:///c", targetRange = range, targetSelectionRange = range },
          },
        },
      })
      assert.are.same({ "file:///a", "file:///b", "file:///c" }, {
        out[1].uri,
        out[2].uri,
        out[3].uri,
      })
      assert.are.equal(3, out[1].lnum)
      assert.are.equal(4, out[1].char)
      assert.are.equal("utf-16", out[1].encoding)
    end)

    it("lists a place two servers both named once", function()
      local out = peek.flatten({
        [1] = { result = { uri = "file:///a", range = range } },
        [2] = { result = { uri = "file:///a", range = range } },
      })
      assert.are.equal(1, #out)
    end)

    it("skips a failed answer and a nil result", function()
      local out = peek.flatten({
        [1] = { err = { code = -1, message = "no" } },
        [2] = { result = nil },
        [3] = { result = { uri = "file:///c", range = range } },
      })
      assert.are.equal(1, #out)
      assert.are.equal("file:///c", out[1].uri)
    end)

    it("is deterministic across clients", function()
      local answers = {}
      for id = 1, 5 do
        answers[id] = { result = { uri = "file:///f" .. id, range = range } }
      end
      local out = peek.flatten(answers)
      assert.are.same(
        { "file:///f1", "file:///f2", "file:///f3", "file:///f4", "file:///f5" },
        vim.tbl_map(function(t)
          return t.uri
        end, out)
      )
    end)
  end)

  describe("open", function()
    it("shows the real buffer in a float, at the target line", function()
      local entry = peek.open(target(dst, 1, 6))
      assert.is_not_nil(entry)
      assert.are.equal("editor", vim.api.nvim_win_get_config(entry.win).relative)
      assert.are.equal(
        vim.fs.normalize(dst),
        vim.fs.normalize(vim.api.nvim_buf_get_name(entry.buf))
      )
      assert.are.same({ 2, 6 }, vim.api.nvim_win_get_cursor(entry.win))
      assert.are.equal(entry.win, vim.api.nvim_get_current_win())
      assert.are.equal(1, #peek.entries())
    end)

    it("titles the float with the file and the line", function()
      local entry = peek.open(target(dst, 1))
      local title = vim.api.nvim_win_get_config(entry.win).title
      local text = type(title) == "table" and title[1][1] or title
      assert.is_truthy(tostring(text):find("dst.lua:2", 1, true))
    end)

    it("clamps a target line past the end of the file instead of raising", function()
      local entry = peek.open(target(dst, 999))
      assert.is_not_nil(entry)
      assert.are.equal(4, vim.api.nvim_win_get_cursor(entry.win)[1])
    end)

    it("maps the peek keys buffer-locally", function()
      local entry = peek.open(target(dst, 0))
      for _, lhs in ipairs({ "q", "<C-o>", "<C-v>", "<C-x>", "<C-t>" }) do
        local map = vim.fn.maparg(lhs, "n", false, true)
        assert.are.equal(1, map.buffer, lhs .. " is not buffer-local")
      end
      assert.is_truthy(entry)
    end)

    it("leaves a key alone that `peek.keys` set to false", function()
      require("lsp.config").setup({ peek = { keys = { edit = false } } })
      peek.open(target(dst, 0))
      assert.are.equal("", vim.fn.maparg("<C-o>", "n"))
    end)

    it("stacks a peek opened from inside a peek, offset from the one below", function()
      local first = peek.open(target(dst, 0))
      local second = peek.open(target(src, 0))
      assert.are.equal(2, #peek.entries())
      assert.are.equal(first.win, second.parent)
      local a = vim.api.nvim_win_get_config(first.win)
      local b = vim.api.nvim_win_get_config(second.win)
      assert.is_true(b.row >= a.row and b.col > a.col)
      assert.is_true(b.zindex > a.zindex)
    end)

    it("takes the size from the config: fractions of the editor, or cells", function()
      require("lsp.config").setup({ peek = { width = 40, height = 10 } })
      local entry = peek.open(target(dst, 0))
      local cfg = vim.api.nvim_win_get_config(entry.win)
      -- Content size: the border is the two extra columns and rows.
      assert.are.equal(38, cfg.width)
      assert.are.equal(8, cfg.height)
    end)
  end)

  describe("close", function()
    it("closes the float, gives the keys back and returns to the window it came from", function()
      local entry = peek.open(target(dst, 0))
      peek.close()
      vim.wait(200, function()
        return vim.api.nvim_get_current_win() == main
      end)
      assert.is_false(vim.api.nvim_win_is_valid(entry.win))
      assert.are.equal(0, #peek.entries())
      assert.are.equal(main, vim.api.nvim_get_current_win())
      assert.are.equal("", vim.fn.maparg("q", "n", false, true).lhs or "")
    end)

    it("unloads a buffer the peek loaded, once nothing shows it", function()
      local entry = peek.open(target(dst, 0))
      assert.is_true(entry.fresh)
      local buf = entry.buf
      peek.close()
      vim.wait(500, function()
        return not vim.api.nvim_buf_is_loaded(buf)
      end)
      assert.is_false(vim.api.nvim_buf_is_loaded(buf))
    end)

    it("does not unload a buffer that was already open", function()
      vim.cmd("split " .. vim.fn.fnameescape(dst))
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_set_current_win(main)
      local entry = peek.open(target(dst, 0))
      assert.is_false(entry.fresh)
      peek.close()
      vim.wait(100)
      assert.is_true(vim.api.nvim_buf_is_loaded(buf))
    end)

    it("does not unload a buffer that was edited in the peek", function()
      local entry = peek.open(target(dst, 0))
      local buf = entry.buf
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "-- edited" })
      peek.close()
      vim.wait(100)
      assert.is_true(vim.api.nvim_buf_is_loaded(buf))
      assert.is_true(vim.bo[buf].modified)
      vim.bo[buf].modified = false
    end)

    it("closing a lower peek closes the ones stacked above it", function()
      local first = peek.open(target(dst, 0))
      local second = peek.open(target(src, 0))
      vim.api.nvim_win_close(first.win, true)
      vim.wait(500, function()
        return not vim.api.nvim_win_is_valid(second.win)
      end)
      assert.is_false(vim.api.nvim_win_is_valid(second.win))
      assert.are.equal(0, #peek.entries())
    end)

    it("closes only the top peek from the top one", function()
      local first = peek.open(target(dst, 0))
      local second = peek.open(target(src, 0))
      peek.close()
      vim.wait(200)
      assert.is_false(vim.api.nvim_win_is_valid(second.win))
      assert.is_true(vim.api.nvim_win_is_valid(first.win))
      assert.are.equal(1, #peek.entries())
    end)

    it("is a no-op with nothing open", function()
      assert.has_no.errors(function()
        peek.close()
        peek.close_all()
      end)
    end)

    it("gives back a buffer-local map the peek key had shadowed", function()
      vim.cmd("edit " .. vim.fn.fnameescape(dst))
      local buf = vim.api.nvim_get_current_buf()
      vim.keymap.set("n", "q", "<Nop>", { buffer = buf, desc = "mine" })
      vim.api.nvim_set_current_win(main)
      vim.cmd("edit " .. vim.fn.fnameescape(src))

      -- `dst` is open in no window now, but it is still loaded, so the peek
      -- finds the map in place.
      local entry = peek.open(target(dst, 0))
      assert.are.equal("lsp.nvim peek: close", vim.fn.maparg("q", "n", false, true).desc)
      peek.close()
      vim.wait(200, function()
        return #peek.entries() == 0
      end)
      assert.are.equal(
        "mine",
        vim.api.nvim_buf_call(buf, function()
          return vim.fn.maparg("q", "n", false, true).desc
        end)
      )
      assert.is_truthy(entry)
    end)
  end)

  describe("take", function()
    it("`edit` puts the peeked buffer in the window it came from and closes the float", function()
      local entry = peek.open(target(dst, 2, 2))
      local buf = entry.buf
      peek.take("edit")
      assert.are.equal(buf, vim.api.nvim_win_get_buf(main))
      assert.are.equal(main, vim.api.nvim_get_current_win())
      assert.are.same({ 3, 2 }, vim.api.nvim_win_get_cursor(main))
      assert.is_false(vim.api.nvim_win_is_valid(entry.win))
      assert.are.equal(0, #peek.entries())
    end)

    it("takes the cursor the peek has now, not the one it opened at", function()
      local entry = peek.open(target(dst, 0))
      vim.api.nvim_win_set_cursor(entry.win, { 4, 0 })
      peek.take("edit")
      assert.are.equal(4, vim.api.nvim_win_get_cursor(main)[1])
    end)

    it("`vsplit` and `split` open a new window and leave the old one alone", function()
      local before = #vim.api.nvim_tabpage_list_wins(0)
      local entry = peek.open(target(dst, 0))
      peek.take("vsplit")
      assert.are.equal(before + 1, #vim.api.nvim_tabpage_list_wins(0))
      assert.are.equal(entry.buf, vim.api.nvim_get_current_buf())
      assert.are_not.equal(entry.buf, vim.api.nvim_win_get_buf(main))

      vim.cmd("only!")
      main = vim.api.nvim_get_current_win()
      local entry2 = peek.open(target(dst, 0))
      peek.take("split")
      assert.are.equal(2, #vim.api.nvim_tabpage_list_wins(0))
      assert.are.equal(entry2.buf, vim.api.nvim_get_current_buf())
    end)

    it("`tabedit` opens a new tab page", function()
      local tabs = #vim.api.nvim_list_tabpages()
      local entry = peek.open(target(dst, 0))
      peek.take("tabedit")
      assert.are.equal(tabs + 1, #vim.api.nvim_list_tabpages())
      assert.are.equal(entry.buf, vim.api.nvim_get_current_buf())
      vim.cmd("tabclose")
    end)

    it("records the jump, so `<C-o>` comes back to where the peek started", function()
      vim.api.nvim_win_set_cursor(main, { 2, 3 })
      peek.open(target(dst, 2))
      peek.take("edit")
      vim.cmd("normal! \15")
      assert.are.equal(vim.fs.normalize(src), vim.fs.normalize(vim.api.nvim_buf_get_name(0)))
      assert.are.same({ 2, 3 }, vim.api.nvim_win_get_cursor(0))
    end)

    it("does nothing when the cursor is not in a peek window", function()
      local entry = peek.open(target(dst, 0))
      vim.api.nvim_set_current_win(main)
      peek.take("edit")
      assert.are.equal(src, vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(main)))
      assert.is_true(vim.api.nvim_win_is_valid(entry.win))
    end)

    it("flashes the line it landed on when the beacon is on", function()
      local flashed
      local real = beacon.flash
      beacon.flash = function(win, lnum)
        flashed = { win = win, lnum = lnum }
      end
      peek.open(target(dst, 2))
      peek.take("edit")
      beacon.flash = real
      assert.are.same({ win = main, lnum = 2 }, flashed)
    end)

    it("does not flash with peek.beacon = false", function()
      require("lsp.config").setup({ peek = { beacon = false } })
      local flashed = false
      local real = beacon.flash
      beacon.flash = function()
        flashed = true
      end
      peek.open(target(dst, 2))
      peek.take("edit")
      beacon.flash = real
      assert.is_false(flashed)
    end)
  end)

  describe("peek", function()
    local real_clients, real_request, real_select, real_by_id
    local answer

    before_each(function()
      real_clients = vim.lsp.get_clients
      real_request = vim.lsp.buf_request_all
      real_select = vim.ui.select
      real_by_id = vim.lsp.get_client_by_id
      vim.lsp.get_clients = function()
        return { { id = 1, offset_encoding = "utf-8" } }
      end
      vim.lsp.get_client_by_id = function()
        return { id = 1, offset_encoding = "utf-8" }
      end
      vim.lsp.buf_request_all = function(_, _, _, handler)
        handler(answer)
      end
    end)

    after_each(function()
      vim.lsp.get_clients = real_clients
      vim.lsp.buf_request_all = real_request
      vim.ui.select = real_select
      vim.lsp.get_client_by_id = real_by_id
    end)

    local function loc(path, line)
      return {
        uri = vim.uri_from_fname(path),
        range = {
          start = { line = line, character = 0 },
          ["end"] = { line = line, character = 3 },
        },
      }
    end

    it("opens a single answer directly", function()
      answer = { [1] = { result = { loc(dst, 1) } } }
      peek.peek("definition")
      assert.are.equal(1, #peek.entries())
    end)

    it("asks which when there are several, and opens the choice", function()
      answer = { [1] = { result = { loc(dst, 1), loc(src, 0) } } }
      local offered
      vim.ui.select = function(items, _, on_choice)
        offered = items
        on_choice(items[2])
      end
      peek.peek("definition")
      assert.are.equal(2, #offered)
      assert.are.equal(1, #peek.entries())
      assert.are.equal(
        vim.fs.normalize(src),
        vim.fs.normalize(vim.api.nvim_buf_get_name(peek.entries()[1].buf))
      )
    end)

    it("opens nothing when the choice is cancelled", function()
      answer = { [1] = { result = { loc(dst, 1), loc(src, 0) } } }
      vim.ui.select = function(_, _, on_choice)
        on_choice(nil)
      end
      peek.peek("definition")
      assert.are.equal(0, #peek.entries())
    end)

    it("says so, and opens nothing, for an empty answer", function()
      answer = { [1] = { result = {} } }
      peek.peek("type_definition")
      assert.are.equal(0, #peek.entries())
    end)

    it("says so when no attached server supports the request", function()
      vim.lsp.get_clients = function()
        return {}
      end
      peek.peek("definition")
      assert.are.equal(0, #peek.entries())
    end)

    it("refuses a kind it does not know", function()
      assert.has_no.errors(function()
        peek.peek("nonsense")
      end)
      assert.are.equal(0, #peek.entries())
    end)

    it("knows the four requests it can peek", function()
      assert.are.equal("textDocument/definition", peek.METHODS.definition)
      assert.are.equal("textDocument/typeDefinition", peek.METHODS.type_definition)
      assert.are.equal("textDocument/implementation", peek.METHODS.implementation)
      assert.are.equal("textDocument/declaration", peek.METHODS.declaration)
    end)
  end)
end)

describe("lsp.core.peek.beacon", function()
  it("lights a line and puts the buffer back afterwards", function()
    vim.cmd("enew!")
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "b", "c" })
    local ns = vim.api.nvim_create_namespace("lsp_nvim_beacon")

    beacon.flash(vim.api.nvim_get_current_win(), 1)
    assert.are.equal(1, #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))

    vim.wait(beacon.DURATION_MS + 300, function()
      return #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 0
    end)
    assert.are.equal(0, #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))
  end)

  it("ignores a line that is not there and a window that is gone", function()
    vim.cmd("enew!")
    assert.has_no.errors(function()
      beacon.flash(vim.api.nvim_get_current_win(), 99)
      beacon.flash(-1, 0)
    end)
  end)
end)
