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

--- The fastest of `runs` calls of `fn`, in milliseconds. Scheduling noise (a CI
--- runner under load) only ever adds time, so the minimum is what the code
--- costs; the regressions the timing specs exist for are a hundred times that.
---@param fn fun()
---@param runs? integer
---@return number
local function best_ms(fn, runs)
  local best = math.huge
  for _ = 1, runs or 5 do
    local t0 = uv.hrtime()
    fn()
    best = math.min(best, (uv.hrtime() - t0) / 1e6)
  end
  return best
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
      return best_ms(function()
        links.target_at(line, col)
      end)
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

  -- A link target is whatever the document says, and the file a link points at
  -- is whatever happens to be there: what is resolved, stat-ed and read on the
  -- strength of one has to hold up against both.
  describe("resolve: untrusted input", function()
    it("refuses a target that decodes to a path with a control byte", function()
      assert.is_nil(links.resolve("$LSPTEST_ENV_ROOT/notes/a.md%00.txt"))
      assert.is_nil(links.resolve("$LSPTEST_ENV_ROOT/a%0Ab.md"))
      assert.is_nil(links.resolve("~/a%1Fb.md"))
    end)

    it("leaves `exists` unknown for a path it was not allowed to stat", function()
      local asked = {}
      local r = links.resolve("$LSPTEST_ENV_ROOT/notes/a.md", {
        stat = function(path)
          asked[#asked + 1] = path
          return nil
        end,
      })
      assert.is_nil(r.exists)
      assert.are.same({ root .. "/notes/a.md" }, asked)
    end)

    it("takes the answer of the stat it is given", function()
      local r = links.resolve("$LSPTEST_ENV_ROOT/nope.md", {
        stat = function()
          return true
        end,
      })
      assert.is_true(r.exists)
    end)
  end)

  -- gopath reads a wider grammar than a link target has. The built-in resolver
  -- is the reference, so where the two differ gopath is not asked, or not heard.
  describe("resolve: gopath's wider grammar", function()
    local asked

    before_each(function()
      asked = {}
      package.preload["gopath"] = nil
      package.loaded["gopath"] = {
        -- What gopath does with `report(1).md`: `(1)` is a position, the path
        -- is cut back to `report`.
        resolve_text = function(text)
          asked[#asked + 1] = text
          if text:find("(1)", 1, true) then
            return { kind = "file", path = root .. "/report", range = { line = 1 } }
          end
          return { kind = "file", path = root .. "/notes/a.md" }
        end,
      }
    end)

    it("does not ask for `${VAR}foo`, which is not a folder below VAR", function()
      assert.is_nil(links.resolve("${LSPTEST_ENV_ROOT}notes/a.md"))
      assert.are.same({}, asked)
    end)

    it("does not ask for a target with a long run of blanks", function()
      local r = links.resolve("$LSPTEST_ENV_ROOT/a" .. (" "):rep(8) .. "b.md")
      assert.are.same({}, asked)
      assert.are.equal("builtin", r.source)
    end)

    -- Measured against gopath's own parser: 4000 blanks inside a `<...>` target
    -- cost about 100 ms per link, and a document can hold two thousand of them.
    it("is not slowed down by a very long run of blanks", function()
      local ms = best_ms(function()
        links.resolve("$LSPTEST_ENV_ROOT/a" .. (" "):rep(4000) .. "b.md")
      end)
      assert.is_true(ms < 100, ("%.1f ms"):format(ms))
    end)

    it("takes the built-in answer when gopath read a position into the name", function()
      write_file(root .. "/report(1).md", "# R\n")
      local r = links.resolve("$LSPTEST_ENV_ROOT/report(1).md")
      assert.are.equal(root .. "/report(1).md", r.path)
      assert.is_true(r.exists)
      assert.are.equal("builtin", r.source)
    end)

    it("still uses gopath for an ordinary target", function()
      local r = links.resolve("$LSPTEST_ENV_ROOT/notes/a.md")
      assert.are.equal("gopath", r.source)
      assert.are.same({ "$LSPTEST_ENV_ROOT/notes/a.md" }, asked)
    end)
  end)

  describe("what is read on the strength of a link", function()
    it("never reads a path with a NUL, which the OS would cut short", function()
      write_file(root .. "/secret", "# Not a document\n")
      local path = root .. "/secret" .. string.char(0) .. ".md"
      assert.is_nil(links.heading_index(path))
      assert.is_nil(links.preview(path, 3))
    end)

    it("judges the file a symlink points at, not the link's own name", function()
      write_file(root .. "/key", "# looks like a heading\n")
      write_file(root .. "/real.md", "# Real\n")
      local evil = vim.uv.fs_symlink(root .. "/key", root .. "/evil.md")
      local fine = vim.uv.fs_symlink(root .. "/real.md", root .. "/fine.md")
      if not (evil and fine) then
        return pending("cannot create symlinks here")
      end
      assert.is_nil(links.heading_index(root .. "/evil.md"))
      assert.is_nil(links.preview(root .. "/evil.md", 3))
      -- ... and a link to a document is still one.
      assert.are.equal(0, links.heading_line(root .. "/fine.md", "real"))
      assert.are.same({ "# Real" }, links.preview(root .. "/fine.md", 3))
    end)

    it("does not raise on a NUL in a fragment or in a file", function()
      local nul = string.char(0)
      write_file(
        root .. "/n.md",
        "# A" .. nul .. "B\n" .. '<a name="x' .. nul .. 'y"></a>\n## Fine\n'
      )
      local idx = links.heading_index(root .. "/n.md")
      assert.is_table(idx)
      assert.are.equal(2, links.heading_lookup(idx, "fine"))
      assert.has_no.errors(function()
        links.heading_lookup(idx, "%00")
        links.heading_lookup(idx, "a%00b")
        links.heading_line(root .. "/n.md", "%00")
      end)
      assert.is_nil(links.heading_lookup(idx, "%00"))
    end)
  end)

  -- Diagnostics ask for the same few target files on every keystroke.
  describe("heading_index cache", function()
    local reads, orig_read

    before_each(function()
      reads = {}
      orig_read = require("lib.nvim.fs.read")
      package.loaded["lib.nvim.fs.read"] = function(path)
        reads[#reads + 1] = path
        return orig_read(path)
      end
    end)

    after_each(function()
      package.loaded["lib.nvim.fs.read"] = orig_read
    end)

    it("returns the same index, without reading again, while the file is unchanged", function()
      write_file(root .. "/c.md", "# One\n")
      local a = links.heading_index(root .. "/c.md")
      local b = links.heading_index(root .. "/c.md")
      assert.are.equal(a, b)
      assert.are.equal(1, #reads)
    end)

    it("builds a new index when the file changed", function()
      write_file(root .. "/c.md", "# One\n")
      local a = links.heading_index(root .. "/c.md")
      write_file(root .. "/c.md", "# One\n## Two, which is longer\n")
      local b = links.heading_index(root .. "/c.md")
      assert.are_not.equal(a, b)
      assert.are.equal(1, links.heading_lookup(b, "two-which-is-longer"))
      assert.are.equal(2, #reads)
    end)

    it("does not cache a file it cannot judge", function()
      write_file(root .. "/x.lua", "# One\n")
      assert.is_nil(links.heading_index(root .. "/x.lua"))
      assert.is_nil(links.heading_index(root .. "/gone.md"))
      assert.are.equal(0, #reads)
    end)

    it("keeps no more than INDEX_CACHE_SIZE indexes, the oldest go first", function()
      links.INDEX_CACHE_SIZE = 3
      for i = 1, 5 do
        write_file(("%s/f%d.md"):format(root, i), "# F" .. i .. "\n")
        links.heading_index(("%s/f%d.md"):format(root, i))
      end
      assert.are.equal(5, #reads)
      links.heading_index(root .. "/f5.md") -- the newest is still there
      assert.are.equal(5, #reads)
      links.heading_index(root .. "/f1.md") -- the oldest is not
      assert.are.equal(6, #reads)
    end)

    -- A changed file is indexed again; its old place in the eviction order must
    -- go, or the key is in the list twice and the entry just made is evicted.
    it("keeps a file that is edited over and over in the cache", function()
      local path = root .. "/busy.md"
      local last
      for i = 1, links.INDEX_CACHE_SIZE + 5 do
        write_file(path, ("# H\n"):rep(i))
        last = links.heading_index(path)
      end
      local before = #reads
      assert.are.equal(last, links.heading_index(path))
      assert.are.equal(before, #reads, "an unchanged file was read again")
    end)

    it("answers from the cache or not at all when asked to", function()
      write_file(root .. "/c.md", "# One\n")
      assert.is_nil(links.heading_index(root .. "/c.md", true))
      assert.are.equal(0, #reads)
      local built, cached = links.heading_index(root .. "/c.md")
      assert.is_nil(cached)
      local again, hit = links.heading_index(root .. "/c.md", true)
      assert.are.equal(built, again)
      assert.is_true(hit)
    end)

    it("forgets everything on clear_cache", function()
      write_file(root .. "/c.md", "# One\n")
      links.heading_index(root .. "/c.md")
      links.clear_cache()
      links.heading_index(root .. "/c.md")
      assert.are.equal(2, #reads)
    end)
  end)

  -- What a second review found in the link scanner, fence tracking and code
  -- span masking. Each case is one that was wrong before and is pinned here.
  describe("parser: links in links, escapes, blocks", function()
    ---@param line string
    ---@return string[]
    local function link_targets(line)
      local out = {}
      for _, l in ipairs(links.links(line)) do
        out[#out + 1] = l.target
      end
      return out
    end

    ---@param lines string[]
    ---@return string[]
    local function scanned(lines)
      local out = {}
      for _, l in ipairs(links.scan(lines)) do
        out[#out + 1] = l.target
      end
      return out
    end

    -- CommonMark: a link cannot contain a link. `[A [B](x) C](y)` is the link
    -- B between two pieces of text, and `(y)` is text.
    it("does not make a link out of the text around a link", function()
      local line = "[A [B]($R/b.md) C]($R/a.md)"
      assert.are.same({ "$R/b.md" }, link_targets(line))
      assert.is_nil(links.target_at(line, 2)) -- "A"
      assert.is_nil(links.target_at(line, 17)) -- " C"
      assert.is_nil(links.target_at(line, 22)) -- inside the outer `(...)`
      assert.are.equal("$R/b.md", links.target_at(line, 8))
      assert.are.equal("$R/b.md", links.target_at(line, 4)) -- "B"
    end)

    -- ... but an image's description may hold a link.
    it("keeps the link around an image that holds a link", function()
      local line = "![A [B]($R/b.md) C]($R/a.md)"
      assert.are.same({ "$R/b.md", "$R/a.md" }, link_targets(line))
      assert.are.equal("$R/a.md", links.target_at(line, 24))
    end)

    it("takes the badge pattern as before, with a link around it", function()
      local line = "[![alt]($R/i.png)]($R/doc.md) and [![b]($R/j.png)]($R/d2.md)"
      assert.are.same({ "$R/i.png", "$R/doc.md", "$R/j.png", "$R/d2.md" }, link_targets(line))
    end)

    it("does not take an escaped `!` for an image", function()
      local line = [[\![A [B]($R/b.md) C]($R/a.md)]]
      assert.are.same({ "$R/b.md" }, link_targets(line))
    end)

    -- A failed parse is charged what it cost: a byte for an empty target. Five
    -- of them used to exhaust the whole budget of a hover (the limit each).
    it("finds a link after any number of empty-target links", function()
      local line = ("[x]() "):rep(50) .. "[a]($R/real.md)"
      assert.are.same({ "$R/real.md" }, link_targets(line))
      assert.are.equal("$R/real.md", links.target_at(line, #line - 3))
      local blank = ("[x]( p) "):rep(50) .. "[a]($R/real.md)"
      assert.are.same({ "$R/real.md" }, link_targets(blank))
    end)

    -- A fence line ends a block only with nothing but blanks after the run, and
    -- a backtick fence's info string holds no backtick.
    it("ends a block at its own closing fence, not at one with an info string", function()
      assert.are.same(
        { "$R/real.md" },
        scanned({
          "```md",
          "[a]($R/e1.md)",
          "```js",
          "[b]($R/e2.md)",
          "```",
          "[c]($R/real.md)",
        })
      )
    end)

    it("does not open a block at a line that starts with an inline code span", function()
      assert.are.same({ "$R/real.md" }, scanned({ "```x``` is inline code", "[a]($R/real.md)" }))
      assert.are.same({ "$R/real.md" }, scanned({ "````x```` is inline", "[a]($R/real.md)" }))
      -- ... while a tilde fence may carry anything.
      assert.are.same({}, scanned({ "~~~ `x`", "[a]($R/example.md)", "~~~" }))
    end)

    it("follows a fence inside a block quote, and ends it with the quote", function()
      assert.are.same(
        { "$R/real.md" },
        scanned({ "> ```md", "> [a]($R/example.md)", "> ```", "[b]($R/real.md)" })
      )
      -- The quote ends without the block having been closed.
      assert.are.same(
        { "$R/real.md" },
        scanned({ "> ```md", "> [a]($R/in.md)", "", "[b]($R/real.md)" })
      )
      assert.are.same({}, scanned({ ">> ```md", ">> [a]($R/example.md)", ">> ```" }))
    end)

    it("follows a fence that opens behind a list marker", function()
      assert.are.same(
        { "$R/real.md" },
        scanned({ "- ```md", "  [a]($R/example.md)", "  ```", "[b]($R/real.md)" })
      )
      assert.are.same({}, scanned({ "1. ```md", "   [a]($R/example.md)", "   ```" }))
    end)

    -- A code span may wrap over a line break.
    it("finds a code span that wraps, whichever line holds its end", function()
      assert.are.same(
        { "$R/real.md" },
        scanned({ "text `a", "b` and [r]($R/real.md) then `[x]($R/ex.md)`" })
      )
      assert.are.same({}, scanned({ "see `look at", "[x]($R/ex.md)` now" }))
    end)

    it("does not let a lone backtick hide a link on the next line", function()
      assert.are.same({ "$R/real.md" }, scanned({ "a ` lone", "[a]($R/real.md)" }))
      assert.are.same(
        { "$R/real.md" },
        scanned({ "a ` lone", "", "`[x]($R/ex.md)` [a]($R/real.md)" })
      )
    end)

    it("does not pair backticks across a list item, a heading or a table row", function()
      assert.are.same(
        { "$R/real.md" },
        scanned({ "- one `x", "- two `[a]($R/ex.md)` [b]($R/real.md)" })
      )
      assert.are.same({ "$R/real.md" }, scanned({ "# h `x", "[a]($R/real.md) `y" }))
      assert.are.same({ "$R/real.md" }, scanned({ "| a `x |", "| [a]($R/real.md) `y |" }))
    end)

    it("stays fast on a long paragraph of unmatched backticks", function()
      local lines = {}
      for i = 1, 20000 do
        lines[i] = "x `y [a]($R/x" .. i .. ".md)"
      end
      local ms = best_ms(function()
        links.scan(lines)
      end, 3)
      assert.is_true(ms < 800, ("%.0f ms"):format(ms))
    end)

    local bs = string.char(92)
    local mask_cases = {
      -- A span may end in a backslash: it is not an escape inside a span.
      { "`a" .. bs .. "` `b`", (" "):rep(8) },
      { "`C:" .. bs .. "` x `y`", (" "):rep(5) .. " x " .. (" "):rep(3) },
      -- An escaped backslash does not escape the backtick after it.
      { "a" .. bs .. bs .. "`b` c", "a" .. bs .. bs .. (" "):rep(3) .. " c" },
      -- Three backslashes: the backtick is escaped, nothing opens.
      { "a" .. bs .. bs .. bs .. "`b` c", "a" .. bs .. bs .. bs .. "`b` c" },
      -- An escaped first backtick of a longer run: the rest of the run opens.
      { "a" .. bs .. "``b` c", "a" .. bs .. "`" .. (" "):rep(3) .. " c" },
    }
    for _, c in ipairs(mask_cases) do
      it(("masks %q"):format(c[1]), function()
        local got = links.mask_code_spans(c[1])
        assert.are.equal(#c[1], #got)
        assert.are.equal(c[2], got)
      end)
    end

    it("reports a link after a span that ends in a backslash", function()
      assert.are.same(
        { "$R/r.md" },
        scanned({ "`C:" .. bs .. "` and `[x]($R/e.md)` [y]($R/r.md)" })
      )
    end)

    it("does not see a heading after a closing fence with an info string", function()
      write_file(root .. "/f.md", "```md\n```js\n# nope\n```\n# yes\n")
      local idx = assert(links.heading_index(root .. "/f.md"))
      assert.is_nil(links.heading_lookup(idx, "nope"))
      assert.are.equal(4, links.heading_lookup(idx, "yes"))
    end)
  end)

  -- What a second review found in the anchors: every one is a heading GitHub
  -- gives an anchor that the index did not know (a link to it was reported as
  -- "non-existent heading"), or the other way round.
  describe("heading_index: the anchors GitHub gives", function()
    ---@param text string
    ---@return table<string, integer>
    local function index_of(text)
      write_file(root .. "/g.md", text)
      links.clear_cache()
      return assert(links.heading_index(root .. "/g.md"))
    end

    local function at(idx, fragment)
      return links.heading_lookup(idx, fragment)
    end

    it("indexes a setext heading, and counts it with the ATX ones", function()
      local idx = index_of("Title\n=====\n\nUsage\n-----\n\ntext\n\n## Usage\n")
      assert.are.equal(0, at(idx, "title"))
      assert.are.equal(3, at(idx, "usage"))
      assert.are.equal(8, at(idx, "usage-1"))
    end)

    it("does not take a thematic break, a list item or a quote for a setext title", function()
      local idx = index_of("- item\n---\n\n> quote\n---\n\n***\n\nreal\n---\n")
      assert.is_nil(at(idx, "item"))
      assert.is_nil(at(idx, "quote"))
      assert.are.equal(8, at(idx, "real"))
    end)

    it("takes the lines of a multi-line setext title together", function()
      local idx = index_of("first line\nsecond line\n======\n")
      assert.are.equal(0, at(idx, "first-line-second-line"))
    end)

    it("indexes a heading indented by up to three blanks, in a quote or in a list", function()
      local idx = index_of("   ## Indented\n> ## Quoted\n- ## Listed\n1. ## Numbered\n")
      assert.are.equal(0, at(idx, "indented"))
      assert.are.equal(1, at(idx, "quoted"))
      assert.are.equal(2, at(idx, "listed"))
      assert.are.equal(3, at(idx, "numbered"))
    end)

    it("does not take four blanks, seven hashes or a bare #tag for a heading", function()
      local idx = index_of("    ## Code\n####### Seven\n#tag\n")
      assert.is_nil(at(idx, "code"))
      assert.is_nil(at(idx, "seven"))
      assert.is_nil(at(idx, "tag"))
    end)

    it("keeps what is inside a code span as it is", function()
      local idx = index_of("## `Option<T>`\n## The `<div>` element\n## Syntax: `[text](url)`\n")
      assert.are.equal(0, at(idx, "optiont"))
      assert.are.equal(1, at(idx, "the-div-element"))
      assert.are.equal(2, at(idx, "syntax-texturl"))
    end)

    it("drops an image from the anchor, and knows the alt-text spelling too", function()
      local idx = index_of("## ![logo](a.png) Brand\n# Project [![CI](x.svg)](https://ci) Status\n")
      assert.are.equal(0, at(idx, "-brand"))
      assert.are.equal(0, at(idx, "logo-brand"))
      assert.are.equal(1, at(idx, "project--status"))
    end)

    it("takes the emphasis out of a title, wherever it is", function()
      local idx = index_of("## The _foo_ command\n## __init__ method\n## snake_case here\n")
      assert.are.equal(0, at(idx, "the-foo-command"))
      assert.are.equal(1, at(idx, "init-method"))
      assert.are.equal(2, at(idx, "snake_case-here"))
      assert.is_nil(at(idx, "snakecase-here"))
    end)

    it("numbers a repeated heading on the anchor GitHub ends up with", function()
      local idx = index_of("## 🚀 Fixes\n## 🚀 Fixes\n## _foo_\n## foo\n")
      assert.are.equal(0, at(idx, "-fixes"))
      assert.are.equal(1, at(idx, "-fixes-1"))
      assert.are.equal(2, at(idx, "foo"))
      assert.are.equal(3, at(idx, "foo-1"))
    end)

    it("decodes character references before it makes the anchor", function()
      local idx = index_of(
        "## Q&amp;A\n## Overview &amp; Setup\n## &#169; Num\n## &#x41;lpha\n## &bogus; x\n"
      )
      assert.are.equal(0, at(idx, "qa"))
      assert.are.equal(1, at(idx, "overview--setup"))
      assert.are.equal(2, at(idx, "-num"))
      assert.are.equal(3, at(idx, "alpha"))
      assert.are.equal(4, at(idx, "bogus-x"))
    end)

    it("accepts both the id and the GitHub spelling of a heading with {#id}", function()
      local idx = index_of("## Title {#custom-id}\n")
      assert.are.equal(0, at(idx, "title"))
      assert.are.equal(0, at(idx, "custom-id"))
      assert.are.equal(0, at(idx, "title-custom-id"))
    end)

    it("sees a heading on the first line of a file with a byte order mark", function()
      write_file(root .. "/bom.md", "\239\187\191# Title\n## Second\n")
      links.clear_cache()
      local idx = assert(links.heading_index(root .. "/bom.md"))
      assert.are.equal(0, at(idx, "title"))
      assert.are.equal(1, at(idx, "second"))
    end)

    it("does not take a comment in a YAML front matter for a heading", function()
      local idx = index_of("---\n# a comment\ntitle: x\n---\n# Real\n")
      assert.is_nil(at(idx, "a-comment"))
      assert.are.equal(4, at(idx, "real"))
      -- Not closed: the dashes were a thematic break.
      local open = index_of("---\n# Still a heading\n")
      assert.are.equal(1, at(open, "still-a-heading"))
    end)

    it("drops CJK and full-width punctuation like any other punctuation", function()
      local idx = index_of("## 概要：使い方\n## Foo（bar）\n")
      assert.are.equal(0, at(idx, "概要使い方"))
      assert.are.equal(1, at(idx, "foobar"))
    end)

    -- JavaScript's toLowerCase, which GitHub's slugger uses, is not Vim's.
    it("folds the lowercase of a dotted capital I and of a final sigma", function()
      local idx = index_of("## \196\176stanbul\n## \206\159\206\148\206\159\206\163\n")
      assert.are.equal(0, at(idx, "istanbul"))
      assert.are.equal(0, at(idx, "i\204\135stanbul"))
      assert.are.equal(1, at(idx, "\206\191\206\180\206\191\207\131")) -- medial sigma
      assert.are.equal(1, at(idx, "\206\191\206\180\206\191\207\130")) -- final sigma
    end)
  end)

  -- Third round: what the review of the fixes found.
  describe("parser: after the review of the fixes", function()
    ---@param lines string[]
    ---@return string[]
    local function scanned(lines)
      local out = {}
      for _, l in ipairs(links.scan(lines)) do
        out[#out + 1] = l.target
      end
      return out
    end

    ---@param line string
    ---@return string[]
    local function link_targets(line)
      local out = {}
      for _, l in ipairs(links.links(line)) do
        out[#out + 1] = l.target
      end
      return out
    end

    -- A fence line closes a block only at the block's own quote depth.
    it("does not close a block at a `>` line inside it", function()
      assert.are.same(
        { "$R/real.md" },
        scanned({ "```md", "> ```js", "> [x]($R/e.md)", "> ```", "```", "[b]($R/real.md)" })
      )
      assert.are.same(
        { "$R/real.md" },
        scanned({ "> ```md", ">> ```", "> [b]($R/x.md)", "> ```", "[b]($R/real.md)" })
      )
    end)

    it("does not take a `>` fence line inside a block for its end in heading_index", function()
      write_file(root .. "/q.md", "```md\n> ```js\n> x\n> ```\n```\n# Real\n")
      local idx = assert(links.heading_index(root .. "/q.md"))
      assert.are.equal(5, links.heading_lookup(idx, "real"))
    end)

    -- ... and a block opened in a list item ends with the item.
    it("ends a block opened behind a list marker when the item ends", function()
      -- never closed: the next list item and a column-0 line end it
      assert.are.same(
        { "$R/a.md", "$R/b.md" },
        scanned({ "- ```md", "  [x]($R/e.md)", "- next", "[a]($R/a.md)", "", "[b]($R/b.md)" })
      )
      assert.are.same({ "$R/real.md" }, scanned({ "1. ```", "   [x]($R/e.md)", "[y]($R/real.md)" }))
      -- a blank line and the item's own indentation keep it
      assert.are.same(
        { "$R/real.md" },
        scanned({ "- ```md", "", "  [x]($R/e.md)", "  ```", "[y]($R/real.md)" })
      )
      -- a tab-indented item
      assert.are.same(
        { "$R/real.md" },
        scanned({
          "-" .. string.char(9) .. "```md",
          string.char(9) .. "[x]($R/e.md)",
          "[y]($R/real.md)",
        })
      )
    end)

    it("ends such a block in heading_index, too", function()
      write_file(root .. "/l.md", "- ```md\n  # nope\n- next\n# Yes\n")
      local idx = assert(links.heading_index(root .. "/l.md"))
      assert.is_nil(links.heading_lookup(idx, "nope"))
      assert.are.equal(3, links.heading_lookup(idx, "yes"))
    end)

    -- `[x](a b)` and `[x](foo` are answered, leniently, but they are text to
    -- CommonMark: they must not take the enclosing link with them.
    it("does not let a malformed inner link kill the link around it", function()
      assert.are.same({ "a", "$R/real.md" }, link_targets("[see [x](a b) here]($R/real.md)"))
      -- (`foo` is the lenient answer for a link still being typed.)
      assert.are.same({ "foo", "$R/real.md" }, link_targets("[a [x](foo b]($R/real.md)"))
      assert.are.equal("$R/real.md", links.target_at("[see [x](a b) here]($R/real.md)", 5))
    end)

    it("lets a real inner link kill it, `[x]()` and a titled one included", function()
      assert.are.same({}, link_targets("[a [x]() b]($R/outer.md)"))
      assert.are.same({ "$R/in.md" }, link_targets([=[[a [x]($R/in.md "t") b]($R/outer.md)]=]))
    end)

    -- `#tag` is no heading and `2.` no list that interrupts a paragraph: neither
    -- may cut a code span's paragraph.
    it("does not end a paragraph at a `#tag` line or a `2.` line", function()
      assert.are.same({}, scanned({ "the syntax is `[x]($R/ex.md)", "#tag more` text" }))
      assert.are.same({}, scanned({ "the syntax is `[x]($R/ex.md)", "2. more` text" }))
      -- while a heading and a first list item do
      assert.are.same({ "$R/real.md" }, scanned({ "a ` lone", "# heading", "[b]($R/real.md) `x`" }))
    end)
  end)

  describe("safe by default: network paths and quoting", function()
    local function counting_stat()
      local stats = {}
      local real_stat = vim.uv.fs_stat
      vim.uv.fs_stat = function(path, ...)
        if tostring(path):find("192.0.2.1", 1, true) then
          stats[#stats + 1] = path
        end
        return real_stat(path, ...)
      end
      return stats, function()
        vim.uv.fs_stat = real_stat
      end
    end

    it("does not stat a network path, whoever asks", function()
      vim.env.LSPTEST_UNC = "//192.0.2.1/share"
      local was_windows = require("lsp.core.env_links").windows
      require("lsp.core.env_links").windows = true
      local stats, restore = counting_stat()
      local resolved = links.resolve("$LSPTEST_UNC/a.md")
      local verdict = links.verdict("Link to non-existent document '$LSPTEST_UNC/a.md'")
      restore()
      vim.env.LSPTEST_UNC = nil
      require("lsp.core.env_links").windows = was_windows
      assert.is_nil(resolved.exists)
      assert.is_nil(verdict, "not looked at is no verdict")
      assert.are.same({}, stats)
    end)

    it("shows an absolute path, quoted, and only that", function()
      assert.are.equal(root .. "/a.md", links.displayable_path(root .. "/a.md"))
      assert.is_nil(links.displayable_path("sk-secret-token/a.md"))
      assert.are.equal("", links.looked_up_at("sk-secret-token/a.md"))
      assert.are.equal(
        (root .. "/y?md"),
        links.displayable_path(root .. "/y" .. string.char(27) .. "md")
      )
    end)
  end)

  -- What the review of the anchor rework found.
  describe("heading_index: after the review of the rework", function()
    ---@param text string
    ---@return table<string, integer>
    local function index_of(text)
      write_file(root .. "/g2.md", text)
      links.clear_cache()
      return assert(links.heading_index(root .. "/g2.md"))
    end

    local function at(idx, fragment)
      return links.heading_lookup(idx, fragment)
    end

    it("keeps an underscore inside a word, drops those of emphasis, in linear time", function()
      local idx = index_of("## snake__case here\n## a _b_ c\n## x_ y\n")
      assert.are.equal(0, at(idx, "snake__case-here"))
      assert.are.equal(1, at(idx, "a-b-c"))
      assert.are.equal(2, at(idx, "x-y"))
      assert.are.equal(2, at(idx, "x_-y")) -- the lenient spelling stays known
      for _, shape in ipairs({
        ("_"):rep(1990),
        "a" .. ("_"):rep(1990) .. "b",
        ("a_"):rep(995),
        ("_a"):rep(995),
      }) do
        local line = "## " .. shape
        write_file(root .. "/u.md", (line .. "\n"):rep(100))
        local ms = best_ms(function()
          links.clear_cache()
          links.heading_index(root .. "/u.md")
        end, 3)
        assert.is_true(ms < 400, ("%.0f ms on %q"):format(ms, shape:sub(1, 6)))
      end
    end)

    it("leaves a character reference in a code span as it is", function()
      local idx =
        index_of("## Entities: `&lt;` and `&gt;`\n## `a &amp; b`\n## `&amp;` &amp; x\n## Q&amp;A\n")
      assert.are.equal(0, at(idx, "entities-lt-and-gt"))
      assert.are.equal(1, at(idx, "a-amp-b"))
      assert.are.equal(2, at(idx, "amp--x"))
      assert.are.equal(3, at(idx, "qa"))
    end)

    it("knows more of the named references", function()
      local idx =
        index_of("## Setup &mdash; Linux\n## Product&trade; Overview\n## &Uuml;bersicht\n")
      assert.are.equal(0, at(idx, "setup--linux"))
      assert.are.equal(1, at(idx, "product-overview"))
      assert.are.equal(2, at(idx, "übersicht"))
    end)

    it("keeps the hyphen GitHub keeps for a trailing image, badge or tag", function()
      local idx =
        index_of('## Title <img src="x">\n# Proj ![build](b.svg)\n## Title ![b](x.svg)\n## Plain\n')
      assert.are.equal(0, at(idx, "title-"))
      assert.are.equal(1, at(idx, "proj-"))
      assert.are.equal(0, at(idx, "title")) -- the trimmed spelling is known too
      assert.is_nil(at(idx, "plain-"))
    end)

    it("trims the lines of a setext title", function()
      assert.are.equal(0, at(index_of("   Title\n===\n"), "title"))
      assert.are.equal(
        0,
        at(index_of("first line\n   second line  \n======\n"), "first-line-second-line")
      )
      assert.are.equal(2, at(index_of("- item\n\n  Para\n  ---\n"), "para"))
    end)

    -- A lenient spelling is known, but it never takes the anchor of a heading
    -- whose exact anchor it is.
    it("does not let a lenient spelling take a later heading's anchor", function()
      local idx = index_of("## ![logo](a.png) Brand\n## logo Brand\n## logo Brand\n")
      assert.are.equal(0, at(idx, "-brand"))
      assert.are.equal(1, at(idx, "logo-brand"))
      assert.are.equal(2, at(idx, "logo-brand-1"))
      local emphasis = index_of("## _foo_ bar\n## foo bar\n")
      assert.are.equal(0, at(emphasis, "foo-bar"))
      assert.are.equal(1, at(emphasis, "foo-bar-1"))
    end)

    it("takes nested brackets, autolinks and parentheses in a destination", function()
      local idx = index_of(
        "## [a [b] c](u) Z\n## <https://a.b/c> text\n## [Foo](https://x/Foo_(bar)) y\n## <me@a.b> mail\n## [Bar](x_(a)b) z\n"
      )
      assert.are.equal(0, at(idx, "a-b-c-z"))
      assert.are.equal(1, at(idx, "httpsabc-text"))
      assert.are.equal(2, at(idx, "foo-y"))
      assert.are.equal(3, at(idx, "mea.b-mail"))
      assert.are.equal(4, at(idx, "bar-z")) -- not "barb-z": the destination balances its parentheses
    end)

    it("does not let a fence line in a front matter hide the headings after it", function()
      assert.are.equal(4, at(index_of("---\nsnippet: |\n  ```sh\n---\n# After\n"), "after"))
      assert.are.equal(4, at(index_of("---\nsnippet: |\n  ~~~\n---\n# After\n"), "after"))
    end)
  end)

  -- Fourth round: what the review of the second fixes found.
  describe("scanner and paths: after the third review", function()
    ---@param lines string[]
    ---@return string[]
    local function scanned(lines)
      local out = {}
      for _, l in ipairs(links.scan(lines)) do
        out[#out + 1] = l.target
      end
      return out
    end

    -- The quote prefix used to swallow the indentation of a list item's
    -- continuation lines, so the item "ended" at its first content line.
    it("keeps a list-item fence inside a block quote open until the item ends", function()
      assert.are.same(
        { "$A/after.md", "$A/out.md" },
        scanned({
          "> - ```md",
          ">   [in]($A/in.md)",
          ">   ```",
          "> [after]($A/after.md)",
          "",
          "[out]($A/out.md)",
        })
      )
    end)

    it("ends a list-item fence in a block quote at the item's dedent", function()
      assert.are.same(
        { "$A/next.md" },
        scanned({ "> - ```md", ">   [in]($A/in.md)", "> - next", "> [x]($A/next.md)" })
      )
    end)

    it("keeps the headings after a list-item fence in a block quote", function()
      write_file(root .. "/ql.md", "> - ```md\n>   # nope\n>   ```\n> # Inside quote\n# Real\n")
      links.clear_cache()
      local idx = assert(links.heading_index(root .. "/ql.md"))
      assert.is_nil(links.heading_lookup(idx, "nope"))
      assert.are.equal(3, links.heading_lookup(idx, "inside-quote"))
      assert.are.equal(4, links.heading_lookup(idx, "real"))
    end)

    -- Another number does not interrupt a paragraph, but after a numbered item it
    -- is the next item of the list.
    it("splits the items of a numbered list, and still not a plain paragraph", function()
      assert.are.same({ "$A/x.md" }, scanned({ "1. press `", "2. [x]($A/x.md) and `y` ok" }))
      assert.are.same({}, scanned({ "1. a `", "2. use `[x]($A/x.md)` here" }))
      assert.are.same({}, scanned({ "the syntax is `[x]($A/ex.md)", "2. more` text" }))
    end)

    it("stats a double-slash path where that is an ordinary local path", function()
      vim.env.LSPTEST_DBL = "//192.0.2.1/share"
      local was_windows = links.windows
      links.windows = false
      local stats = {}
      local real_stat = vim.uv.fs_stat
      vim.uv.fs_stat = function(path)
        if tostring(path):find("192.0.2.1", 1, true) then
          stats[#stats + 1] = path
        end
        return nil
      end
      local resolved = links.resolve("$LSPTEST_DBL/a.md")
      vim.uv.fs_stat = real_stat
      links.windows = was_windows
      vim.env.LSPTEST_DBL = nil
      assert.is_false(resolved.exists)
      assert.are.equal(1, #stats)
    end)

    it("takes a double slash for a network path on Windows only", function()
      assert.is_true(links.is_network_path("//h/s/a.md", true))
      assert.is_false(links.is_network_path("//h/s/a.md", false))
      assert.is_true(
        links.is_network_path(string.rep(string.char(92), 2) .. "h" .. string.char(92) .. "s", true)
      )
      assert.is_false(links.is_network_path(string.rep(string.char(92), 2) .. "h", false))
      assert.is_false(links.is_network_path("C:/x", true))
      assert.is_false(links.is_network_path("///x", true))
    end)

    it("shows a path only when its directory exists", function()
      assert.are.equal(root .. "/gone.md", links.displayable_path(root .. "/gone.md"))
      assert.is_nil(links.displayable_path(root .. "/no/such/dir/gone.md"))
      -- a value that starts with a slash is still no path
      assert.is_nil(links.displayable_path("/9f2Kx+Qm7vT3rLw8aZpYc0Hn5bUeDg1J/a.md"))
      assert.are.equal("", links.looked_up_at("/9f2Kx+Qm7vT3rLw8aZpYc0Hn5bUeDg1J/a.md"))
      assert.is_truthy(links.looked_up_at(root .. "/gone.md"):find(root, 1, true))
    end)

    it("takes a tag name to end at a blank, a slash or a `>`", function()
      write_file(
        root .. "/t.md",
        "## Result<T, E> type\n## K<K,V> map\n## Use <kbd>Ctrl</kbd> keys\n"
      )
      links.clear_cache()
      local idx = assert(links.heading_index(root .. "/t.md"))
      assert.are.equal(0, links.heading_lookup(idx, "resultt-e-type"))
      assert.are.equal(1, links.heading_lookup(idx, "kkv-map"))
      assert.are.equal(2, links.heading_lookup(idx, "use-ctrl-keys"))
    end)

    it("renders an HTML comment in a heading away", function()
      write_file(root .. "/c.md", "## Title <!-- omit in toc -->\n## Other <!-- never closed\n")
      links.clear_cache()
      local idx = assert(links.heading_index(root .. "/c.md"))
      assert.are.equal(0, links.heading_lookup(idx, "title-"))
      assert.are.equal(0, links.heading_lookup(idx, "title"))
    end)
  end)

  describe("after the fourth review", function()
    ---@param lines string[]
    ---@return string[]
    local function scanned(lines)
      local out = {}
      for _, l in ipairs(links.scan(lines)) do
        out[#out + 1] = l.target
      end
      return out
    end

    -- `/` and `C:/` always exist: a value that is nothing but a secret that starts
    -- with a slash used to pass the "its directory exists" rule.
    it("does not show a path that sits directly below a root", function()
      assert.is_nil(links.displayable_path("/9f2Kx+Qm7vT3rLw8aZpYc0Hn5bUeDg1J"))
      assert.is_nil(links.displayable_path("//abc"))
      assert.is_nil(links.displayable_path("C:/secret"))
      assert.is_nil(links.displayable_path("C:/"))
      assert.are.equal(root .. "/ok.md", links.displayable_path(root .. "/ok.md"))
    end)

    -- A quote that starts before the item's content is a quote of its own.
    it("ends a list-item fence at a quote that starts before the item's content", function()
      assert.are.same({ "$A/q.md" }, scanned({ "- ```", "  code", ">   [q]($A/q.md)" }))
      assert.are.same({ "$A/d.md" }, scanned({ "> - ```md", "> >   [d]($A/d.md)" }))
      -- a `>` at the item's content column is code
      assert.are.same({}, scanned({ "- ```", "  > [c]($A/c.md)", "  ```" }))
    end)

    it("does not index a setext heading that starts on a list-item line", function()
      write_file(root .. "/sl.md", "- Title\n  ===\n\nPlain\n=====\n")
      links.clear_cache()
      local idx = assert(links.heading_index(root .. "/sl.md"))
      assert.is_nil(links.heading_lookup(idx, "title"))
      assert.are.equal(3, links.heading_lookup(idx, "plain"))
    end)
  end)

  -- Completion of the path of a link whose target starts with a variable.
  describe("typing_at and fenced_at", function()
    ---@param line string
    ---@param col? integer # Default: the end of the line.
    local function typing(line, col)
      return links.typing_at(line, col or #line + 1)
    end

    it("finds the target typed so far in an inline link, an image and a definition", function()
      assert.are.same({ text = "$R/x", start = 5, angled = false }, typing("[a]($R/x"))
      assert.are.same({ text = "$R/p", start = 6, angled = false }, typing("![i]($R/p"))
      assert.are.same({ text = "$R/x", start = 10, angled = false }, typing("[label]: $R/x"))
      assert.are.same({ text = "", start = 5, angled = false }, typing("[a]("))
      -- the cursor in an earlier link of the line
      assert.are.same({ text = "$R/", start = 5, angled = false }, typing("[a]($R/x) [b](y)", 8))
    end)

    it("takes a `<...>` target with blanks, and balanced parentheses", function()
      assert.are.same({ text = "$R/my n", start = 6, angled = true }, typing("[a](<$R/my n"))
      assert.are.same({ text = "$R/f(1)/x", start = 5, angled = false }, typing("[a]($R/f(1)/x"))
    end)

    it("answers nil outside a target, or when it is closed", function()
      assert.is_nil(typing("plain text"))
      assert.is_nil(typing("[a]($R/x) more"))
      assert.is_nil(typing("[a]($R/x)"))
      assert.is_nil(typing("[a](<$R/x>"))
      assert.is_nil(typing("[a]($R/x y"))
      assert.is_nil(links.typing_at(nil, 1))
      assert.is_nil(links.typing_at("[a]($R/x", "3"))
      assert.is_nil(links.typing_at(("[a]($R/x"):rep(links.MAX_LINE_BYTES), 5))
    end)

    it("knows a fence, a fence line and a front matter", function()
      local lines = { "---", "title: x", "---", "text", "```", "code", "```", "text" }
      for lnum, want in ipairs({ true, true, true, false, true, true, true, false }) do
        assert.are.equal(want, links.fenced_at(lines, lnum), "line " .. lnum)
      end
      -- not closed: no front matter
      assert.is_false(links.fenced_at({ "---", "text" }, 2))
    end)
  end)

  -- `target_at` answers for one column; `links` for the whole line, with the
  -- span of each target (what a diagnostic underlines).
  describe("links", function()
    ---@param line string
    ---@return string[]
    local function targets(line)
      local out = {}
      for _, l in ipairs(links.links(line)) do
        out[#out + 1] = l.target
      end
      return out
    end

    it("lists every link on a line, left to right", function()
      assert.are.same(
        { "$A/1.md", "./2.md", "$C/3.png" },
        targets("[one]($A/1.md) text [two](./2.md) ![three]($C/3.png)")
      )
    end)

    it("gives the span of each target, `<>` and `)` not included", function()
      local line = "see [a]($R/x.md#f) and [b](<$R/my f.md>)"
      local got = links.links(line)
      assert.are.equal(2, #got)
      assert.are.equal("$R/x.md#f", line:sub(got[1].first, got[1].last))
      assert.are.equal("$R/my f.md", line:sub(got[2].first, got[2].last))
      assert.are.equal("$R/my f.md", got[2].target)
    end)

    it("finds the links around brackets in the text, the badge pattern included", function()
      assert.are.same({ "$R/i.png", "$R/doc.md" }, targets("[![alt]($R/i.png)]($R/doc.md)"))
      assert.are.same({ "$R/x.md" }, targets("[a [b] c]($R/x.md)"))
      assert.are.same({ "$R/x.md" }, targets("[a" .. "\\" .. "]b]($R/x.md)"))
    end)

    it("lists a reference definition, with its span", function()
      local line = "[lbl]: <$R/my notes.md> 'title'"
      local got = links.links(line)
      assert.are.equal(1, #got)
      assert.are.equal("$R/my notes.md", got[1].target)
      assert.are.equal("$R/my notes.md", line:sub(got[1].first, got[1].last))
      local bare = links.links("[lbl]: $R/x.md")
      assert.are.equal("$R/x.md", ("[lbl]: $R/x.md"):sub(bare[1].first, bare[1].last))
    end)

    it("answers an empty list for a line that is not a string, or too long", function()
      assert.are.same({}, links.links(nil))
      assert.are.same({}, links.links(42))
      assert.are.same({}, links.links("[a]($R/x.md)" .. (" "):rep(links.MAX_LINE_BYTES)))
    end)

    it("agrees with target_at on where each target is", function()
      local line = "x [a]($R/one.md) y [![i]($R/two.png)]($R/three.md) z"
      for _, l in ipairs(links.links(line)) do
        assert.are.equal(l.target, links.target_at(line, l.first), l.target)
        assert.are.equal(l.target, links.target_at(line, l.last), l.target)
      end
    end)

    it("stays fast on a line of hostile brackets", function()
      local n = links.MAX_LINE_BYTES
      local lines = {
        ("["):rep(n),
        ("[a"):rep(n / 2),
        ("[a](<"):rep(n / 5),
        "[" .. ("[a]("):rep((n - 1) / 4),
        ("[" .. ("]("):rep(2)):rep(n / 5),
      }
      for _, line in ipairs(lines) do
        local ms = best_ms(function()
          links.links(line)
        end)
        assert.is_true(ms < 100, ("%.1f ms on %q"):format(ms, line:sub(1, 12)))
      end
    end)
  end)

  describe("mask_code_spans", function()
    local cases = {
      { "no code here", "no code here" },
      { "a `b` c", "a     c" },
      { "a ``b`c`` d", "a" .. (" "):rep(9) .. "d" },
      { "`a` and `b`", "   " .. " and " .. "   " },
      -- No closing run of the same length: the backticks stay text.
      { "a `b c", "a `b c" },
      { "a `b`` c", "a `b`` c" },
      -- An escaped backtick opens nothing.
      { "a \\`b` c", "a \\`b` c" },
    }
    for _, c in ipairs(cases) do
      it(("%q"):format(c[1]), function()
        local got = links.mask_code_spans(c[1])
        assert.are.equal(#c[1], #got)
        assert.are.equal(c[2], got)
      end)
    end

    it("hides a link inside a span but not one beside it", function()
      local masked = links.mask_code_spans("`[a]($R/x.md)` [b]($R/y.md)")
      assert.are.same(
        { "$R/y.md" },
        vim.tbl_map(function(l)
          return l.target
        end, links.links(masked))
      )
    end)

    it("stays fast on backticks of a hundred different lengths", function()
      local parts = {}
      for k = 1, 120 do
        parts[#parts + 1] = ("`"):rep(k) .. "x"
      end
      local line = table.concat(parts):rep(3):sub(1, links.MAX_LINE_BYTES)
      local ms = best_ms(function()
        links.mask_code_spans(line)
      end)
      assert.is_true(ms < 100, ("%.1f ms"):format(ms))
    end)
  end)

  describe("scan", function()
    ---@param lines string[]
    ---@return string[]
    local function targets(lines)
      local out = {}
      for _, l in ipairs(links.scan(lines)) do
        out[#out + 1] = l.target
      end
      return out
    end

    it("finds env and home links, with line and span, and skips the rest", function()
      local lines = { "# t", "[a]($R/x.md) [b](./y.md) [c](~/z.md) [d](https://e.org)" }
      local got = links.scan(lines)
      assert.are.equal(2, #got)
      assert.are.equal(1, got[1].lnum)
      assert.are.equal("$R/x.md", lines[2]:sub(got[1].first, got[1].last))
      assert.are.equal("~/z.md", lines[2]:sub(got[2].first, got[2].last))
    end)

    it("does not take a link in a fenced code block for one", function()
      assert.are.same(
        { "$R/real.md" },
        targets({
          "```md",
          "[x]($R/example.md)",
          "```",
          "[y]($R/real.md)",
          "~~~",
          "[z]($R/e2.md)",
          "~~~",
        })
      )
    end)

    -- A block ends at a fence of its own kind and at least its own length.
    it("keeps a block open past a fence of another kind or a shorter one", function()
      assert.are.same(
        { "$R/real.md" },
        targets({
          "~~~md",
          "```",
          "[a]($R/in-tilde-block.md)",
          "```",
          "~~~",
          "````",
          "```",
          "[b]($R/in-long-block.md)",
          "```",
          "````",
          "[c]($R/real.md)",
        })
      )
    end)

    it("does not take a link in a code span for one", function()
      assert.are.same(
        { "$R/real.md" },
        targets({ "write `[x]($R/example.md)` like `this` or [y]($R/real.md)" })
      )
    end)

    it("skips a YAML front matter, and only a closed one", function()
      assert.are.same(
        { "$R/body.md" },
        targets({ "---", "link: [a]($R/meta.md)", "---", "[b]($R/body.md)" })
      )
      -- No closing line: `---` is a thematic break, the rest is the document.
      assert.are.same({ "$R/x.md" }, targets({ "---", "[a]($R/x.md)" }))
      -- Not on the first line: not a front matter.
      assert.are.same({ "$R/x.md" }, targets({ "text", "---", "[a]($R/x.md)", "---" }))
    end)

    it("finds a reference definition", function()
      assert.are.same({ "$R/ref.md" }, targets({ "[lbl]: $R/ref.md" }))
    end)

    it("stops at the most links one buffer reports", function()
      local lines = {}
      for i = 1, links.MAX_SCANNED_LINKS + 50 do
        lines[i] = "[a]($R/x.md)"
      end
      assert.are.equal(links.MAX_SCANNED_LINKS, #links.scan(lines))
    end)

    it("answers an empty list for an empty buffer", function()
      assert.are.same({}, links.scan({}))
      assert.are.same({}, links.scan({ "" }))
    end)
  end)

  describe("heading_index", function()
    ---@param text string
    ---@return table<string, integer>
    local function index_of(text)
      write_file(root .. "/i.md", text)
      return assert(links.heading_index(root .. "/i.md"))
    end

    it("numbers a repeated heading the way GitHub does", function()
      local idx = index_of("# Dup\n## Dup\n### Dup\n")
      assert.are.equal(0, links.heading_lookup(idx, "dup"))
      assert.are.equal(1, links.heading_lookup(idx, "dup-1"))
      assert.are.equal(2, links.heading_lookup(idx, "dup-2"))
      assert.is_nil(links.heading_lookup(idx, "dup-3"))
    end)

    it("takes a heading's text from a link in it", function()
      local idx = index_of("## [1.2.0](https://x.org/compare) - 2024\n## ![logo](a.png) Brand\n")
      assert.are.equal(0, links.heading_lookup(idx, "120---2024"))
      assert.are.equal(1, links.heading_lookup(idx, "logo-brand"))
    end)

    it("ignores HTML tags in a heading", function()
      local idx = index_of("## <kbd>Ctrl</kbd> keys\n")
      assert.are.equal(0, links.heading_lookup(idx, "ctrl-keys"))
    end)

    it("knows a `{#custom-id}` and an HTML anchor", function()
      local idx = index_of('## Setup {#install}\n\n<a name="legacy"></a>\n<h2 id="other">x</h2>\n')
      assert.are.equal(0, links.heading_lookup(idx, "install"))
      assert.are.equal(0, links.heading_lookup(idx, "setup"))
      assert.are.equal(2, links.heading_lookup(idx, "legacy"))
      assert.are.equal(3, links.heading_lookup(idx, "other"))
    end)

    it("finds a heading with an emoji by the anchor GitHub gives it", function()
      local idx = index_of("## 🚀 Features\n## ✨ Neu & Übersicht\n")
      assert.are.equal(0, links.heading_lookup(idx, "-features"))
      assert.are.equal(1, links.heading_lookup(idx, "-neu--übersicht"))
    end)

    it("finds an emphasised heading by its plain anchor", function()
      local idx = index_of("## _Notes_\n")
      assert.are.equal(0, links.heading_lookup(idx, "notes"))
    end)

    it("takes a fragment as written: encoded, with spaces, in any case", function()
      local idx = index_of("## Second Part\n## Übersicht\n")
      assert.are.equal(0, links.heading_lookup(idx, "Second-Part"))
      assert.are.equal(0, links.heading_lookup(idx, "second%20part"))
      assert.are.equal(1, links.heading_lookup(idx, "%C3%9Cbersicht"))
    end)

    it("answers nil for an empty or non-string fragment", function()
      local idx = index_of("## A\n")
      assert.is_nil(links.heading_lookup(idx, ""))
      assert.is_nil(links.heading_lookup(idx, nil))
    end)

    it("is nil, not empty, for a file it cannot judge", function()
      write_file(root .. "/x.lua", "# Title\n")
      assert.is_nil(links.heading_index(root .. "/x.lua"))
      assert.is_nil(links.heading_index(root .. "/missing.md"))
      -- An empty Markdown file is judged: it has no headings.
      write_file(root .. "/empty.md", "")
      assert.are.same({}, links.heading_index(root .. "/empty.md"))
    end)

    it("does not see a heading inside a fenced code block", function()
      local idx = index_of("```\n# nope\n```\n# yes\n")
      assert.is_nil(links.heading_lookup(idx, "nope"))
      assert.are.equal(3, links.heading_lookup(idx, "yes"))
    end)

    it("does not see a heading after a fence of another kind inside a block", function()
      local idx = index_of("~~~md\n```\n# nope\n```\n~~~\n# yes\n")
      assert.is_nil(links.heading_lookup(idx, "nope"))
      assert.are.equal(5, links.heading_lookup(idx, "yes"))
    end)

    -- The file is whatever the link points at, up to MAX_READ_BYTES; every
    -- heading line below is the longest one that is still read, and shaped to
    -- make the title steps -- link text, `{#id}`, tags -- search again from
    -- each opener. Each of those is a single sweep now.
    it("stays fast on hostile heading lines", function()
      local width = links.MAX_HEADING_BYTES - 6
      local shapes = {
        ("["):rep(width),
        ("[a]("):rep(width / 4),
        ("[a]("):rep(width / 8) .. ("](x "):rep(width / 8),
        ("<a "):rep(width / 3),
        ("{#"):rep(width / 2),
        ("a "):rep((width - 4) / 2) .. "{#x}",
        ("]("):rep(width / 2),
      }
      -- A shape over the cap is rejected before any title step runs, and would
      -- measure nothing: every one has to be a heading line that is read.
      for _, shape in ipairs(shapes) do
        assert.is_true(#("## " .. shape) <= links.MAX_HEADING_BYTES, #shape)
      end
      local lines = {}
      for _ = 1, 100 do
        for _, shape in ipairs(shapes) do
          lines[#lines + 1] = "## " .. shape
        end
      end
      write_file(root .. "/hostile.md", table.concat(lines, "\n"))

      -- Under the 2 MB read cap, or the index would be nil and measure nothing.
      assert.is_table(links.heading_index(root .. "/hostile.md"))
      local ms = best_ms(function()
        links.clear_cache()
        links.heading_index(root .. "/hostile.md")
      end, 3)
      -- A cubic title pattern is seconds per line, and this is 700 of them.
      assert.is_true(ms < 400, ("took %.0f ms"):format(ms))
    end)
  end)

  describe("is_markdown", function()
    it("is true for Markdown extensions only", function()
      assert.is_true(links.is_markdown("/a/b.md"))
      assert.is_true(links.is_markdown("/a/b.MD"))
      assert.is_true(links.is_markdown("/a/b.markdown"))
      assert.is_true(links.is_markdown("/a/b.mdx"))
      assert.is_false(links.is_markdown("/a/b.txt"))
      assert.is_false(links.is_markdown("/a/b"))
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

      assert.are.equal(2, links.heading_line(root .. "/s.md", "real"))
      local ms = best_ms(function()
        links.clear_cache() -- the cache would answer every run after the first
        links.heading_line(root .. "/s.md", "real")
      end)
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

  -- While the in-process client runs it reports the broken env links itself,
  -- including the ones marksman says nothing about; marksman's own message
  -- about one would be a second diagnostic on the same range.
  describe("while the env-link client runs", function()
    before_each(function()
      package.loaded["lsp.core.env_links_server"] = {
        active = function()
          return true
        end,
      }
    end)

    after_each(function()
      package.loaded["lsp.core.env_links_server"] = nil
    end)

    it("leaves the broken env link to the client, and still drops the false alarm", function()
      local got = messages(all())
      assert.are.equal(1, #got, vim.inspect(got))
      assert.is_truthy(got[1]:find("Ambiguous link to document", 1, true))
    end)

    it("does not touch any other diagnostic", function()
      local others = function()
        return {
          diag("Ambiguous link to document 'x.md'", 2),
          diag("Link to non-existent link definition 'x'"),
        }
      end
      local with_client = messages(others())
      package.loaded["lsp.core.env_links_server"] = {
        active = function()
          return false
        end,
      }
      assert.are.same(messages(others()), with_client)
      assert.is_true(#with_client >= 1)
    end)

    it("changes nothing when languages.env_links is off", function()
      require("lsp.config").setup({ languages = { env_links = false } })
      local got = messages(all())
      assert.are.equal(1, #got, vim.inspect(got))
      assert.is_truthy(got[1]:find("Ambiguous link to document", 1, true))
    end)
  end)

  it("keeps marksman's message when the client is not running", function()
    package.loaded["lsp.core.env_links_server"] = {
      active = function()
        return false
      end,
    }
    local got = messages(all())
    package.loaded["lsp.core.env_links_server"] = nil
    assert.are.equal(2, #got, vim.inspect(got))
    assert.is_truthy(got[1]:find("resolved to " .. root .. "/gone.md", 1, true), got[1])
  end)

  it("does not annotate a kept message with what a variable holds that is not a path", function()
    vim.env.LSPTEST_SECRET = "sk-secret-token"
    local got = handler.filter_diagnostics({
      diag("Link to non-existent document '$LSPTEST_SECRET/a.md'"),
    }, false)
    vim.env.LSPTEST_SECRET = nil
    assert.are.equal(1, #got)
    assert.is_nil(got[1].message:find("sk-secret", 1, true), got[1].message)
  end)

  it("does not stat a network path to judge a message", function()
    vim.env.LSPTEST_UNC = "//192.0.2.1/share"
    local was_windows = require("lsp.core.env_links").windows
    require("lsp.core.env_links").windows = true
    local stats = {}
    local real_stat = vim.uv.fs_stat
    vim.uv.fs_stat = function(path, ...)
      if tostring(path):find("192.0.2.1", 1, true) then
        stats[#stats + 1] = path
      end
      return real_stat(path, ...)
    end
    local ok, got = pcall(handler.filter_diagnostics, {
      diag("Link to non-existent document '$LSPTEST_UNC/a.md'"),
    }, false)
    vim.uv.fs_stat = real_stat
    vim.env.LSPTEST_UNC = nil
    require("lsp.core.env_links").windows = was_windows
    assert.is_true(ok, tostring(got))
    assert.are.same({}, stats)
    -- No verdict: the old rules apply (the blanket rule hides it).
    assert.are.same({}, got)
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

  -- What the client reports on its own, as `textDocument/diagnostic` answers
  -- it. marksman reports none of the `#fragment` links, so these are the
  -- only ones there are.
  describe("diagnostics", function()
    local seq = 0

    ---@param text string
    ---@return table[]
    local function items_of(text)
      -- A new file each time: `doc` loads it, and a buffer that is already
      -- loaded keeps its text when the file is written again.
      seq = seq + 1
      local buf = doc(("%s/doc%d.md"):format(root, seq), text)
      local report = server.diagnostics({ textDocument = { uri = vim.uri_from_bufnr(buf) } })
      assert.are.equal("full", report.kind)
      return report.items
    end

    it("reports a link to a file that is not there, with where it looked", function()
      local items = items_of("[g]($LSPTEST_ENV_ROOT/gone.md)\n")
      assert.are.equal(1, #items)
      assert.are.equal("missing-file", items[1].code)
      assert.are.equal(vim.diagnostic.severity.WARN, items[1].severity)
      assert.are.equal(server.NAME, items[1].source)
      assert.is_truthy(items[1].message:find("resolved to " .. root .. "/gone.md", 1, true))
      assert.are.same(
        { start = { line = 0, character = 4 }, ["end"] = { line = 0, character = 29 } },
        items[1].range
      )
    end)

    it("is silent about a link whose file is there", function()
      assert.are.same({}, items_of("[t]($LSPTEST_ENV_ROOT/target.md)\n[d]($LSPTEST_ENV_ROOT)\n"))
    end)

    -- The gap this closes: marksman says nothing about any link with a
    -- `#fragment`, so a missing file behind one went unreported.
    it("reports a missing file even when the link carries a fragment", function()
      local items = items_of("[g]($LSPTEST_ENV_ROOT/gone.md#part)\n")
      assert.are.equal(1, #items)
      assert.are.equal("missing-file", items[1].code)
    end)

    it("reports a heading the file does not have, and only that", function()
      local items = items_of(table.concat({
        "[ok]($LSPTEST_ENV_ROOT/target.md#deep-section)",
        "[bad]($LSPTEST_ENV_ROOT/target.md#no-such-part)",
        "[top]($LSPTEST_ENV_ROOT/target.md#TARGET)",
      }, "\n") .. "\n")
      assert.are.equal(1, #items)
      assert.are.equal("missing-heading", items[1].code)
      assert.are.equal(1, items[1].range.start.line)
      assert.is_truthy(items[1].message:find("#no-such-part", 1, true))
    end)

    it("knows the numbered anchor of a repeated heading", function()
      write_file(root .. "/dups.md", "# Same\n## Same\n")
      assert.are.same({}, items_of("[b]($LSPTEST_ENV_ROOT/dups.md#same-1)\n"))
      assert.are.equal(1, #items_of("[b]($LSPTEST_ENV_ROOT/dups.md#same-2)\n"))
    end)

    -- A `#L10` into a source file, a fragment on a directory: nothing is known
    -- about their anchors, and "cannot tell" is not "broken".
    it("does not judge the fragment of a file that is not Markdown", function()
      write_file(root .. "/code.lua", "-- x\n")
      assert.are.same({}, items_of("[c]($LSPTEST_ENV_ROOT/code.lua#L10)\n"))
      -- A text file is read (a hover quotes it), but its anchors are unknown:
      -- only this one is decided by `is_markdown`, the guard in `problem`.
      write_file(root .. "/plain.txt", "x\n")
      assert.are.same({}, items_of("[t]($LSPTEST_ENV_ROOT/plain.txt#L10)\n"))
      assert.are.same({}, items_of("[d]($LSPTEST_ENV_ROOT#anything)\n"))
    end)

    it("does not judge a Markdown file above the size cap", function()
      local links = require("lsp.core.env_links")
      local saved = links.MAX_READ_BYTES
      links.MAX_READ_BYTES = 4
      local items = items_of("[t]($LSPTEST_ENV_ROOT/target.md#nope)\n")
      links.MAX_READ_BYTES = saved
      assert.are.same({}, items)
    end)

    it("is silent about a variable nothing defines", function()
      assert.are.same({}, items_of("[u]($LSPTEST_DEFINITELY_UNSET/x.md)\n"))
    end)

    it("does not report an example in a code block or a code span", function()
      assert.are.same(
        {},
        items_of(table.concat({
          "```md",
          "[x]($LSPTEST_ENV_ROOT/example.md)",
          "```",
          "like `[y]($LSPTEST_ENV_ROOT/example.md)` here",
        }, "\n") .. "\n")
      )
    end)

    it("reports in UTF-16 columns, after an emoji and an umlaut", function()
      -- 😀 is 4 bytes and 2 UTF-16 units; ü is 2 bytes and 1 unit.
      local items = items_of("😀 ü [a]($LSPTEST_ENV_ROOT/gone.md)\n")
      assert.are.equal(1, #items)
      local before = #"😀 ü [a](" -- bytes
      local units = 2 + 1 + 1 + 1 + #"[a]("
      assert.is_true(before > units)
      assert.are.equal(units, items[1].range.start.character)
      assert.are.equal(units + #"$LSPTEST_ENV_ROOT/gone.md", items[1].range["end"].character)
    end)

    it("answers an empty report for a document Neovim does not have", function()
      local report = server.diagnostics({
        textDocument = { uri = vim.uri_from_fname(root .. "/never-opened.md") },
      })
      assert.are.same({ kind = "full", items = {} }, report)
      assert.are.same({ kind = "full", items = {} }, server.diagnostics(nil))
      assert.are.same({ kind = "full", items = {} }, server.diagnostics({ textDocument = {} }))
    end)

    it("does not create a buffer for a document Neovim does not have", function()
      local before = #vim.api.nvim_list_bufs()
      server.diagnostics({ textDocument = { uri = vim.uri_from_fname(root .. "/ghost.md") } })
      assert.are.equal(before, #vim.api.nvim_list_bufs())
    end)

    it("does not print what a variable holds that is not a path", function()
      vim.env.LSPTEST_SECRET = "sk-secret-token"
      local items = items_of("[x]($LSPTEST_SECRET/a.md)\n")
      vim.env.LSPTEST_SECRET = nil
      assert.are.equal(1, #items)
      assert.is_nil(items[1].message:find("sk-secret", 1, true), items[1].message)
      assert.is_truthy(items[1].message:find("$LSPTEST_SECRET/a.md", 1, true))
    end)

    it(
      "does not print a secret that is the whole value of a variable and starts with a slash",
      function()
        vim.env.LSPTEST_TOK = "/9f2Kx+Qm7vT3rLw8aZpYc0Hn5bUeDg1J"
        local items = items_of("[x]($LSPTEST_TOK)\n")
        vim.env.LSPTEST_TOK = nil
        assert.are.equal(1, #items)
        assert.is_nil(items[1].message:find("9f2Kx", 1, true), items[1].message)
      end
    )

    it("quotes a fragment without its control bytes, and not at any length", function()
      local tab = string.char(9)
      local items =
        items_of("[x](<$LSPTEST_ENV_ROOT/target.md#a" .. tab .. "b" .. ("z"):rep(500) .. ">)\n")
      assert.are.equal(1, #items)
      assert.is_nil(items[1].message:find(tab, 1, true))
      assert.is_true(#items[1].message < 400, #items[1].message)
    end)

    it("spends only so much time on building heading indexes in one pull", function()
      local saved = server.INDEX_BUDGET_NS
      server.INDEX_BUDGET_NS = 0 -- the first build uses it up
      local lines = {}
      for i = 1, 4 do
        write_file(("%s/bud%d.md"):format(root, i), "# Only\n")
        lines[#lines + 1] = ("[l]($LSPTEST_ENV_ROOT/bud%d.md#nope)"):format(i)
      end
      local text = table.concat(lines, "\n") .. "\n"
      local first = items_of(text)
      local second = items_of(text)
      server.INDEX_BUDGET_NS = saved
      assert.are.equal(1, #first)
      -- the next pull answers the first from the cache and builds the next one
      assert.are.equal(2, #second)
    end)

    it("looks at only so many different files in one pull", function()
      local saved = server.MAX_LOOKED_UP_FILES
      server.MAX_LOOKED_UP_FILES = 3
      local lines = {}
      for i = 1, 8 do
        write_file(("%s/look%d.md"):format(root, i), "# Only\n")
        lines[#lines + 1] = ("[l]($LSPTEST_ENV_ROOT/look%d.md#nope)"):format(i)
      end
      local items = items_of(table.concat(lines, "\n") .. "\n")
      server.MAX_LOOKED_UP_FILES = saved
      assert.are.equal(3, #items)
    end)

    it("does not look at a network path", function()
      vim.env.LSPTEST_UNC = "//192.0.2.1/share"
      local was_windows = require("lsp.core.env_links").windows
      require("lsp.core.env_links").windows = true
      local stats = {}
      local real_stat = vim.uv.fs_stat
      vim.uv.fs_stat = function(path, ...)
        if tostring(path):find("192.0.2.1", 1, true) then
          stats[#stats + 1] = path
        end
        return real_stat(path, ...)
      end
      local ok, items = pcall(items_of, "[u]($LSPTEST_UNC/x.md)\n[v]($LSPTEST_UNC/y.md#h)\n")
      vim.uv.fs_stat = real_stat
      vim.env.LSPTEST_UNC = nil
      require("lsp.core.env_links").windows = was_windows
      assert.is_true(ok, tostring(items))
      assert.are.same({}, stats)
      assert.are.same({}, items)
    end)

    it("looks at a path once per pull, however many links name it", function()
      local stats = 0
      local real_stat = vim.uv.fs_stat
      vim.uv.fs_stat = function(path, ...)
        if path == root .. "/gone.md" then
          stats = stats + 1
        end
        return real_stat(path, ...)
      end
      local text = ("[g]($LSPTEST_ENV_ROOT/gone.md)\n"):rep(5)
      local ok, items = pcall(items_of, text)
      vim.uv.fs_stat = real_stat
      assert.is_true(ok, tostring(items))
      assert.are.equal(5, #items)
      assert.are.equal(1, stats)
    end)

    it("reports the other links when one of them makes the code raise", function()
      require("lsp.core.env_links").heading_index = function()
        error("boom")
      end
      local items =
        items_of("[a]($LSPTEST_ENV_ROOT/target.md#deep-section)\n[b]($LSPTEST_ENV_ROOT/gone.md)\n")
      assert.are.equal(1, #items)
      assert.are.equal("missing-file", items[1].code)
    end)

    it("builds the heading index of only so many files in one pull", function()
      local lines = {}
      for i = 1, server.MAX_INDEXED_FILES + 8 do
        write_file(("%s/many%d.md"):format(root, i), "# Only\n")
        lines[#lines + 1] = ("[l]($LSPTEST_ENV_ROOT/many%d.md#nope)"):format(i)
      end
      local items = items_of(table.concat(lines, "\n") .. "\n")
      assert.are.equal(server.MAX_INDEXED_FILES, #items)
    end)

    it("does not stat a network path for a hover, and says so", function()
      vim.env.LSPTEST_UNC = "//192.0.2.1/share"
      local was_windows = require("lsp.core.env_links").windows
      require("lsp.core.env_links").windows = true
      local stats = {}
      local real_stat = vim.uv.fs_stat
      vim.uv.fs_stat = function(path, ...)
        if tostring(path):find("192.0.2.1", 1, true) then
          stats[#stats + 1] = path
        end
        return real_stat(path, ...)
      end
      local buf = doc(root .. "/unc.md", "[u]($LSPTEST_UNC/x.md)\n")
      local ok, hover = pcall(server.hover, {
        textDocument = { uri = vim.uri_from_bufnr(buf) },
        position = { line = 0, character = 8 },
      })
      local definition = server.definition({
        textDocument = { uri = vim.uri_from_bufnr(buf) },
        position = { line = 0, character = 8 },
      })
      vim.uv.fs_stat = real_stat
      vim.env.LSPTEST_UNC = nil
      require("lsp.core.env_links").windows = was_windows
      assert.is_true(ok, tostring(hover))
      assert.are.same({}, stats)
      assert.is_nil(definition)
      assert.is_truthy(hover.contents.value:find("(not checked)", 1, true))
      assert.is_nil(hover.contents.value:find("(missing)", 1, true))
    end)

    it("does not print a variable's value in a hover", function()
      vim.env.LSPTEST_SECRET = "sk-secret-token"
      local buf = doc(root .. "/secret.md", "[x]($LSPTEST_SECRET/a.md)\n")
      local hover = server.hover({
        textDocument = { uri = vim.uri_from_bufnr(buf) },
        position = { line = 0, character = 8 },
      })
      vim.env.LSPTEST_SECRET = nil
      assert.is_nil(hover.contents.value:find("sk-secret", 1, true), hover.contents.value)
      assert.is_truthy(hover.contents.value:find("(missing)", 1, true))
    end)

    -- The budget is for the disk: scanning and indexing a large document must
    -- not use it up, or the links after them are silently not checked.
    it("does not count anything but fs_stat against the stat budget", function()
      local calls = 0
      local real_hrtime = vim.uv.hrtime
      vim.uv.hrtime = function()
        calls = calls + 1
        return calls == 1 and 0 or 10 ^ 12 -- the pull "took" far longer than the budget
      end
      local ok, items = pcall(items_of, "[g]($LSPTEST_ENV_ROOT/gone.md)\n")
      vim.uv.hrtime = real_hrtime
      assert.is_true(ok, tostring(items))
      assert.are.equal(1, #items)
    end)

    it("charges only a read and a parse against the cap on indexed files", function()
      local lines = {}
      for i = 1, server.MAX_INDEXED_FILES + 8 do
        write_file(("%s/cap%d.md"):format(root, i), "# Only\n")
        lines[#lines + 1] = ("[l]($LSPTEST_ENV_ROOT/cap%d.md#nope)"):format(i)
      end
      local text = table.concat(lines, "\n") .. "\n"
      assert.are.equal(server.MAX_INDEXED_FILES, #items_of(text))
      -- The next pull is answered from the cache for those, and builds the rest.
      assert.are.equal(server.MAX_INDEXED_FILES + 8, #items_of(text))
    end)

    it("logs the first failure of a pull once, and keeps the other links", function()
      local logged = {}
      local real_error = vim.lsp.log.error
      vim.lsp.log.error = function(...)
        logged[#logged + 1] = table.concat(vim.tbl_map(tostring, { ... }), " ")
      end
      require("lsp.core.env_links").heading_index = function()
        error("boom")
      end
      local ok, items = pcall(
        items_of,
        "[a]($LSPTEST_ENV_ROOT/target.md#x)\n[b]($LSPTEST_ENV_ROOT/target.md#y)\n[c]($LSPTEST_ENV_ROOT/gone.md)\n"
      )
      vim.lsp.log.error = real_error
      assert.is_true(ok, tostring(items))
      assert.are.equal(1, #items)
      assert.are.equal(1, #logged, vim.inspect(logged))
      assert.is_truthy(logged[1]:find("boom", 1, true))
      assert.is_truthy(logged[1]:find("target.md#x", 1, true))
    end)
  end)

  describe("completion", function()
    local seq = 0

    --- Ask for completion at the end of line `lnum` (0-based) of a new document.
    ---@param lines string[]
    ---@param lnum? integer # Default: the last line.
    ---@param character? integer # UTF-16 column of the cursor. Default: the end of the line.
    ---@return table|nil
    local function complete(lines, lnum, character)
      seq = seq + 1
      local buf = doc(("%s/cp%d.md"):format(root, seq), table.concat(lines, "\n") .. "\n")
      lnum = lnum or #lines - 1
      local line = lines[lnum + 1]
      return server.completion({
        textDocument = { uri = vim.uri_from_bufnr(buf) },
        position = { line = lnum, character = character or vim.str_utfindex(line, "utf-16", #line) },
      })
    end

    ---@param result table|nil
    ---@return string[]
    local function labels(result)
      local out = {}
      for _, item in ipairs(result and result.items or {}) do
        out[#out + 1] = item.label
      end
      return out
    end

    before_each(function()
      vim.fn.mkdir(root .. "/notes/sub", "p")
      write_file(root .. "/notes/a.md", "# a\n")
      write_file(root .. "/notes/b file.md", "# b\n")
      write_file(root .. "/notes/.hidden", "x\n")
      vim.fn.mkdir(root .. "/My Dir", "p")
    end)

    it("lists the entries of the directory, folders first, without dotfiles", function()
      local r = complete({ "[a]($LSPTEST_ENV_ROOT/notes/" })
      assert.are.same({ "sub/", "a.md", "b file.md" }, labels(r))
      table.sort(r.items, function(x, y)
        return x.sortText < y.sortText
      end)
      assert.are.equal("sub/", r.items[1].label)
      assert.is_false(r.isIncomplete)
      local kinds = {}
      for _, i in ipairs(r.items) do
        kinds[i.label] = i.kind
      end
      assert.are.equal(19, kinds["sub/"])
      assert.are.equal(17, kinds["a.md"])
    end)

    it("filters by what is typed after the last slash, and replaces just that", function()
      local r = complete({ "[a]($LSPTEST_ENV_ROOT/notes/b" })
      assert.are.same({ "b file.md" }, labels(r))
      local edit = r.items[1].textEdit
      assert.are.equal("b%20file.md", edit.newText)
      assert.are.equal(#"[a]($LSPTEST_ENV_ROOT/notes/", edit.range.start.character)
      assert.are.equal(#"[a]($LSPTEST_ENV_ROOT/notes/b", edit.range["end"].character)
      -- case does not matter, and a dot asks for the hidden ones
      assert.are.same({ "a.md" }, labels(complete({ "[a]($LSPTEST_ENV_ROOT/notes/A" })))
      assert.are.same({ ".hidden" }, labels(complete({ "[a]($LSPTEST_ENV_ROOT/notes/." })))
    end)

    it("percent-encodes what a bare target cannot hold, and not inside `<...>`", function()
      local bare = complete({ "[a]($LSPTEST_ENV_ROOT/My" })
      assert.are.equal("My%20Dir/", bare.items[1].textEdit.newText)
      assert.are.equal("My%20Dir", bare.items[1].filterText)
      local angled = complete({ "[a](<$LSPTEST_ENV_ROOT/My" })
      assert.are.equal("My Dir/", angled.items[1].textEdit.newText)
      -- ... and an encoded part already typed is understood
      assert.are.same({ "My Dir/" }, labels(complete({ "[a]($LSPTEST_ENV_ROOT/My%20" })))
    end)

    it("counts the range in UTF-16 units, after an emoji and an umlaut", function()
      local r = complete({ "😀 ü [a]($LSPTEST_ENV_ROOT/notes/b" })
      local units = 2 + 1 + 1 + 1 + #"[a]($LSPTEST_ENV_ROOT/notes/"
      assert.are.equal(units, r.items[1].textEdit.range.start.character)
      assert.are.equal(units + 1, r.items[1].textEdit.range["end"].character)
    end)

    it("completes a reference definition and a `~/` target", function()
      assert.are.same(
        { "sub/", "a.md", "b file.md" },
        labels(complete({ "[lbl]: $LSPTEST_ENV_ROOT/notes/" }))
      )
      local real_home = vim.uv.os_homedir
      vim.uv.os_homedir = function()
        return root
      end
      local r = complete({ "[a](~/notes/s" })
      vim.uv.os_homedir = real_home
      assert.are.same({ "sub/" }, labels(r))
    end)

    it("offers the variables that name a directory, and no secret", function()
      vim.env.LSPTEST_SECRET_X = "sk-secret-token"
      vim.env.LSPTEST_FILE_X = root .. "/notes/a.md"
      local r = complete({ "[a]($LSPTEST_" })
      vim.env.LSPTEST_SECRET_X = nil
      vim.env.LSPTEST_FILE_X = nil
      assert.are.same({ "$LSPTEST_ENV_ROOT" }, labels(r))
      assert.are.equal("$LSPTEST_ENV_ROOT/", r.items[1].textEdit.newText)
      assert.are.equal(#"[a](", r.items[1].textEdit.range.start.character)
      -- the braced spelling keeps its braces
      local braced = complete({ "[a](${LSPTEST_E" })
      assert.are.equal("${LSPTEST_ENV_ROOT}/", braced.items[1].textEdit.newText)
      -- the config directory has no real variable behind it
      -- (only when that directory exists: a CI runner may have no config at all)
      local has_config = vim.fn.isdirectory(vim.fn.stdpath("config")) == 1
      assert.are.equal(
        has_config,
        vim.tbl_contains(labels(complete({ "[a]($NVIM_CONF" })), "$NVIM_CONFIG_DIR")
      )
      -- a variable typed in full is offered once more, with its slash
      assert.are.same({ "$LSPTEST_ENV_ROOT" }, labels(complete({ "[a]($LSPTEST_ENV_ROOT" })))
    end)

    it("answers nil where it has nothing to say", function()
      for name, lines in pairs({
        ordinary = { "[a](./notes/" },
        undefined = { "[a]($LSPTEST_NOT_DEFINED/notes/" },
        ["no slash after a tilde"] = { "[a](~" },
        fragment = { "[a]($LSPTEST_ENV_ROOT/target.md#" },
        closed = { "[a]($LSPTEST_ENV_ROOT/notes/) x" },
        ["missing directory"] = { "[a]($LSPTEST_ENV_ROOT/nope/" },
        ["a file, not a directory"] = { "[a]($LSPTEST_ENV_ROOT/target.md/" },
        fence = { "```", "[a]($LSPTEST_ENV_ROOT/notes/", "```" },
        ["front matter"] = { "---", "x: [a]($LSPTEST_ENV_ROOT/notes/", "---" },
        ["no match"] = { "[a]($LSPTEST_ENV_ROOT/notes/zzz" },
      }) do
        local lnum = name == "fence" and 1 or name == "front matter" and 1 or nil
        assert.is_nil(complete(lines, lnum), name)
      end
    end)

    it("shows a symlink to a directory as a folder", function()
      local made = vim.uv.fs_symlink(root .. "/notes/sub", root .. "/notes/linkdir", { dir = true })
      if not made then
        return pending("cannot create symlinks here")
      end
      local r = complete({ "[a]($LSPTEST_ENV_ROOT/notes/link" })
      assert.are.same({ "linkdir/" }, labels(r))
      assert.are.equal(19, r.items[1].kind)
    end)

    it("answers nil inside a closed code span", function()
      local line = "`[a]($LSPTEST_ENV_ROOT/notes/` and more"
      assert.is_nil(complete({ line }, 0, #"`[a]($LSPTEST_ENV_ROOT/notes/"))
      -- the same line without the span completes
      local plain = "[a]($LSPTEST_ENV_ROOT/notes/) and more"
      assert.is_truthy(complete({ plain }, 0, #"[a]($LSPTEST_ENV_ROOT/notes/"))
    end)

    it("does not look at a network path", function()
      vim.env.LSPTEST_UNC = "//192.0.2.1/share"
      local was_windows = require("lsp.core.env_links").windows
      require("lsp.core.env_links").windows = true
      local stats = {}
      local real_stat = vim.uv.fs_stat
      vim.uv.fs_stat = function(path, ...)
        if tostring(path):find("192.0.2.1", 1, true) then
          stats[#stats + 1] = path
        end
        return real_stat(path, ...)
      end
      local ok, r = pcall(complete, { "[a]($LSPTEST_UNC/dir/" })
      local ok2, names = pcall(complete, { "[a]($LSPTEST_U" })
      vim.uv.fs_stat = real_stat
      require("lsp.core.env_links").windows = was_windows
      vim.env.LSPTEST_UNC = nil
      assert.is_true(ok, tostring(r))
      assert.is_true(ok2, tostring(names))
      assert.is_nil(r)
      assert.is_nil(names, "a network share is not offered as a variable either")
      assert.are.same({}, stats)
    end)

    it("stops at the item cap and says the answer is incomplete", function()
      for i = 1, 6 do
        write_file(("%s/notes/many%d.md"):format(root, i), "x\n")
      end
      local saved = server.MAX_COMPLETION_ITEMS
      server.MAX_COMPLETION_ITEMS = 3
      local r = complete({ "[a]($LSPTEST_ENV_ROOT/notes/many" })
      server.MAX_COMPLETION_ITEMS = saved
      assert.are.equal(3, #r.items)
      assert.is_true(r.isIncomplete)
    end)

    it("looks at no more than a bounded number of directory entries", function()
      for i = 1, 6 do
        write_file(("%s/notes/zz%d.md"):format(root, i), "x\n")
      end
      local saved = server.MAX_COMPLETION_SCAN
      server.MAX_COMPLETION_SCAN = 2
      local r = complete({ "[a]($LSPTEST_ENV_ROOT/notes/zz" })
      server.MAX_COMPLETION_SCAN = saved
      assert.is_true(r == nil or r.isIncomplete)
    end)

    it("does not raise on a position that names no line", function()
      assert.is_nil(server.completion(nil))
      assert.is_nil(server.completion({
        textDocument = { uri = "file:///nope.md" },
        position = { line = 0, character = 0 },
      }))
      local buf = doc(root .. "/one.md", "# x\n")
      assert.is_nil(server.completion({
        textDocument = { uri = vim.uri_from_bufnr(buf) },
        position = { line = 99, character = 0 },
      }))
      assert.is_nil(server.completion({
        textDocument = { uri = vim.uri_from_bufnr(buf) },
        position = { line = -1, character = 0 },
      }))
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

    -- Neovim pulls diagnostics by itself after the document was opened or
    -- changed, so the client has to say so (`diagnosticProvider`,
    -- `textDocumentSync`); without either nothing ever asks.
    it("reports a broken link through the diagnostics Neovim pulls", function()
      server.setup({ env_links = true })
      local buf = open_markdown(root .. "/doc.md", "[g]($LSPTEST_ENV_ROOT/gone.md)\n")

      local function ours()
        return vim.tbl_filter(function(d)
          return d.source == server.NAME
        end, vim.diagnostic.get(buf))
      end
      assert.is_true(
        vim.wait(3000, function()
          return #ours() == 1
        end),
        "no diagnostic arrived"
      )
      assert.are.equal("missing-file", ours()[1].code)

      -- ... and follows the document: fixing the link clears it.
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "[t]($LSPTEST_ENV_ROOT/target.md)" })
      assert.is_true(
        vim.wait(3000, function()
          return #ours() == 0
        end),
        "the diagnostic stayed after the link was fixed"
      )
    end)

    it("advertises what Neovim needs to pull", function()
      server.setup({ env_links = true })
      local buf = open_markdown(root .. "/doc.md", "# x\n")
      assert.is_true(vim.wait(3000, function()
        return #vim.lsp.get_clients({ bufnr = buf, name = server.NAME }) > 0
      end))
      local caps = vim.lsp.get_clients({ bufnr = buf, name = server.NAME })[1].server_capabilities
      assert.are.equal(server.NAME, caps.diagnosticProvider.identifier)
      assert.is_false(caps.diagnosticProvider.workspaceDiagnostics)
      assert.is_true(caps.textDocumentSync.openClose)
    end)

    -- A file written inside Neovim does not change the document that links to
    -- it, so nothing would ask again: the write itself has to.
    it("re-checks when a file is written, so a created target clears the warning", function()
      server.setup({ env_links = true })
      local buf = open_markdown(root .. "/doc.md", "[n]($LSPTEST_ENV_ROOT/later.md)\n")
      local function ours()
        return vim.tbl_filter(function(d)
          return d.source == server.NAME
        end, vim.diagnostic.get(buf))
      end
      assert.is_true(vim.wait(3000, function()
        return #ours() == 1
      end))

      -- Nothing but the trigger may clear it: wait out the debounce and the
      -- pulls that follow an attach, and make sure it is still there.
      vim.wait(800, function()
        return false
      end)
      write_file(root .. "/later.md", "# Later\n")
      vim.wait(800, function()
        return false
      end)
      assert.are.equal(1, #ours(), "the warning went away without a trigger")
      vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf })
      assert.is_true(
        vim.wait(3000, function()
          return #ours() == 0
        end),
        "the warning stayed after the target was created"
      )
    end)

    it("answers completion through the same client, and advertises its triggers", function()
      server.setup({ env_links = true })
      vim.fn.mkdir(root .. "/notes", "p")
      write_file(root .. "/notes/a.md", "# a\n")
      local buf = open_markdown(root .. "/doc.md", "[a]($LSPTEST_ENV_ROOT/notes/\n")
      assert.is_true(vim.wait(3000, function()
        return #vim.lsp.get_clients({ bufnr = buf, name = server.NAME }) > 0
      end))
      local caps = vim.lsp.get_clients({ bufnr = buf, name = server.NAME })[1].server_capabilities
      assert.are.same({ "/", "$", "{" }, caps.completionProvider.triggerCharacters)

      local results = vim.lsp.buf_request_sync(buf, "textDocument/completion", {
        textDocument = { uri = vim.uri_from_bufnr(buf) },
        position = { line = 0, character = #"[a]($LSPTEST_ENV_ROOT/notes/" },
      }, 3000)
      local found
      for _, r in pairs(results or {}) do
        if r.result then
          found = r.result
        end
      end
      assert.is_truthy(found)
      assert.are.equal("a.md", found.items[1].label)
    end)

    it("says whether it is running", function()
      assert.is_false(server.active())
      server.setup({ env_links = true })
      local buf = open_markdown(root .. "/doc.md", "# x\n")
      assert.is_true(vim.wait(3000, function()
        return #vim.lsp.get_clients({ bufnr = buf, name = server.NAME }) > 0
      end))
      assert.is_true(server.active())
      server.detach()
      assert.is_true(vim.wait(3000, function()
        return not server.active()
      end))
    end)

    it("re-checks when Neovim regains focus, too", function()
      server.setup({ env_links = true })
      local buf = open_markdown(root .. "/doc.md", "[n]($LSPTEST_ENV_ROOT/later.md)\n")
      local function ours()
        return vim.tbl_filter(function(d)
          return d.source == server.NAME
        end, vim.diagnostic.get(buf))
      end
      assert.is_true(vim.wait(3000, function()
        return #ours() == 1
      end))

      -- Nothing but the trigger may clear it: wait out the debounce and the
      -- pulls that follow an attach, and make sure it is still there.
      vim.wait(800, function()
        return false
      end)
      write_file(root .. "/later.md", "# Later\n")
      vim.wait(800, function()
        return false
      end)
      assert.are.equal(1, #ours(), "the warning went away without a trigger")
      vim.api.nvim_exec_autocmds("FocusGained", {})
      assert.is_true(
        vim.wait(3000, function()
          return #ours() == 0
        end),
        "the warning stayed after the target was created and Neovim regained focus"
      )
    end)

    -- Neovim pulls after a change only for a buffer that is shown: a change
    -- made to a hidden one leaves its diagnostics stale until it is shown.
    it("pulls for a hidden Markdown buffer that changed, when it is shown", function()
      server.setup({ env_links = true })
      write_file(root .. "/hidden.md", "[g]($LSPTEST_ENV_ROOT/gone.md)\n")
      open_markdown(root .. "/shown.md", "# x\n")
      local hidden = vim.fn.bufadd(root .. "/hidden.md")
      vim.fn.bufload(hidden)
      vim.bo[hidden].filetype = "markdown"
      local function ours()
        return vim.tbl_filter(function(d)
          return d.source == server.NAME
        end, vim.diagnostic.get(hidden))
      end
      assert.is_true(vim.wait(3000, function()
        return #ours() == 1
      end))

      vim.api.nvim_buf_set_lines(hidden, 0, 1, false, { "[t]($LSPTEST_ENV_ROOT/target.md)" })
      vim.wait(800, function()
        return false
      end)
      assert.are.equal(1, #ours(), "a hidden buffer was pulled without being shown")

      vim.api.nvim_set_current_buf(hidden)
      assert.is_true(
        vim.wait(3000, function()
          return #ours() == 0
        end),
        "the stale diagnostic stayed once the buffer was shown"
      )
    end)

    it("pulls for a hidden buffer whatever its file is called", function()
      server.setup({ env_links = true })
      write_file(root .. "/hidden.mkd", "[g]($LSPTEST_ENV_ROOT/gone.md)\n")
      open_markdown(root .. "/shown.md", "# x\n")
      local hidden = vim.fn.bufadd(root .. "/hidden.mkd")
      vim.fn.bufload(hidden)
      vim.bo[hidden].filetype = "markdown"
      local function ours()
        return vim.tbl_filter(function(d)
          return d.source == server.NAME
        end, vim.diagnostic.get(hidden))
      end
      assert.is_true(vim.wait(3000, function()
        return #ours() == 1
      end))
      vim.api.nvim_buf_set_lines(hidden, 0, 1, false, { "[t]($LSPTEST_ENV_ROOT/target.md)" })
      vim.wait(800, function()
        return false
      end)
      assert.are.equal(1, #ours())
      vim.api.nvim_set_current_buf(hidden)
      assert.is_true(vim.wait(3000, function()
        return #ours() == 0
      end))
    end)

    -- Neovim clears a client's pulled diagnostics on detach only when no other
    -- pull-capable client stays on the buffer.
    it("takes its diagnostics with it when another pull client stays on the buffer", function()
      local function pull_server()
        return function(dispatchers)
          local srv = {}
          function srv.request(method, _, callback, notify_reply)
            if method == "initialize" then
              callback(nil, {
                capabilities = {
                  textDocumentSync = { openClose = true, change = 2 },
                  diagnosticProvider = {
                    identifier = "other",
                    interFileDependencies = false,
                    workspaceDiagnostics = false,
                  },
                },
              })
            elseif method == "textDocument/diagnostic" then
              callback(nil, { kind = "full", items = {} })
            elseif method == "shutdown" then
              callback(nil, nil)
            else
              callback({ code = -32601, message = "unsupported" }, nil)
            end
            if notify_reply then
              notify_reply(1)
            end
            return true, 1
          end
          function srv.notify(method)
            if method == "exit" then
              dispatchers.on_exit(0, 0)
            end
            return true
          end
          function srv.is_closing()
            return false
          end
          function srv.terminate() end
          return srv
        end
      end

      server.setup({ env_links = true })
      local buf = open_markdown(root .. "/doc.md", "[g]($LSPTEST_ENV_ROOT/gone.md)\n")
      vim.lsp.start({ name = "lsp-test-pull-other", cmd = pull_server(), root_dir = root }, {
        bufnr = buf,
      })
      local function ours()
        return vim.tbl_filter(function(d)
          return d.source == server.NAME
        end, vim.diagnostic.get(buf))
      end
      assert.is_true(vim.wait(3000, function()
        return #ours() == 1
          and #vim.lsp.get_clients({ bufnr = buf, name = "lsp-test-pull-other" }) > 0
      end))

      server.detach()
      assert.is_true(
        vim.wait(3000, function()
          return #ours() == 0
        end),
        "the stopped client's diagnostics stayed"
      )
      for _, c in ipairs(vim.lsp.get_clients({ name = "lsp-test-pull-other" })) do
        c:stop()
      end
    end)

    -- marksman publishes for every file of the workspace; the client answers for
    -- the buffers it is attached to. Its own message is dropped only where the
    -- client answers, and a broken link is never reported by nobody.
    describe("and marksman reports the same broken link", function()
      local message = "Link to non-existent document '$LSPTEST_ENV_ROOT/gone.md'"

      ---@param uri string
      ---@return table[] delivered
      local function marksman_pushes(uri)
        local get_client = vim.lsp.get_client_by_id
        local default = vim.lsp.handlers["textDocument/publishDiagnostics"]
        local got
        vim.lsp.get_client_by_id = function()
          return { name = "marksman" }
        end
        vim.lsp.handlers["textDocument/publishDiagnostics"] = function(_, result)
          got = result
        end
        package.loaded["lsp.servers.marksman.diagnostics_handler"] = nil
        local handler = require("lsp.servers.marksman.diagnostics_handler").make_handler()
        local ok, err = pcall(handler, nil, {
          uri = uri,
          diagnostics = {
            {
              range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 1 } },
              severity = 2,
              message = message,
            },
          },
        }, { client_id = 1 }, {})
        vim.lsp.get_client_by_id = get_client
        vim.lsp.handlers["textDocument/publishDiagnostics"] = default
        package.loaded["lsp.servers.marksman.diagnostics_handler"] = nil
        assert.is_true(ok, tostring(err))
        return got and got.diagnostics or {}
      end

      before_each(function()
        require("lsp.config").setup({})
      end)

      it("drops marksman's message for a document the client is attached to", function()
        server.setup({ env_links = true })
        local buf = open_markdown(root .. "/doc.md", "[g]($LSPTEST_ENV_ROOT/gone.md)\n")
        assert.is_true(vim.wait(3000, function()
          return #vim.lsp.get_clients({ bufnr = buf, name = server.NAME }) > 0
        end))
        assert.are.same({}, marksman_pushes(vim.uri_from_bufnr(buf)))
      end)

      it("keeps it, annotated, for a document nobody has open", function()
        server.setup({ env_links = true })
        local buf = open_markdown(root .. "/doc.md", "# x\n")
        assert.is_true(vim.wait(3000, function()
          return #vim.lsp.get_clients({ bufnr = buf, name = server.NAME }) > 0
        end))
        local got = marksman_pushes(vim.uri_from_fname(root .. "/other.md"))
        assert.are.equal(1, #got)
        assert.is_truthy(got[1].message:find("(resolved to " .. root .. "/gone.md)", 1, true))
      end)

      it("keeps it for a loaded buffer the client is not attached to", function()
        server.setup({ env_links = true })
        local buf = open_markdown(root .. "/doc.md", "# x\n")
        assert.is_true(vim.wait(3000, function()
          return #vim.lsp.get_clients({ bufnr = buf, name = server.NAME }) > 0
        end))
        -- (Whether `bufload` attaches depends on filetype detection: detach to be sure.)
        write_file(root .. "/loaded.md", "[g]($LSPTEST_ENV_ROOT/gone.md)\n")
        local loaded = vim.fn.bufadd(root .. "/loaded.md")
        vim.fn.bufload(loaded)
        vim.wait(300, function()
          return false
        end)
        for _, c in ipairs(vim.lsp.get_clients({ bufnr = loaded, name = server.NAME })) do
          vim.lsp.buf_detach_client(loaded, c.id)
        end
        assert.are.equal(0, #vim.lsp.get_clients({ bufnr = loaded, name = server.NAME }))
        local got = marksman_pushes(vim.uri_from_bufnr(loaded))
        assert.are.equal(1, #got)
      end)

      -- The annotation used to be lost whenever nothing else was dropped from
      -- the push: only a changed *count* made the handler pass the filtered list on.
      it("annotates it when the client is not running, with nothing else dropped", function()
        local got = marksman_pushes(vim.uri_from_fname(root .. "/doc.md"))
        assert.are.equal(1, #got)
        assert.is_truthy(got[1].message:find("(resolved to " .. root .. "/gone.md)", 1, true))
      end)
    end)
  end)
end)
