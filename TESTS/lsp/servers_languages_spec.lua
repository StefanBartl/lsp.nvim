--- Two caches that outlived what they were caching.
---
--- Marksman's diagnostics handler keeps every URI it has ever seen so the
--- hints toggle can re-filter instantly, and `markdown_words` scans the
--- project once and holds the result. Both were correct about the data and
--- wrong about its extent.

describe("lsp.servers.marksman.diagnostics_handler", function()
  local saved

  before_each(function()
    saved = vim.lsp.get_client_by_id
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.get_client_by_id = function(id)
      return { id = id, name = "marksman" }
    end
  end)

  after_each(function()
    vim.lsp.get_client_by_id = saved
    package.loaded["lsp.servers.marksman.diagnostics_handler"] = nil
  end)

  ---@return table
  local function one_hint()
    return {
      {
        message = "a hint",
        severity = 4,
        range = {
          start = { line = 0, character = 0 },
          ["end"] = { line = 0, character = 1 },
        },
      },
    }
  end

  -- `republish_all` walked every URI it had ever cached, and Neovim's own
  -- publishDiagnostics handler resolves a URI through `vim.uri_to_bufnr`,
  -- which *creates* a buffer when none exists. So one `:LspMdHints` brought
  -- back a buffer for every markdown file the session had visited, with its
  -- diagnostics on it. Measured: close a file, toggle, and it is back.
  --
  -- Dropping the closed ones is also what bounds the cache: it is keyed by URI
  -- and nothing else ever removed an entry.
  it("does not resurrect a file the user closed", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local path = dir .. "/gone.md"
    vim.fn.writefile({ "# gone" }, path)

    local dh = require("lsp.servers.marksman.diagnostics_handler")
    local handler = dh.make_handler()

    vim.cmd.edit(vim.fn.fnameescape(path))
    local bufnr = vim.api.nvim_get_current_buf()
    local uri = vim.uri_from_bufnr(bufnr)
    handler(nil, { uri = uri, diagnostics = one_hint() }, {
      client_id = 1,
      method = "textDocument/publishDiagnostics",
      bufnr = bufnr,
    }, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
    local before = #vim.api.nvim_list_bufs()

    dh.republish_all()

    assert.are.equal(before, #vim.api.nvim_list_bufs(), "a closed file came back as a buffer")
    -- And it is out of the cache, so the next toggle has nothing to resurrect.
    dh.republish_all()
    assert.are.equal(before, #vim.api.nvim_list_bufs())

    pcall(vim.fn.delete, dir, "rf")
  end)

  -- The server and Neovim spell one file differently: marksman sends
  -- `file:///e%3A/repos/x.md` where `vim.uri_from_bufnr` says
  -- `file:///e:/repos/x.md` (measured on Windows). Comparing raw URIs made
  -- every open buffer look closed, so `republish_all` dropped it from the cache
  -- and the hints toggle did nothing until the server's next push. A
  -- percent-encoded first letter is a spelling that differs on every platform.
  it("republishes an open file whatever way the server spelled its URI", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local path = dir .. "/open.md"
    vim.fn.writefile({ "# open" }, path)

    local published = {}
    local key = "textDocument/publishDiagnostics"
    local real_handler = vim.lsp.handlers[key]
    vim.lsp.handlers[key] = function(_, result)
      published[#published + 1] = result.uri
    end

    vim.cmd.edit(vim.fn.fnameescape(path))
    local uri = vim.uri_from_bufnr(vim.api.nvim_get_current_buf())
    local odd = uri:gsub("/([^/])([^/]*)$", function(first, rest)
      return ("/%%%02X%s"):format(first:byte(), rest)
    end)
    assert.are_not.equal(uri, odd)

    local dh = require("lsp.servers.marksman.diagnostics_handler")
    dh.make_handler()(nil, { uri = odd, diagnostics = one_hint() }, {
      client_id = 1,
      method = "textDocument/publishDiagnostics",
    }, nil)
    published = {}

    dh.republish_all()
    vim.lsp.handlers[key] = real_handler

    assert.are.same({ odd }, published, "an open file was taken for a closed one")
    pcall(vim.fn.delete, dir, "rf")
  end)
end)

describe("lsp.languages.documentation.markdown_words", function()
  after_each(function()
    package.loaded["lsp.languages.documentation.markdown_words"] = nil
  end)

  -- `max_files` was tested once per *directory*, in the outer loop of the
  -- walk, so any single directory was drained in full however large. It is the
  -- bound on how much a scan reads -- `rebuild_async` reads every collected
  -- file synchronously (in slices; one pass used to take 82ms for 400 small
  -- files) -- so the cap has to hold per file, not per directory.
  --
  -- 600 files in one directory against a cap of 500, each carrying one unique
  -- word, so the cached word count is the file count.
  it("stops collecting at max_files even inside one directory", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    for i = 1, 600 do
      vim.fn.writefile({ ("marker%04d"):format(i) }, ("%s/f%04d.md"):format(dir, i))
    end

    local mw = require("lsp.languages.documentation.markdown_words")
    mw.set_root(dir)
    local built = vim.wait(30000, function()
      return mw.stats().cached
    end, 20)

    assert.is_true(built, "the rebuild never finished")
    assert.are.equal(500, mw.stats().words, "the cap was ignored inside the directory")

    pcall(vim.fn.delete, dir, "rf")
  end)

  -- `max_files` counts only *matching* files, so a tree with few Markdown files
  -- (a home directory, %TEMP%) used to be walked to its last directory: measured
  -- 7176 directories and 32 000 entries for 501 files, one freeze of ~1.3 s up
  -- to many seconds. `max_dirs` bounds the directories opened.
  --
  -- 20 sibling directories with one file each against a cap of 5: the root
  -- counts as one, so four of the twenty are read.
  it("stops walking at max_dirs even when few files match", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    for i = 1, 20 do
      vim.fn.mkdir(("%s/d%02d"):format(dir, i), "p")
      vim.fn.writefile({ ("dirword%02d"):format(i) }, ("%s/d%02d/n.md"):format(dir, i))
    end

    local mw = require("lsp.languages.documentation.markdown_words")
    mw.setup({ max_dirs = 5 })
    mw.set_root(dir)
    local built = vim.wait(30000, function()
      local s = mw.stats()
      return s.cached and not s.building
    end, 20)

    assert.is_true(built, "the rebuild never finished")
    assert.are.equal(4, mw.stats().words, "the walk ignored max_dirs")

    pcall(vim.fn.delete, dir, "rf")
  end)

  -- A rebuild spans many event-loop ticks now. A root that arrives while one is
  -- running has to *replace* it: the old guard dropped the request, which was
  -- harmless while a rebuild fitted into one tick and would otherwise leave the
  -- cache on the old root with nothing left to trigger the new one.
  it("lets a new root replace a rebuild that is still running", function()
    local big = vim.fn.tempname()
    vim.fn.mkdir(big, "p")
    for i = 1, 200 do
      vim.fn.mkdir(("%s/d%03d"):format(big, i), "p")
      vim.fn.writefile({ "bigword" .. i }, ("%s/d%03d/x.md"):format(big, i))
    end
    local small = vim.fn.tempname()
    vim.fn.mkdir(small, "p")
    vim.fn.writefile({ "smallonly alpha beta" }, small .. "/a.md")

    local mw = require("lsp.languages.documentation.markdown_words")
    mw.set_root(big)
    mw.set_root(small) -- arrives while `big` is still building
    local built = vim.wait(30000, function()
      local s = mw.stats()
      return s.cached and not s.building
    end, 20)

    assert.is_true(built, "the rebuild never finished")
    assert.are.equal(vim.fs.normalize(small), vim.fs.normalize(mw.stats().root))
    assert.are.equal(3, mw.stats().words, "the cache holds the superseded root's words")

    pcall(vim.fn.delete, big, "rf")
    pcall(vim.fn.delete, small, "rf")
  end)

  -- `set_root` used to pass its argument straight through `vim.fn.expand()`,
  -- Vim's *filename* expansion -- a backtick span in the argument is a
  -- command substitution over `&shell`. `:MdSetRoot` argument is exactly
  -- that argument.
  it("does not run a shell command embedded via backticks in the root (SEC-34)", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local marker = dir .. "/sec34_marker"
    pcall(vim.fn.delete, marker)

    local mw = require("lsp.languages.documentation.markdown_words")
    mw.set_root("`touch " .. marker .. "`")
    vim.wait(2000, function()
      return mw.stats().cached
    end, 20)

    assert.are.equal(0, vim.fn.filereadable(marker), "the backtick span ran as a shell command")

    pcall(vim.fn.delete, dir, "rf")
  end)

  it(
    "still expands ~ in the root, which is all the replacement is meant to keep (SEC-34)",
    function()
      -- A stubbed home directory, not the real one: `~` on this machine is a
      -- large real tree, and the point here is the substitution, not a scan of
      -- it.
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")

      local uv = vim.uv or vim.loop
      local real_homedir = uv.os_homedir
      ---@diagnostic disable-next-line: duplicate-set-field
      uv.os_homedir = function()
        return dir
      end

      local mw = require("lsp.languages.documentation.markdown_words")
      mw.set_root("~")
      local built = vim.wait(2000, function()
        return mw.stats().cached
      end, 10)

      uv.os_homedir = real_homedir

      assert.is_true(built, "the rebuild never finished")
      assert.are.equal(dir, mw.stats().root)

      pcall(vim.fn.delete, dir, "rf")
    end
  )
end)
