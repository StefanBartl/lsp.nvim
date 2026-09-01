--- Covers the shared usage counter and the engine-neutral registrar.
---
--- These two exist because the hand-written sources used to reach for nvim-cmp
--- themselves, which meant choosing blink silently dropped them. What is worth
--- pinning down is therefore the seam: that ranking is engine-independent, that
--- namespaces do not bleed into each other, and that a pick is recorded no
--- matter which engine reported it.

-- Only the registrar is held as an upvalue: `with_temp_state` reloads the
-- counter, so a module-level `usage` would be a second, stale instance whose
-- counts the tests never see.
local register = require("lsp.completion.register")

---Point the counter at a scratch file so a test run never touches the real
---history in stdpath("state").
---@param fn fun(usage: table, store: table<string, any>) # the freshly reloaded counter, and the table standing in for the state file
local function with_temp_state(fn)
  local json = require("lib.nvim.fs.json")
  local real_read, real_write = json.read, json.write

  ---@type table<string, any>
  local store = {}
  -- Test doubles for the duration of the callback; the originals are put
  -- back below.
  ---@diagnostic disable-next-line: duplicate-set-field
  json.read = function(path)
    return store[path]
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  json.write = function(path, tbl)
    store[path] = vim.deepcopy(tbl)
  end

  package.loaded["lsp.completion.usage"] = nil
  local fresh = require("lsp.completion.usage")

  local ok, err = pcall(fn, fresh, store)

  json.read, json.write = real_read, real_write
  package.loaded["lsp.completion.usage"] = nil
  require("lsp.completion.usage")

  if not ok then
    error(err)
  end
end

describe("lsp.completion.usage", function()
  it("ranks the most-used label first", function()
    with_temp_state(function(u)
      u.bump("ns", "beta")
      u.bump("ns", "beta")
      u.bump("ns", "alpha")
      assert.are.same({ "beta", "alpha" }, u.ranked("ns"))
    end)
  end)

  it("falls back to alphabetical among ties", function()
    with_temp_state(function(u)
      u.bump("ns", "gamma")
      u.bump("ns", "alpha")
      u.bump("ns", "beta")
      assert.are.same({ "alpha", "beta", "gamma" }, u.ranked("ns"))
    end)
  end)

  it("lists only the labels that were actually picked", function()
    -- The dictionary source hands over ~25000 words; ranking has to stay a sort
    -- over the handful with a count, not over all of them.
    with_temp_state(function(u)
      u.bump("ns", "picked")
      assert.are.same({ "picked" }, u.ranked("ns"))
    end)
  end)

  it("keeps namespaces apart", function()
    with_temp_state(function(u)
      -- The same spelling in two namespaces must not share a count, or writing
      -- prose would reorder the plugin-name list.
      u.bump("md_words", "documentation")
      u.bump("md_words", "documentation")
      assert.are.equal(0, u.count("personal_names", "documentation"))
      assert.are.equal(2, u.count("md_words", "documentation"))
    end)
  end)

  it("sortText is zero-padded so string comparison stays numeric", function()
    with_temp_state(function(u)
      -- The trap this guards: sortText compares as a string in both engines,
      -- so an unpadded "10" would sort before "9".
      assert.is_true(u.sort_text(9) < u.sort_text(10))
      assert.is_true(u.sort_text(1) < u.sort_text(100))
    end)
  end)

  it("a picked label outranks an unpicked one", function()
    -- The whole point of the module. Leaving the unpicked item's sortText nil
    -- would lose this: both engines read a missing sortText as "no opinion" and
    -- move on to the next comparator, rather than ranking it last.
    with_temp_state(function(u)
      assert.is_true(u.sort_text(1) < u.sort_text_unranked("aardvark"))
      assert.is_true(u.sort_text(99999999) < u.sort_text_unranked("aardvark"))
    end)
  end)

  it("unpicked labels stay alphabetical among themselves", function()
    with_temp_state(function(u)
      assert.is_true(u.sort_text_unranked("alpha") < u.sort_text_unranked("beta"))
    end)
  end)

  it("an unpicked label loses to what an LSP server would emit", function()
    -- Servers emit digits or the label itself; "~" sorts after both, so a raw
    -- dictionary word never displaces a real completion on a tie.
    with_temp_state(function(u)
      assert.is_true(u.sort_text_unranked("word") > "0005")
      assert.is_true(u.sort_text_unranked("word") > "word")
    end)
  end)

  it("persists across a reload", function()
    with_temp_state(function(u)
      u.bump("ns", "kept")
      package.loaded["lsp.completion.usage"] = nil
      local reloaded = require("lsp.completion.usage")
      assert.are.equal(1, reloaded.count("ns", "kept"))
    end)
  end)

  it("migrates the pre-split personal_names history", function()
    with_temp_state(function(_, store)
      -- The counts are the user's, accumulated over months; the rename must not
      -- silently reset them.
      local legacy = vim.fs.joinpath(vim.fn.stdpath("state"), "personal_names_usage.json")
      store[legacy] = { ["cascade.nvim"] = 7 }

      package.loaded["lsp.completion.usage"] = nil
      local fresh = require("lsp.completion.usage")
      assert.are.equal(7, fresh.count("personal_names", "cascade.nvim"))
    end)
  end)
end)

describe("lsp.completion.register", function()
  ---@param filetypes string[]|nil
  ---@return LspNvim.CompletionSource
  local function spec(filetypes)
    return {
      name = "test_source",
      namespace = "test_ns",
      filetypes = filetypes,
      items = function()
        return {}
      end,
    }
  end

  it("a source without filetypes applies everywhere", function()
    assert.is_true(register.applies(spec(nil)))
  end)

  it("a filetype-scoped source applies only there", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = bufnr })
    vim.api.nvim_set_current_buf(bufnr)
    assert.is_true(register.applies(spec({ "markdown" })))
    assert.is_false(register.applies(spec({ "lua" })))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("a pick bumps the count and runs the source's hook", function()
    with_temp_state(function(u)
      local picked
      local s = spec(nil)
      s.on_pick = function(label)
        picked = label
      end
      register.picked(s, "chosen")
      assert.are.equal("chosen", picked)
      assert.are.equal(1, u.count("test_ns", "chosen"))
    end)
  end)

  it("a source without a namespace opts out of counting, not of the hook", function()
    with_temp_state(function()
      local picked
      local s = spec(nil)
      s.namespace = nil
      s.on_pick = function(label)
        picked = label
      end
      assert.has_no.errors(function()
        register.picked(s, "chosen")
      end)
      assert.are.equal("chosen", picked)
    end)
  end)

  it("a throwing on_pick does not lose the count", function()
    with_temp_state(function(u)
      local s = spec(nil)
      s.on_pick = function()
        error("boom")
      end
      assert.has_no.errors(function()
        register.picked(s, "chosen")
      end)
      assert.are.equal(1, u.count("test_ns", "chosen"))
    end)
  end)

  it("registering records the spec so blink can find it later", function()
    -- blink resolves providers from a module path and gets no closure, so the
    -- lookup by name is the only thing connecting the two.
    register.source(spec(nil))
    assert.is_not_nil(register.spec("test_source"))
    assert.are.equal("test_source", register.spec("test_source").name)
  end)

  it("rejects a source with no name or no items function", function()
    assert.has_error(function()
      -- The empty name is the case; `items` only has to be a function.
      ---@diagnostic disable-next-line: missing-return
      register.source({ name = "", items = function() end })
    end)
    assert.has_error(function()
      -- A non-function `items` is the case.
      ---@diagnostic disable-next-line: assign-type-mismatch
      register.source({ name = "x", items = "not a function" })
    end)
  end)
end)

describe("lsp.completion.blink", function()
  local Source = require("lsp.completion.blink")

  it("yields nothing for a name that was never registered", function()
    local src = Source.new({ source = "no_such_source" })
    assert.is_false(src:enabled())

    local got
    src:get_completions({}, function(response)
      got = response
    end)
    assert.are.same({}, got.items)
  end)

  it("still inserts the text when recording a pick", function()
    -- Counting must never replace the default implementation -- that is what
    -- actually inserts the completion.
    with_temp_state(function()
      register.source({
        name = "blink_probe",
        namespace = "blink_probe",
        items = function()
          return {}
        end,
      })

      local inserted, done = false, false
      local src = Source.new({ source = "blink_probe" })
      src:execute({}, { label = "word" }, function()
        done = true
      end, function()
        inserted = true
      end)

      assert.is_true(inserted, "default_implementation ran")
      assert.is_true(done, "callback ran")
    end)
  end)
end)
