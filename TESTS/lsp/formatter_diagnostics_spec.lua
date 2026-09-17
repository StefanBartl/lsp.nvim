--- Four defects found by provoking `lsp/formatter/` and `lsp/diagnostics/`
--- with the conditions they are never run under by hand: a formatter that
--- answers later, several LSP clients where the code assumed one, and a list
--- command run twice in a row.
---
--- Every case here was first watched failing against `git show HEAD:` of the
--- file it covers; the numbers quoted in the comments are from those runs.

describe("lsp.formatter.conform.format_preserve_view", function()
  local saved_conform

  before_each(function()
    saved_conform = package.loaded["conform"]
  end)

  after_each(function()
    package.loaded["conform"] = saved_conform
  end)

  -- The helper's whole reason to exist is in its own docstring: "Synchronous
  -- formatting is used to avoid race conditions with subsequent write", and
  -- the call site was commented "Force synchronous run". It did not force
  -- anything -- `vim.tbl_extend("force", defaults, opts)` lets the *caller*
  -- win, so `async = true` reached Conform.
  --
  -- Measured on the unfixed file with a fake Conform that edits the buffer
  -- from `vim.schedule`, which is what an async formatter does: disk after
  -- save 1 held the unformatted "save one", disk after save 2 held the
  -- formatted text. The edit landed one save late, and `restore_views` ran
  -- against a buffer that had not been touched yet.
  it("keeps Conform synchronous even when the caller asks for async", function()
    local seen
    package.loaded["conform"] = {
      format = function(o)
        seen = vim.deepcopy(o)
        return true
      end,
    }

    local confmod = require("lsp.formatter.conform")
    local buf = vim.api.nvim_create_buf(true, false)
    confmod.format_preserve_view(buf, { async = true, timeout_ms = 42 })

    assert.is_table(seen)
    assert.are.equal(false, seen.async)
    -- The caller still owns everything that is a preference rather than a
    -- contract, or the override would just have moved instead of going away.
    assert.are.equal(42, seen.timeout_ms)
    assert.are.equal(buf, seen.bufnr)
  end)

  -- Same reason, other half of the contract: the buffer the caller named is
  -- the buffer that gets formatted. `bufnr` was mergeable too.
  it("formats the buffer it was given, not one the options name", function()
    local seen
    package.loaded["conform"] = {
      format = function(o)
        seen = vim.deepcopy(o)
        return true
      end,
    }

    local confmod = require("lsp.formatter.conform")
    local target = vim.api.nvim_create_buf(true, false)
    local decoy = vim.api.nvim_create_buf(true, false)
    confmod.format_preserve_view(target, { bufnr = decoy })

    assert.are.equal(target, seen.bufnr)
  end)
end)

describe("lsp.formatter LSP fallback", function()
  local clients, buf, tmp

  --- A fake client that advertises formatting. `mute` never answers the
  --- formatting request, which is how a server that is busy reindexing looks
  --- from the editor's side.
  ---@param name string
  ---@param mute boolean
  ---@param seen string[]
  ---@return integer|nil
  local function start_fake(name, mute, seen)
    return vim.lsp.start({
      name = name,
      root_dir = vim.fn.getcwd(),
      cmd = function()
        return {
          request = function(method, _params, cb)
            if method == "initialize" then
              cb(nil, { capabilities = { documentFormattingProvider = true } })
              return true, 1
            end
            if method == "textDocument/formatting" then
              seen[#seen + 1] = name
              if mute then
                return true, 2
              end
              cb(nil, {})
              return true, 2
            end
            cb(nil, nil)
            return true, 3
          end,
          notify = function()
            return true
          end,
          is_closing = function()
            return false
          end,
          terminate = function() end,
        }
      end,
    }, { bufnr = buf, attach = true })
  end

  before_each(function()
    clients = {}
    tmp = vim.fn.tempname() .. ".txt"
    vim.cmd("edit " .. vim.fn.fnameescape(tmp))
    buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello" })
  end)

  after_each(function()
    for _, id in ipairs(clients) do
      pcall(function()
        local c = vim.lsp.get_client_by_id(id)
        if c then
          c:stop(true)
        end
      end)
    end
    vim.cmd("silent! bwipeout!")
    os.remove(tmp)
  end)

  ---@param specs table[] # { name, mute }
  local function attach(specs, seen)
    for _, s in ipairs(specs) do
      clients[#clients + 1] = start_fake(s[1], s[2], seen)
    end
    assert.is_true(vim.wait(2000, function()
      for _, id in ipairs(clients) do
        local c = vim.lsp.get_client_by_id(id)
        if not (c and c.initialized) then
          return false
        end
      end
      return true
    end, 10))
  end

  -- `vim.lsp.buf.format` with neither `id` nor `filter` requests *every*
  -- attached client that advertises formatting, each with the full
  -- `timeout_ms`, and applies each answer on top of the last. Two things
  -- follow, both measured on the unfixed file with three capable fakes of
  -- which two never answer: `timeout_ms = 1000` made `format()` take 2083 ms,
  -- and all three clients received the request. `@types` documents
  -- `timeout_ms` as what is "passed to the LSP fallback" -- per client it is
  -- not a bound on the save at all.
  it("asks exactly one client, so timeout_ms bounds the whole format", function()
    local seen = {}
    attach({ { "first", true }, { "second", true } }, seen)
    assert.are.equal(2, #vim.lsp.get_clients({ bufnr = buf }))

    local fmt = require("lsp.formatter").build({ timeout_ms = 300 })
    local t0 = vim.uv.hrtime()
    fmt.format(buf)
    local elapsed_ms = (vim.uv.hrtime() - t0) / 1e6

    assert.are.same({ "first" }, seen)
    -- Unfixed: two mute clients at 300 ms each, ~625 ms. Fixed: one, ~310 ms.
    assert.is_true(
      elapsed_ms < 300 * 1.8,
      ("LSP fallback took %.0f ms for a 300 ms timeout"):format(elapsed_ms)
    )
  end)

  -- Which client is picked has to be the same on every save, or two formatters
  -- take turns rewriting the file. Lowest id = attached first.
  it("picks the same client on every save", function()
    local seen = {}
    attach({ { "alpha", false }, { "beta", false } }, seen)

    local fmt = require("lsp.formatter").build({ timeout_ms = 300 })
    fmt.format(buf)
    fmt.format(buf)

    assert.are.same({ "alpha", "alpha" }, seen)
  end)
end)

describe("lsp.diagnostics.loclist.to_loc", function()
  local ns, buf, tmp

  before_each(function()
    ns = vim.api.nvim_create_namespace("formatter_diagnostics_spec_loc")
    tmp = vim.fn.tempname() .. ".txt"
    vim.cmd("edit " .. vim.fn.fnameescape(tmp))
    buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "b", "c" })
    vim.diagnostic.set(ns, buf, {
      { lnum = 0, col = 0, message = "E1", severity = vim.diagnostic.severity.ERROR },
      { lnum = 1, col = 0, message = "W1", severity = vim.diagnostic.severity.WARN },
      { lnum = 2, col = 0, message = "I1", severity = vim.diagnostic.severity.INFO },
    })
  end)

  after_each(function()
    vim.diagnostic.reset(ns)
    vim.cmd("silent! lclose")
    vim.cmd("silent! bwipeout!")
    os.remove(tmp)
  end)

  -- A location list takes its buffer from its window, and `:DiagLoc` opens the
  -- location-list window with `lwindow`, which focuses it. So the second
  -- `:DiagLoc` looked at the window under the cursor -- the location-list
  -- window, whose buffer is the quickfix scratch buffer -- found no
  -- diagnostics there, and rebuilt the list empty; `lwindow` then closed it.
  --
  -- Measured on the unfixed file: `:DiagLoc` -> 3 entries, window type
  -- "loclist"; `:DiagLoc warn` immediately after -> 0 entries, window gone,
  -- no error and no message. The command meant to narrow the list wiped it.
  it("re-filters from the file window when run inside the loclist window", function()
    local loclist = require("lsp.diagnostics.loclist")

    loclist.to_loc({ open = true })
    assert.are.equal(3, #vim.fn.getloclist(0))
    assert.are.equal("loclist", vim.fn.win_gettype(0)) -- the cursor really did move

    loclist.to_loc({ open = true, severity = "warn" })
    local entries = vim.fn.getloclist(0)
    assert.are.equal(1, #entries)
    assert.are.equal("W1", entries[1].text)
  end)

  -- The same trap with the other kind of special window: a quickfix window has
  -- no `filewinid` to walk back through, so the fallback is the first ordinary
  -- window in the tabpage rather than the scratch buffer under the cursor.
  it("does not build the list from a quickfix window's scratch buffer", function()
    local loclist = require("lsp.diagnostics.loclist")

    vim.fn.setqflist({ { bufnr = buf, lnum = 1, text = "unrelated" } })
    vim.cmd("copen")
    assert.are.equal("quickfix", vim.fn.win_gettype(0))

    loclist.to_loc({ open = false })
    local target = vim.fn.getloclist(vim.fn.win_getid(1))
    vim.cmd("silent! cclose")
    assert.are.equal(3, #target)
  end)
end)

describe("lsp.diagnostics.quickfix.to_qf", function()
  local ns, a, b

  before_each(function()
    ns = vim.api.nvim_create_namespace("formatter_diagnostics_spec_qf")
    local function mk(suffix, diags)
      local id = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(id, vim.fn.tempname() .. suffix)
      vim.api.nvim_buf_set_lines(id, 0, -1, false, { "x", "y" })
      vim.diagnostic.set(ns, id, diags)
      return id
    end
    local S = vim.diagnostic.severity
    a = mk("A.txt", {
      { lnum = 0, col = 0, message = "A-E", severity = S.ERROR },
      { lnum = 1, col = 0, message = "A-W", severity = S.WARN },
    })
    b = mk("B.txt", { { lnum = 0, col = 0, message = "B-E", severity = S.ERROR } })
  end)

  after_each(function()
    vim.diagnostic.reset(ns)
    vim.fn.setqflist({}, "f")
    pcall(vim.api.nvim_buf_delete, a, { force = true })
    pcall(vim.api.nvim_buf_delete, b, { force = true })
  end)

  --- The list `vim.diagnostic` maintains is found by title, not by being the
  --- current one.
  ---@return table[]
  local function diagnostics_list()
    for nr = 1, vim.fn.getqflist({ nr = "$" }).nr do
      local list = vim.fn.getqflist({ nr = nr, title = 0, items = 0 })
      if list.title == "Diagnostics" then
        return list.items
      end
    end
    return {}
  end

  -- `to_qf` read `opts.bufnr` and handed it to `vim.diagnostic.setqflist`,
  -- which has no such option: its table goes to `vim.diagnostic.get(nil, opts)`
  -- and that function takes the buffer *positionally*, so the key rode along
  -- unread. `@types` documented `bufnr` as "target buffer". Measured on the
  -- unfixed file with two buffers holding three diagnostics between them:
  -- `to_qf({ bufnr = A })` produced all three entries, buffer B's included.
  it("restricts the list to the buffer it was given", function()
    local quickfix = require("lsp.diagnostics.quickfix")

    quickfix.to_qf({ open = false })
    assert.are.equal(3, #diagnostics_list())

    quickfix.to_qf({ open = false, bufnr = a })
    local items = diagnostics_list()
    assert.are.equal(2, #items)
    for _, item in ipairs(items) do
      assert.are.equal(a, item.bufnr)
    end
  end)

  it("still applies the severity filter inside one buffer", function()
    local quickfix = require("lsp.diagnostics.quickfix")

    quickfix.to_qf({ open = false, bufnr = a, severity = "error" })
    local items = diagnostics_list()
    assert.are.equal(1, #items)
    assert.are.equal("A-E", items[1].text)
  end)

  -- The buffer-scoped path sets the list by hand, so it has to keep Neovim's
  -- own title and update in place; otherwise `:DiagQF` would push a new list
  -- onto the ten-deep quickfix stack on every invocation and the workspace
  -- path would stop finding the one the buffer path wrote.
  it("updates one list instead of stacking a new one per call", function()
    local quickfix = require("lsp.diagnostics.quickfix")

    for _ = 1, 5 do
      quickfix.to_qf({ open = false, bufnr = a })
    end
    assert.are.equal(1, vim.fn.getqflist({ nr = "$" }).nr)

    quickfix.to_qf({ open = false })
    assert.are.equal(1, vim.fn.getqflist({ nr = "$" }).nr)
    assert.are.equal(3, #diagnostics_list())
  end)
end)

describe("lsp.diagnostics.commands", function()
  before_each(function()
    vim.g._diagnostics_cmds_enabled = nil
    require("lsp.diagnostics").setup()
  end)

  -- `ACTIONS.md` documented four bang forms as ways to "force" one list or the
  -- other. Measured: `:DiagNextQF!` and `:DiagPrevQF!` declared `bang = true`
  -- and no handler ever read `ctx.bang`, so the bang parsed and did nothing;
  -- `:DiagNextLoc!` and `:DiagPrevLoc!` did not declare it and answered
  -- "E477: No ! allowed". There is no mode to force -- `next_loc` always steps
  -- diagnostics, `next_qf` always steps the quickfix list -- so the four forms
  -- are gone from the docs and the two stray declarations with them. A
  -- modifier that is half ignored and half rejected is worse than none.
  it("declares no bang on any Diag command", function()
    local commands = vim.api.nvim_get_commands({})
    for _, name in ipairs({
      "DiagLoc",
      "DiagNextLoc",
      "DiagPrevLoc",
      "DiagQF",
      "DiagNextQF",
      "DiagPrevQF",
    }) do
      assert.is_table(commands[name], name .. " is not registered")
      assert.are.equal(false, commands[name].bang, name .. " still accepts a bang")
    end
  end)

  it("does not promise the bang forms in ACTIONS.md", function()
    local doc = table.concat(vim.fn.readfile("lua/lsp/diagnostics/ACTIONS.md"), "\n")
    for _, form in ipairs({ "DiagNextQF!", "DiagPrevQF!", "DiagNextLoc!", "DiagPrevLoc!" }) do
      -- Mentioned in the note that explains their removal, never as a bullet
      -- offering them.
      assert.is_nil(
        doc:match("%*%s*`:" .. form:gsub("!", "!") .. "[^`]*`"),
        "ACTIONS.md still offers :" .. form
      )
    end
  end)
end)
