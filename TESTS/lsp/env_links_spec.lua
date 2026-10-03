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
      assert.are.equal(root, links.resolve("${LSPTEST_ENV_ROOT}").path)
    end)

    -- In a shell `${VAR}foo` is the value with `foo` glued on; nothing below
    -- the folder. Guessing a separator would resolve it to a file it never named.
    it("does not guess at `${VAR}` with text glued to it", function()
      assert.is_nil(links.resolve("${LSPTEST_ENV_ROOT}notes/a.md"))
      assert.is_nil(links.resolve("$LSPTEST_ENV_ROOTnotes/a.md"))
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
      local backslashed = (root .. "/notes/a.md"):gsub("/", string.char(92))
      local asked = with_gopath(function()
        return { kind = "file", path = backslashed, exists = false }
      end)

      local r = links.resolve("$WHATEVER/x.md#frag")

      assert.are.same({ "$WHATEVER/x.md" }, asked, "the fragment is not gopath's business")
      assert.are.equal(root .. "/notes/a.md", r.path, "separators are normalised")
      assert.are.equal("gopath", r.source)
      assert.are.equal("frag", r.fragment)
      assert.is_true(r.exists, "existence is decided here, not by gopath's flag")
    end)

    -- gopath's `exists` means "is a regular file" (measured: a directory
    -- comes back `exists = false`). Trusting it made a link to a folder look
    -- broken, so only the path is taken from gopath.
    it("does not inherit gopath's `regular files only` notion of existing", function()
      with_gopath(function()
        return { kind = "file", path = root .. "/notes", exists = false }
      end)
      assert.is_true(links.resolve("$LSPTEST_ENV_ROOT/notes").exists)
    end)

    it("does not believe `exists = true` for a path that is not there", function()
      with_gopath(function()
        return { kind = "file", path = root .. "/notes/gone.md", exists = true }
      end)
      assert.is_false(links.resolve("$LSPTEST_ENV_ROOT/notes/gone.md").exists)
    end)

    -- A missing module makes `require` search every loader on each call
    -- (~0.4 ms measured), and this runs per env-link diagnostic on every push.
    it("stops asking `require` for a gopath that is not installed", function()
      local attempts = 0
      package.loaded["gopath"] = nil
      package.preload["gopath"] = function()
        attempts = attempts + 1
        error("gopath is not installed")
      end
      for _ = 1, 5 do
        links.resolve("$LSPTEST_ENV_ROOT/notes/a.md")
      end
      assert.are.equal(1, attempts)
    end)

    it("still finds a gopath that was loaded after a failed attempt", function()
      package.loaded["gopath"] = nil
      package.preload["gopath"] = function()
        error("not yet")
      end
      assert.are.equal("builtin", links.resolve("$LSPTEST_ENV_ROOT/notes/a.md").source)

      package.loaded["gopath"] = {
        resolve_text = function()
          return { kind = "file", path = root .. "/notes/a.md" }
        end,
      }
      assert.are.equal("gopath", links.resolve("$LSPTEST_ENV_ROOT/notes/a.md").source)
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
      -- A `<...>` reference target holds spaces, as an inline one does; the
      -- definition answers from any column of the line, the title's included.
      { "[label]: <$R/my notes.md>", 12, "$R/my notes.md" },
      { "[label]: <$R/my notes.md>", 21, "$R/my notes.md" },
      { '[label]: <$R/my notes.md> "a title"', 12, "$R/my notes.md" },
      { '[label]: <$R/my notes.md> "a title"', 32, "$R/my notes.md" },
      -- ... and ends at the FIRST `>`: a `>` in the title is not part of it.
      { '[label]: <$R/x.md> "a > b"', 12, "$R/x.md" },
      -- An unterminated `<` is left as written (garbage in, no resolution out:
      -- `links.resolve("<$R/x.md")` is nil, so nothing is shown). This one is
      -- also green without the fix; it guards the fallback to the bare form.
      { "[label]: <$R/x.md", 12, "<$R/x.md" },
      -- A stray `]` before the link, a link still being typed, nested parens.
      { "x](y) [a]($R/x.md)", 15, "$R/x.md" },
      { "[a]($R/x.md", 5, "$R/x.md" },
      { "[a]($R/x(1).md)", 8, "$R/x(1).md" },
      -- Link text may hold balanced brackets, an image (the badge pattern) and
      -- escaped brackets; the target is found from anywhere in the link.
      { "[a [b] c]($R/x.md)", 15, "$R/x.md" },
      { "[a [b] c]($R/x.md)", 3, "$R/x.md" },
      { "[a [b [c] d] e]($R/x.md)", 20, "$R/x.md" },
      { "[![alt]($R/i.png)]($R/doc.md)", 27, "$R/doc.md" }, -- outer target
      { "[![alt]($R/i.png)]($R/doc.md)", 1, "$R/doc.md" }, -- outer `[`
      { "[![alt]($R/i.png)]($R/doc.md)", 18, "$R/doc.md" }, -- outer `]`
      { "[![alt]($R/i.png)]($R/doc.md)", 12, "$R/i.png" }, -- inner target
      { "[![alt]($R/i.png)]($R/doc.md)", 4, "$R/i.png" }, -- inner alt text
      { "[a\\]b]($R/x.md)", 12, "$R/x.md" },
      { "[a\\[b]($R/x.md)", 12, "$R/x.md" },
      { "x \\[not a link] [a]($R/x.md)", 24, "$R/x.md" },
      -- An unbalanced `[` before a link does not swallow it (CommonMark: the
      -- stray bracket is text), and neither does an extra `]`.
      { "[ [a]($R/x.md)", 10, "$R/x.md" },
      { "a] [b]($R/x.md)", 12, "$R/x.md" },
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

    -- A hover on a minified or generated line must not be able to stall the
    -- editor, whatever its length: the scan is linear, and this cap only keeps
    -- it short (see the timing cases below).
    it("gives up on a line too long to be hand-written Markdown", function()
      local line = "[a]($R/x.md)" .. (" "):rep(links.MAX_LINE_BYTES)
      assert.is_nil(links.target_at(line, 3))
      assert.are.equal("$R/x.md", links.target_at("[a]($R/x.md)", 3))
    end)

    it("finds the right link when the line has several", function()
      local line = "[one]($A/1.md) [two]($B/2.md) [three]($C/3.md)"
      assert.are.equal("$B/2.md", links.target_at(line, line:find("two", 1, true)))
    end)

    it("refuses a target longer than any real one instead of cutting it short", function()
      local at_cap = ("x"):rep(links.MAX_TARGET_BYTES)
      assert.are.equal(at_cap, links.target_at("[a](" .. at_cap .. ")", 3))
      -- One byte more, terminated or not: nil, never a truncated path.
      local over = at_cap .. "x"
      assert.is_nil(links.target_at("[a](" .. over .. ")", 3))
      assert.is_nil(links.target_at("[a](" .. over, 3))
      -- The same limit for a `<...>` target, which may hold spaces.
      assert.are.equal(at_cap, links.target_at("[a](<" .. at_cap .. ">)", 3))
      assert.is_nil(links.target_at("[a](<" .. over .. ">)", 3))
      -- ... and for a reference definition, which is a link too: bare and `<>`.
      assert.are.equal(at_cap, links.target_at("[l]: " .. at_cap, 3))
      assert.are.equal(at_cap, links.target_at("[l]: <" .. at_cap .. ">", 3))
      assert.is_nil(links.target_at("[l]: " .. over, 3))
      assert.is_nil(links.target_at("[l]: <" .. over .. ">", 3))
    end)

    -- A target at the limit is found from every byte of the link, the closing
    -- `>` and `)` of a `<...>` form included: the window that decides whether a
    -- link can reach the column must cover them.
    it("finds a target at the limit from its closing delimiters, too", function()
      local at_cap = ("x"):rep(links.MAX_TARGET_BYTES)
      local angled = "[a](<" .. at_cap .. ">)"
      local bare = "[a](" .. at_cap .. ")"
      for _, line in ipairs({ angled, bare }) do
        for _, col in ipairs({ 3, #line - 2, #line - 1, #line }) do
          assert.are.equal(at_cap, links.target_at(line, col), ("col %d of %d"):format(col, #line))
        end
      end
    end)

    -- What the linear scan replaced was quadratic, and each of these took
    -- about a second at the 20000-byte cap (measured: 1.2 s and 0.8 s) -- on a
    -- hover or a `gd`, on a line the user did not write. The bound is generous
    -- (the scan takes about a millisecond); it only has to tell the two apart.
    ---@param line string
    ---@param col integer
    ---@return number ms
    local function time_target_at(line, col)
      local t0 = uv.hrtime()
      links.target_at(line, col)
      return (uv.hrtime() - t0) / 1e6
    end

    it("stays fast on a line of nothing but `[`", function()
      local line = ("["):rep(links.MAX_LINE_BYTES)
      assert.is_true(time_target_at(line, #line) < 300)
      assert.is_true(time_target_at(line, 1) < 300)
    end)

    -- The bracket stack keeps every unclosed `[`; a hostile line makes it deep
    -- and makes every `](` close one of them. Each shape below is the worst
    -- case of one part: depth only, depth with a pending outer `[` that keeps
    -- the early exit from firing, and links nested inside each other.
    it("stays fast on deeply nested brackets", function()
      local n = links.MAX_LINE_BYTES
      local lines = {
        { "only opens", ("[a"):rep(n / 2) },
        { "opens, then closes", ("["):rep(n / 2) .. ("]("):rep(n / 4) },
        { "open outer, endless inner targets", "[" .. ("[a]("):rep((n - 1) / 4) },
        { "nested images", ("[!"):rep(n / 4) .. ("]($X/a.png)"):rep(n / 22) },
      }
      for _, case in ipairs(lines) do
        local line = case[2]:sub(1, n)
        for _, col in ipairs({ 1, math.floor(#line / 2), #line + 1 }) do
          -- 100 ms, tighter than the other cases: without the scan budget
          -- "opens, then closes" takes 270 ms at the middle column (measured),
          -- with it about 2 ms.
          local ms = time_target_at(line, col)
          assert.is_true(ms < 100, ("%s, col %d: %.1f ms"):format(case[1], col, ms))
        end
      end
    end)

    it("stays fast on links whose targets never end", function()
      local line = ("[a]($X/"):rep(math.floor(links.MAX_LINE_BYTES / 7))
      -- One past the end: no link holds that column, so nothing stops the scan
      -- early (at the last byte the first link, whose target runs to the end
      -- of the line, would answer at once and hide the cost).
      assert.is_true(time_target_at(line, #line + 1) < 300)
    end)

    -- Reference definitions are matched by two anchored patterns, one of which
    -- (`<[^>]*>`) runs to the end of the line when the `<` is never closed.
    -- Measured linear, 0.3 to 0.9 ms per line. Every line below is EXACTLY
    -- `MAX_LINE_BYTES` long (asserted): one byte more and the length guard
    -- answers before any pattern runs, which measures nothing -- an earlier
    -- version of this test had exactly that slip. What each line is for:
    --   * a run of blanks (with or without an unclosed `[a]: <` behind it): an
    --     unanchored `%s*` rescans it from every blank (about 1 s);
    --   * a chain of `]:<` after a `[`: a lazy or greedy label part in the
    --     `<...>` pattern (`.-`, `.*` instead of `[^%]]+`) backtracks over
    --     every `]:` (measured 170 to 340 ms depending on the chain). It is
    --     the one line whose mutant sits near the bound, so this test uses a
    --     tighter one (100 ms) than its siblings: the real code is about 300
    --     times below that. (The same change in the bare `%S+` pattern cannot
    --     be caught by timing: after the first `]:` a target always follows
    --     and it succeeds at once.)
    -- This pins the shape of the cost, it is not a proof: the 20000-byte cap
    -- keeps the input small enough that some quadratic patterns would pass.
    it("stays fast on reference definitions with an unclosed `<` or no target", function()
      local n = links.MAX_LINE_BYTES
      local lines = {
        { "unclosed `<`, long tail", "[a]: <" .. ("x"):rep(n - 6) },
        { "run of `<`", "[a]: " .. ("<"):rep(n - 5) },
        { "no target, blanks only", "[a]: " .. (" "):rep(n - 5) },
        { "blanks before `[a]: <`", (" "):rep(n - 6) .. "[a]: <" },
        {
          "`]:<` chain after `[`",
          "[" .. ("]:<"):rep(math.floor((n - 1) / 3)) .. ("x"):rep((n - 1) % 3),
        },
      }
      for _, case in ipairs(lines) do
        local name, line = case[1], case[2]
        assert.are.equal(n, #line, name)
        for _, col in ipairs({ 1, #line }) do
          local ms = time_target_at(line, col)
          assert.is_true(ms < 100, ("%s, col %d: %.1f ms"):format(name, col, ms))
        end
      end
    end)

    -- ERR-02: a caller that passes something else than a line and a column gets
    -- "no link", not an error out of the middle of a hover. (`target_at`'s
    -- annotations say `any` for that reason.) A reference definition ignores the
    -- column, so it too answers nil for a column that is not a number: the guard
    -- is about the call, not about which branch would have used the value.
    it("answers nil instead of raising on a line or column that is not one", function()
      assert.is_nil(links.target_at(nil, 1))
      assert.is_nil(links.target_at(42, 1))
      assert.is_nil(links.target_at("[a]($R/x.md)", nil))
      assert.is_nil(links.target_at("[a]($R/x.md)", "3"))
      assert.is_nil(links.target_at("[l]: $R/x.md", nil))
      assert.are.equal("$R/x.md", links.target_at("[l]: $R/x.md", 3))
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

    it("reads Markdown and text only", function()
      write_file(root .. "/h.lua", "# Title\n")
      assert.is_nil(links.heading_line(root .. "/h.lua", "title"))
    end)

    it("refuses a file above the size cap", function()
      local saved = links.MAX_READ_BYTES
      links.MAX_READ_BYTES = 8
      local got = links.heading_line(root .. "/h.md", "title")
      links.MAX_READ_BYTES = saved
      assert.is_nil(got)
    end)

    it("strips closing hashes and trailing whitespace from the title", function()
      write_file(root .. "/c.md", "## Closed ##   \n### Bare ###\n#### Plain\t\n# C#\n")
      assert.are.equal(0, links.heading_line(root .. "/c.md", "closed"))
      assert.are.equal(1, links.heading_line(root .. "/c.md", "bare"))
      assert.are.equal(2, links.heading_line(root .. "/c.md", "plain"))
      assert.are.equal(3, links.heading_line(root .. "/c.md", "c"))
    end)

    it("does not take `#tag` or a hash-only line for a heading", function()
      write_file(root .. "/n.md", "#tag\n#\n## \n")
      assert.is_nil(links.heading_line(root .. "/n.md", "tag"))
      -- `## ` is a heading with an empty title, which no fragment names.
      assert.is_nil(links.heading_line(root .. "/n.md", "x"))
    end)

    -- The pattern this replaced, `^#+%s+(.-)%s*#*%s*$`, is cubic on a long run
    -- of spaces inside the line: 0.5 s at 1000 bytes, 4.3 s at 2000, and the
    -- file is whatever the link points at (2 MB allowed).
    it("stays fast on a heading line full of spaces", function()
      local within_cap = "# a" .. (" "):rep(links.MAX_HEADING_BYTES - 10) .. "x"
      local over_cap = "# a" .. (" "):rep(links.MAX_HEADING_BYTES * 10) .. "x"
      write_file(root .. "/s.md", table.concat({ within_cap, over_cap, "## Real" }, "\n"))

      local t0 = uv.hrtime()
      local line = links.heading_line(root .. "/s.md", "real")
      local ms = (uv.hrtime() - t0) / 1e6

      assert.are.equal(2, line)
      assert.is_true(ms < 300, ("took %.0f ms"):format(ms))
    end)
  end)

  -- A hover quotes the top of the target. Following a link is the user's
  -- choice; quoting whatever it points at is not something a document should
  -- be able to cause: `[x]($HOME/.ssh/id_rsa)` must not put a private key into
  -- a hover.
  describe("preview", function()
    it("quotes a Markdown or text file", function()
      write_file(root .. "/p.md", "one\ntwo\nthree\n")
      assert.are.same({ "one", "two" }, links.preview(root .. "/p.md", 2))
      write_file(root .. "/p.txt", "plain\n")
      assert.are.same({ "plain" }, links.preview(root .. "/p.txt", 5))
    end)

    it("never quotes anything else", function()
      for _, name in ipairs({ "id_rsa", "secret.key", "credentials", "x.lua", "x.json", "x.env" }) do
        write_file(root .. "/" .. name, "PRIVATE\n")
        assert.is_nil(links.preview(root .. "/" .. name, 5), name)
      end
    end)

    it("refuses a file above the size cap", function()
      write_file(root .. "/big.md", "content\n")
      local saved = links.MAX_READ_BYTES
      links.MAX_READ_BYTES = 3
      local got = links.preview(root .. "/big.md", 5)
      links.MAX_READ_BYTES = saved
      assert.is_nil(got)
    end)

    it("truncates one very long line", function()
      write_file(root .. "/long.md", ("x"):rep(5000) .. "\nshort\n")
      local got = links.preview(root .. "/long.md", 5)
      assert.is_true(#got[1] < 300, #got[1])
      assert.are.equal("short", got[2])
    end)

    it("refuses a directory and a missing file", function()
      assert.is_nil(links.preview(root .. "/notes", 5))
      assert.is_nil(links.preview(root .. "/nope.md", 5))
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

    -- `vim.uri_to_bufnr` creates a listed buffer for a name Neovim does not
    -- have; a request for such a document must leave the buffer list alone.
    it("does not create a buffer for a document that is not open", function()
      local before = #vim.api.nvim_list_bufs()
      local res = server.definition({
        textDocument = { uri = vim.uri_from_fname(root .. "/never-opened.md") },
        position = { line = 0, character = 3 },
      })
      assert.is_nil(res)
      assert.are.equal(before, #vim.api.nvim_list_bufs())
    end)

    it("does not raise on a malformed request", function()
      assert.is_nil(server.definition(nil))
      assert.is_nil(server.definition({}))
      assert.is_nil(server.definition({ textDocument = { uri = "file:///x" } }))
    end)

    -- `nvim_buf_get_lines` takes -1 for the last line, so a negative line must
    -- be refused here rather than answered for the wrong line.
    it("refuses a position that is not a place in the document", function()
      local buf = doc(root .. "/doc.md", "[t]($LSPTEST_ENV_ROOT/target.md)\n")
      local uri = vim.uri_from_bufnr(buf)
      for _, position in ipairs({
        { line = -1, character = 3 },
        { line = 0, character = -1 },
        { line = "0", character = 3 },
        { line = 0 },
      }) do
        local res = server.definition({ textDocument = { uri = uri }, position = position })
        assert.is_nil(res, vim.inspect(position))
      end
      -- The same request with a real position does answer.
      assert.is_truthy(server.definition(params(buf, 0, 8)))
    end)
  end)

  describe("as an in-process server", function()
    -- A handler that raises must not surface as a Lua error in whichever
    -- feature asked -- every `K` and `gd` on that link -- but as the LSP error
    -- it is.
    it("answers a handler that raises with an LSP error", function()
      local real_definition, real_hover = server.definition, server.hover
      server.definition = function()
        error("boom")
      end
      server.hover = function()
        error("bang")
      end
      local srv = server.server({ on_exit = function() end })
      local got = {}
      for _, method in ipairs({ "textDocument/definition", "textDocument/hover" }) do
        srv.request(method, {}, function(err, res)
          got[method] = { err = err, res = res }
        end)
      end
      server.definition, server.hover = real_definition, real_hover

      for method, want in pairs({
        ["textDocument/definition"] = "boom",
        ["textDocument/hover"] = "bang",
      }) do
        assert.is_nil(got[method].res, method)
        assert.are.equal(-32603, got[method].err.code, method)
        assert.is_truthy(got[method].err.message:find(want, 1, true), method)
      end
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

    it("names a non-document target but never quotes it", function()
      write_file(root .. "/secret.key", "TOP-SECRET-LINE\n")
      local buf = doc(root .. "/doc.md", "[t]($LSPTEST_ENV_ROOT/secret.key)\n")
      local res = server.hover(params(buf, 0, 8))
      assert.is_truthy(res)
      assert.is_truthy(res.contents.value:find(root .. "/secret.key", 1, true))
      assert.is_nil(res.contents.value:find("TOP-SECRET-LINE", 1, true))
    end)

    -- The target is whatever the document says; a backtick in it must not end
    -- the code span and let the document format the rest of the hover.
    it("keeps a backtick in the target from breaking the code span", function()
      local buf = doc(root .. "/doc.md", "[t]($LSPTEST_ENV_ROOT/a`b.md)\n")
      local res = server.hover(params(buf, 0, 8))
      assert.is_truthy(res)
      local first = res.contents.value:match("^[^\n]*")
      local _, backticks = first:gsub("`", "")
      assert.are.equal(2, backticks, first)
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

    it("does not attach to an unnamed buffer", function()
      server.setup({ env_links = true })
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = "markdown"
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
