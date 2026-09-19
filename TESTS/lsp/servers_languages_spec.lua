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
end)

describe("lsp.languages.documentation.markdown_words", function()
  after_each(function()
    package.loaded["lsp.languages.documentation.markdown_words"] = nil
  end)

  -- `max_files` was tested once per *directory*, in the outer loop of the
  -- walk, so any single directory was drained in full however large. It is the
  -- only bound on a scan that blocks the editor -- `rebuild_async` defers by a
  -- tick and then reads every file synchronously, measured at 82ms for 400
  -- small files -- so the cap has to hold per file, not per directory.
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
