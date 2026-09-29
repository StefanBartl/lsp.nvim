--- Covers `$VAR/...` and `~/...` Markdown links: `lsp.core.env_links` (the
--- resolution), the marksman diagnostics filter that uses it, and
--- `lsp.core.env_links_server` (definition and hover).
---
--- The starting point was measured against real marksman: for
--- `[x]($REPOS_DIR/a.md)` it answers no definition and no hover, and reports
--- "Link to non-existent document" for a file that exists. Both halves are
--- asserted here on what the *consumer* sees -- the diagnostics that survive
--- the filter, the location a real client request returns -- not on which
--- internal function ran.
---
--- gopath.nvim is stubbed through `package.loaded`/`package.preload` so the
--- two resolution paths (gopath first, built-in otherwise) are both exercised
--- and neither depends on whether gopath happens to be on the runtimepath.

local uv = vim.uv or vim.loop

---@param path string
---@param text string
local function write_file(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local fd = assert(uv.fs_open(path, "w", 420))
  uv.fs_write(fd, text)
  uv.fs_close(fd)
end

---@param path string
---@return string
local function real(path)
  return (vim.fs.normalize(uv.fs_realpath(path) or path))
end

describe("lsp.core.env_links", function()
  local links
  ---@type string
  local root

  --- No gopath: `require("gopath")` raises, as on a machine without it.
  ---@return nil
  local function without_gopath()
    package.loaded["gopath"] = nil
    package.preload["gopath"] = function()
      error("gopath is not installed")
    end
  end

  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    root = real(root)
    vim.env.LSPTEST_ENV_ROOT = root
    write_file(root .. "/notes/a.md", "# A\n")
    package.loaded["lsp.core.env_links"] = nil
    links = require("lsp.core.env_links")
    without_gopath()
  end)

  after_each(function()
    vim.env.LSPTEST_ENV_ROOT = nil
    package.preload["gopath"] = nil
    package.loaded["gopath"] = nil
    vim.fn.delete(root, "rf")
  end)

  describe("is_env_target", function()
    it("recognises $VAR, ${VAR} and ~", function()
      for _, t in ipairs({ "$A/x.md", "${A}/x.md", "$A", "~", "~/x.md", "~\\x.md", "$_a/x" }) do
        assert.is_true(links.is_env_target(t), t)
      end
    end)

    it("refuses everything the user's shell would not expand", function()
      for _, t in ipairs({
        "./x.md",
        "../x.md",
        "x.md",
        "https://example.com",
        "C:\\x.md",
        "/abs/x.md",
        "$",
        "$1",
        "~user/x",
        "",
      }) do
        assert.is_false(links.is_env_target(t), t)
      end
      assert.is_false(links.is_env_target(nil))
      assert.is_false(links.is_env_target(42))
    end)
  end)

  describe("split", function()
    it("separates the fragment", function()
      local path, fragment = links.split("$A/x.md#some-heading")
      assert.are.equal("$A/x.md", path)
      assert.are.equal("some-heading", fragment)
    end)

    it("undoes percent-encoding and drops angle brackets", function()
      assert.are.equal("$A/my notes.md", (links.split("$A/my%20notes.md")))
      assert.are.equal("$A/my notes.md", (links.split("<$A/my notes.md>")))
    end)

    it("has no fragment when there is none", function()
      local _, fragment = links.split("$A/x.md")
      assert.is_nil(fragment)
    end)
  end)

  describe("resolve (built-in)", function()
    it("resolves $VAR and ${VAR}, forward and backward separators", function()
      for _, form in ipairs({
        "$LSPTEST_ENV_ROOT/notes/a.md",
        "${LSPTEST_ENV_ROOT}/notes/a.md",
        "$LSPTEST_ENV_ROOT\\notes\\a.md",
      }) do
        local r = links.resolve(form)
        assert.is_truthy(r, form)
        assert.are.equal(root .. "/notes/a.md", r.path, form)
        assert.is_true(r.exists, form)
        assert.are.equal("builtin", r.source)
      end
    end)

    it("says so when the file is not there", function()
      local r = links.resolve("$LSPTEST_ENV_ROOT/notes/gone.md")
      assert.is_truthy(r)
      assert.is_false(r.exists)
      assert.are.equal(root .. "/notes/gone.md", r.path)
    end)

    it("treats a directory as existing", function()
      local r = links.resolve("$LSPTEST_ENV_ROOT/notes")
      assert.is_true(r.exists)
    end)

    it("resolves a bare $VAR to the directory itself", function()
      assert.are.equal(root, links.resolve("$LSPTEST_ENV_ROOT").path)
    end)

    it("keeps the fragment", function()
      assert.are.equal("intro", links.resolve("$LSPTEST_ENV_ROOT/notes/a.md#intro").fragment)
    end)

    -- Cannot tell is not the same as broken: the caller must be able to
    -- leave such a link alone.
    it("answers nil for a variable nothing defines", function()
      assert.is_nil(links.resolve("$LSPTEST_DEFINITELY_UNSET/x.md"))
    end)

    it("answers nil for a target that is not an env reference", function()
      assert.is_nil(links.resolve("./notes/a.md"))
    end)

    it('resolves $NVIM_CONFIG_DIR from stdpath("config") with no real variable', function()
      local saved = vim.env.NVIM_CONFIG_DIR
      vim.env.NVIM_CONFIG_DIR = nil
      local r = links.resolve("$NVIM_CONFIG_DIR/init.lua")
      vim.env.NVIM_CONFIG_DIR = saved

      assert.is_truthy(r)
      assert.are.equal(vim.fs.normalize(vim.fn.stdpath("config")) .. "/init.lua", r.path)
    end)

    it("lets a real variable win over the well-known directory", function()
      local saved = vim.env.NVIM_CONFIG_DIR
      vim.env.NVIM_CONFIG_DIR = root
      local r = links.resolve("$NVIM_CONFIG_DIR/notes/a.md")
      vim.env.NVIM_CONFIG_DIR = saved

      assert.are.equal(root .. "/notes/a.md", r.path)
    end)

    it("resolves ~ against the home directory", function()
      local home = vim.fs.normalize(vim.uv.os_homedir())
      assert.are.equal(home .. "/some/x.md", links.resolve("~/some/x.md").path)
      assert.are.equal(home, links.resolve("~").path)
    end)

    it("decodes percent-encoding before resolving", function()
      write_file(root .. "/my notes.md", "x")
      local r = links.resolve("$LSPTEST_ENV_ROOT/my%20notes.md")
      assert.is_true(r.exists)
    end)
  end)

  describe("resolve (via gopath.nvim)", function()
    ---@param impl fun(text: string): table|nil
    ---@return string[] asked
    local function with_gopath(impl)
      local asked = {}
      package.preload["gopath"] = nil
      package.loaded["gopath"] = {
        resolve_text = function(text)
          asked[#asked + 1] = text
          return impl(text)
        end,
      }
      return asked
    end

    it("asks gopath, and uses its answer", function()
      local asked = with_gopath(function()
        return { kind = "file", path = "C:\\somewhere\\else.md", exists = true }
      end)

      local r = links.resolve("$WHATEVER/x.md#frag")

      assert.are.same({ "$WHATEVER/x.md" }, asked, "the fragment is not gopath's business")
      assert.are.equal("C:/somewhere/else.md", r.path, "separators are normalised")
      assert.is_true(r.exists)
      assert.are.equal("gopath", r.source)
      assert.are.equal("frag", r.fragment)
    end)

    it("takes `exists = false` from gopath at its word", function()
      with_gopath(function()
        return { kind = "file", path = root .. "/notes/a.md", exists = false }
      end)
      assert.is_false(links.resolve("$LSPTEST_ENV_ROOT/notes/a.md").exists)
    end)

    it("falls back to the built-in resolver when gopath does not recognise it", function()
      with_gopath(function()
        return nil
      end)
      local r = links.resolve("$LSPTEST_ENV_ROOT/notes/a.md")
      assert.are.equal("builtin", r.source)
      assert.is_true(r.exists)
    end)

    it("falls back when gopath raises", function()
      with_gopath(function()
        error("boom")
      end)
      assert.are.equal("builtin", links.resolve("$LSPTEST_ENV_ROOT/notes/a.md").source)
    end)

    it("falls back when this gopath predates resolve_text", function()
      package.preload["gopath"] = nil
      package.loaded["gopath"] = { resolve = function() end }
      assert.are.equal("builtin", links.resolve("$LSPTEST_ENV_ROOT/notes/a.md").source)
    end)

    it("ignores a URL answer", function()
      with_gopath(function()
        return { kind = "url", path = "https://example.com", exists = true }
      end)
      assert.are.equal("builtin", links.resolve("$LSPTEST_ENV_ROOT/notes/a.md").source)
    end)

    it("does not ask gopath about ~", function()
      local asked = with_gopath(function()
        return { kind = "file", path = "/nope", exists = true }
      end)
      links.resolve("~/x.md")
      assert.are.same({}, asked)
    end)
  end)

  describe("target_at", function()
    local cases = {
      -- { line, 1-based column, expected }
      { "[a]($R/x.md)", 1, "$R/x.md" },
      { "[a]($R/x.md)", 3, "$R/x.md" },
      { "[a]($R/x.md)", 8, "$R/x.md" },
      { "[a]($R/x.md)", 12, "$R/x.md" },
      { "see [a]($R/x.md) and [b](./y.md)", 8, "$R/x.md" },
      { "see [a]($R/x.md) and [b](./y.md)", 26, "./y.md" },
      { "![img]($R/pic.png)", 4, "$R/pic.png" },
      { "[a](<$R/my notes.md>)", 6, "$R/my notes.md" },
      { '[a]($R/x.md "a title")', 8, "$R/x.md" },
      { "[a]($R/x.md#frag)", 8, "$R/x.md#frag" },
      { "[a](${R}/x.md)", 8, "${R}/x.md" },
      { "[label]: $R/x.md", 3, "$R/x.md" },
      { "[label]: <$R/x.md>", 12, "$R/x.md" },
      -- Outside every link.
      { "see [a]($R/x.md) and more", 2, nil },
      { "see [a]($R/x.md) and more", 22, nil },
      { "plain text", 3, nil },
      { "[a](", 3, nil },
    }

    for _, c in ipairs(cases) do
      it(("%q at %d"):format(c[1], c[2]), function()
        assert.are.equal(c[3], links.target_at(c[1], c[2]))
      end)
    end

    it("finds the right link when the line has several", function()
      local line = "[one]($A/1.md) [two]($B/2.md) [three]($C/3.md)"
      assert.are.equal("$B/2.md", links.target_at(line, line:find("two", 1, true)))
    end)
  end)

  describe("verdict", function()
    ---@param target string
    ---@return string
    local function msg(target)
      return ("Link to non-existent document '%s'"):format(target)
    end

    it("drops the false alarm: the env link names a file that exists", function()
      local verdict = links.verdict(msg("$LSPTEST_ENV_ROOT/notes/a.md"))
      assert.are.equal("drop", verdict)
    end)

    it("keeps the real one, and says where it looked", function()
      local verdict, resolved = links.verdict(msg("$LSPTEST_ENV_ROOT/notes/gone.md"))
      assert.are.equal("keep", verdict)
      assert.are.equal(root .. "/notes/gone.md", resolved.path)
    end)

    it("has no opinion on an ordinary link", function()
      assert.is_nil((links.verdict(msg("./gone.md"))))
      assert.is_nil((links.verdict(msg("gone.md"))))
    end)

    it("has no opinion when the variable is not defined", function()
      assert.is_nil((links.verdict(msg("$LSPTEST_DEFINITELY_UNSET/x.md"))))
    end)

    it("has no opinion on other diagnostics", function()
      assert.is_nil((links.verdict("Ambiguous link to document '$LSPTEST_ENV_ROOT/x.md'")))
      assert.is_nil((links.verdict("Link to non-existent link definition 'x'")))
    end)

    it("does not raise on a message that is not a string", function()
      assert.is_nil((links.verdict(nil)))
      assert.is_nil((links.verdict(42)))
    end)
  end)

  describe("heading_line", function()
    before_each(function()
      write_file(
        root .. "/h.md",
        table.concat({
          "# Title", -- 0
          "", -- 1
          "```", -- 2
          "# not a heading", -- 3
          "```", -- 4
          "## Second Part", -- 5
          "text", -- 6
          "### Übersicht & Fazit ###", -- 7
          "## Second Part", -- 8 (duplicate: first wins)
        }, "\n")
      )
    end)

    it("finds a heading by its anchor", function()
      assert.are.equal(0, links.heading_line(root .. "/h.md", "title"))
      assert.are.equal(5, links.heading_line(root .. "/h.md", "second-part"))
    end)

    it("is case-insensitive on the fragment", function()
      assert.are.equal(5, links.heading_line(root .. "/h.md", "Second-Part"))
    end)

    it("keeps non-ASCII letters and drops punctuation", function()
      assert.are.equal(7, links.heading_line(root .. "/h.md", "übersicht--fazit"))
    end)

    it("does not see a heading inside a fenced code block", function()
      assert.is_nil(links.heading_line(root .. "/h.md", "not-a-heading"))
    end)

    it("is nil for an unknown anchor or an unreadable file", function()
      assert.is_nil(links.heading_line(root .. "/h.md", "nope"))
      assert.is_nil(links.heading_line(root .. "/missing.md", "title"))
    end)
  end)
end)

describe("lsp.servers.marksman.diagnostics_handler with env links", function()
  ---@type string
  local root
  local handler

  ---@param message string
  ---@param severity? integer
  ---@return table
  local function diag(message, severity)
    return {
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 1 } },
      severity = severity or 1,
      message = message,
    }
  end

  ---@param diagnostics table[]
  ---@return string[]
  local function messages(diagnostics)
    local out = {}
    for _, d in ipairs(handler.filter_diagnostics(diagnostics)) do
      out[#out + 1] = d.message
    end
    return out
  end

  before_each(function()
    root = real(vim.fn.tempname())
    vim.fn.mkdir(root, "p")
    root = real(root)
    vim.env.LSPTEST_ENV_ROOT = root
    write_file(root .. "/exists.md", "# x\n")
    package.preload["gopath"] = function()
      error("gopath is not installed")
    end
    package.loaded["gopath"] = nil
    package.loaded["lsp.servers.marksman.diagnostics_handler"] = nil
    handler = require("lsp.servers.marksman.diagnostics_handler")
    require("lsp.config").setup({})
  end)

  after_each(function()
    vim.env.LSPTEST_ENV_ROOT = nil
    package.preload["gopath"] = nil
    require("lsp.config").setup({})
    vim.fn.delete(root, "rf")
  end)

  local function all()
    return {
      diag("Link to non-existent document '$LSPTEST_ENV_ROOT/exists.md'"),
      diag("Link to non-existent document '$LSPTEST_ENV_ROOT/gone.md'"),
      diag("Link to non-existent document './plain.md'"),
      diag("Ambiguous link to document 'x.md'", 2),
    }
  end

  it("drops the env link whose file exists, keeps the broken one and other diagnostics", function()
    local got = messages(all())

    assert.are.equal(2, #got, vim.inspect(got))
    assert.is_truthy(got[1]:find("gone.md", 1, true))
    assert.is_truthy(got[2]:find("Ambiguous link to document", 1, true))
  end)

  it("names the path a kept env link was looked up at", function()
    local got = messages(all())
    assert.is_truthy(got[1]:find("resolved to " .. root .. "/gone.md", 1, true), got[1])
  end)

  -- The blanket rule is older than this and covers every other kind of link;
  -- it must keep doing so.
  it("still hides an ordinary missing document, as before", function()
    for _, m in ipairs(messages(all())) do
      assert.is_nil(m:find("plain.md", 1, true), m)
    end
  end)

  it("leaves the diagnostics untouched when languages.env_links is off", function()
    require("lsp.config").setup({ languages = { env_links = false } })
    local got = messages(all())

    -- Back to the blanket: every "non-existent document" is hidden, the
    -- existing env link and the broken one alike.
    assert.are.equal(1, #got, vim.inspect(got))
    assert.is_truthy(got[1]:find("Ambiguous link to document", 1, true))
  end)

  it("does not mutate the diagnostics it was given", function()
    local input = all()
    local before = vim.deepcopy(input)
    handler.filter_diagnostics(input)
    assert.are.same(before, input)
  end)
end)

describe("lsp.core.env_links_server", function()
  local server
  ---@type string
  local root

  --- LSP params for a position in a buffer holding `path`.
  ---@param bufnr integer
  ---@param lnum integer # 0-based
  ---@param character integer # UTF-16 code units
  ---@return table
  local function params(bufnr, lnum, character)
    return {
      textDocument = { uri = vim.uri_from_bufnr(bufnr) },
      position = { line = lnum, character = character },
    }
  end

  ---@param path string
  ---@param text string
  ---@return integer bufnr
  local function doc(path, text)
    write_file(path, text)
    local bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)
    return bufnr
  end

  before_each(function()
    root = real(vim.fn.tempname())
    vim.fn.mkdir(root, "p")
    root = real(root)
    vim.env.LSPTEST_ENV_ROOT = root
    package.preload["gopath"] = function()
      error("gopath is not installed")
    end
    package.loaded["gopath"] = nil
    for _, name in ipairs({ "lsp.core.env_links", "lsp.core.env_links_server" }) do
      package.loaded[name] = nil
    end
    server = require("lsp.core.env_links_server")
    write_file(root .. "/target.md", "# Target\n\nfirst body line\n\n## Deep Section\nmore\n")
  end)

  after_each(function()
    server.detach()
    vim.wait(300, function()
      return #vim.lsp.get_clients({ name = server.NAME }) == 0
    end)
    vim.env.LSPTEST_ENV_ROOT = nil
    package.preload["gopath"] = nil
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    vim.fn.delete(root, "rf")
  end)

  describe("definition", function()
    it("returns the file an env link names", function()
      local buf = doc(root .. "/doc.md", "[t]($LSPTEST_ENV_ROOT/target.md)\n")
      local res = server.definition(params(buf, 0, 8))

      assert.is_truthy(res)
      assert.are.equal(vim.uri_from_fname(root .. "/target.md"), res[1].uri)
      assert.are.equal(0, res[1].range.start.line)
    end)

    it("jumps to the heading a #fragment names", function()
      local buf = doc(root .. "/doc.md", "[t]($LSPTEST_ENV_ROOT/target.md#deep-section)\n")
      local res = server.definition(params(buf, 0, 8))
      assert.are.equal(4, res[1].range.start.line)
    end)

    it("falls back to the top of the file for a fragment it cannot find", function()
      local buf = doc(root .. "/doc.md", "[t]($LSPTEST_ENV_ROOT/target.md#nope)\n")
      assert.are.equal(0, server.definition(params(buf, 0, 8))[1].range.start.line)
    end)

    it("works when non-ASCII text precedes the link (UTF-16 vs bytes)", function()
      -- "Übersicht äöü " is 14 UTF-16 units but 18 bytes: a link found by byte
      -- offset alone would be off by four.
      local line = "Übersicht äöü [t]($LSPTEST_ENV_ROOT/target.md)"
      local buf = doc(root .. "/doc.md", line .. "\n")
      local res = server.definition(params(buf, 0, 14 + 8))
      assert.is_truthy(res)
      assert.are.equal(vim.uri_from_fname(root .. "/target.md"), res[1].uri)
    end)

    it("answers nothing on an ordinary link, so marksman's answer stands alone", function()
      local buf = doc(root .. "/doc.md", "[t](./target.md) [u]($LSPTEST_ENV_ROOT/target.md)\n")
      assert.is_nil(server.definition(params(buf, 0, 8)))
    end)

    it("answers nothing off a link", function()
      local buf = doc(root .. "/doc.md", "plain [t]($LSPTEST_ENV_ROOT/target.md) text\n")
      assert.is_nil(server.definition(params(buf, 0, 1)))
      assert.is_nil(server.definition(params(buf, 0, 42)))
    end)

    it("answers nothing for a file that is not there", function()
      local buf = doc(root .. "/doc.md", "[t]($LSPTEST_ENV_ROOT/gone.md)\n")
      assert.is_nil(server.definition(params(buf, 0, 8)))
    end)

    it("answers nothing for an undefined variable", function()
      local buf = doc(root .. "/doc.md", "[t]($LSPTEST_DEFINITELY_UNSET/x.md)\n")
      assert.is_nil(server.definition(params(buf, 0, 8)))
    end)

    it("does not raise on a malformed request", function()
      assert.is_nil(server.definition(nil))
      assert.is_nil(server.definition({}))
      assert.is_nil(server.definition({ textDocument = { uri = "file:///x" } }))
    end)
  end)

  describe("hover", function()
    it("shows where the link leads and the top of the file", function()
      local buf = doc(root .. "/doc.md", "[t]($LSPTEST_ENV_ROOT/target.md)\n")
      local res = server.hover(params(buf, 0, 8))

      assert.is_truthy(res)
      assert.are.equal("markdown", res.contents.kind)
      assert.is_truthy(res.contents.value:find(root .. "/target.md", 1, true))
      assert.is_truthy(res.contents.value:find("first body line", 1, true))
    end)

    it("still answers for a missing file, saying so", function()
      local buf = doc(root .. "/doc.md", "[t]($LSPTEST_ENV_ROOT/gone.md)\n")
      local res = server.hover(params(buf, 0, 8))
      assert.is_truthy(res)
      assert.is_truthy(res.contents.value:find("(missing)", 1, true))
      assert.is_truthy(res.contents.value:find(root .. "/gone.md", 1, true))
    end)

    it("marks a directory as one instead of previewing it", function()
      local buf = doc(root .. "/doc.md", "[t]($LSPTEST_ENV_ROOT)\n")
      assert.is_truthy(server.hover(params(buf, 0, 8)).contents.value:find("directory", 1, true))
    end)

    it("answers nothing on an ordinary link or off a link", function()
      local buf = doc(root .. "/doc.md", "[t](./target.md) plain\n")
      assert.is_nil(server.hover(params(buf, 0, 8)))
      assert.is_nil(server.hover(params(buf, 0, 20)))
    end)
  end)

  describe("as a client", function()
    ---@param path string
    ---@param text string
    ---@return integer bufnr
    local function open_markdown(path, text)
      write_file(path, text)
      vim.cmd.edit(vim.fn.fnameescape(path))
      return vim.api.nvim_get_current_buf()
    end

    it("attaches to a Markdown buffer and answers a definition request", function()
      server.setup({ env_links = true })
      local buf = open_markdown(root .. "/doc.md", "[t]($LSPTEST_ENV_ROOT/target.md)\n")

      assert.is_true(
        vim.wait(3000, function()
          return #vim.lsp.get_clients({ bufnr = buf, name = server.NAME }) > 0
        end),
        "the client never attached"
      )

      local results =
        vim.lsp.buf_request_sync(buf, "textDocument/definition", params(buf, 0, 8), 3000)
      local found
      for _, r in pairs(results or {}) do
        if r.result then
          found = r.result
        end
      end
      assert.is_truthy(found)
      assert.are.equal(vim.uri_from_fname(root .. "/target.md"), found[1].uri)
    end)

    it("answers hover through the same client", function()
      server.setup({ env_links = true })
      local buf = open_markdown(root .. "/doc.md", "[t]($LSPTEST_ENV_ROOT/target.md)\n")
      assert.is_true(vim.wait(3000, function()
        return #vim.lsp.get_clients({ bufnr = buf, name = server.NAME }) > 0
      end))

      local results = vim.lsp.buf_request_sync(buf, "textDocument/hover", params(buf, 0, 8), 3000)
      local found
      for _, r in pairs(results or {}) do
        if r.result then
          found = r.result
        end
      end
      assert.is_truthy(found)
      assert.is_truthy(found.contents.value:find("first body line", 1, true))
    end)

    it("attaches by default, with no options", function()
      server.setup(nil)
      local buf = open_markdown(root .. "/doc.md", "# x\n")
      assert.is_true(vim.wait(3000, function()
        return #vim.lsp.get_clients({ bufnr = buf, name = server.NAME }) > 0
      end))
    end)

    it("does not attach when languages.env_links is off", function()
      server.setup({ env_links = false })
      local buf = open_markdown(root .. "/doc.md", "# x\n")
      vim.wait(500, function()
        return false
      end)
      assert.are.equal(0, #vim.lsp.get_clients({ bufnr = buf, name = server.NAME }))
    end)

    it("does not attach to a non-Markdown buffer", function()
      server.setup({ env_links = true })
      write_file(root .. "/x.lua", "-- x\n")
      vim.cmd.edit(vim.fn.fnameescape(root .. "/x.lua"))
      local buf = vim.api.nvim_get_current_buf()
      vim.wait(500, function()
        return false
      end)
      assert.are.equal(0, #vim.lsp.get_clients({ bufnr = buf, name = server.NAME }))
    end)

    it("does not attach to a scratch buffer", function()
      server.setup({ env_links = true })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].filetype = "markdown"
      vim.wait(500, function()
        return false
      end)
      assert.are.equal(0, #vim.lsp.get_clients({ bufnr = buf, name = server.NAME }))
    end)

    it("serves every Markdown buffer with one client", function()
      server.setup({ env_links = true })
      local a = open_markdown(root .. "/a.md", "# a\n")
      local b = open_markdown(root .. "/b.md", "# b\n")
      assert.is_true(vim.wait(3000, function()
        return #vim.lsp.get_clients({ bufnr = a, name = server.NAME }) > 0
          and #vim.lsp.get_clients({ bufnr = b, name = server.NAME }) > 0
      end))
      assert.are.equal(1, #vim.lsp.get_clients({ name = server.NAME }))
    end)

    it("stops its client on detach", function()
      server.setup({ env_links = true })
      local buf = open_markdown(root .. "/doc.md", "# x\n")
      assert.is_true(vim.wait(3000, function()
        return #vim.lsp.get_clients({ bufnr = buf, name = server.NAME }) > 0
      end))
      server.detach()
      assert.is_true(vim.wait(3000, function()
        return #vim.lsp.get_clients({ name = server.NAME }) == 0
      end))
    end)

    it("is looked past by the helpers that list a buffer's language servers", function()
      server.setup({ env_links = true })
      local buf = open_markdown(root .. "/doc.md", "# x\n")
      assert.is_true(vim.wait(3000, function()
        return #vim.lsp.get_clients({ bufnr = buf, name = server.NAME }) > 0
      end))
      local util = require("lsp.core.util")
      for _, client in ipairs(util.server_clients(buf)) do
        assert.are_not.equal(server.NAME, client.name)
      end
    end)
  end)
end)
