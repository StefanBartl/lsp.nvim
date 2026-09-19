--- Covers the signature-help / hover UI in `lsp.tools.lsp_signature`: the
--- popup itself, the request that fills it, and the highlighting on top.
---
--- Every case here needs either two clients that behave differently, or two
--- requests in flight at once. That is what the module is for -- a buffer with
--- a language server and a linter on it is the normal case, not the edge one
--- -- and it is the condition none of the defects below survived.
---
--- The clients are stubs. A real server would answer, eventually, and
--- eventually is exactly what these cases are about.

describe("lsp.tools.lsp_signature", function()
  local api = vim.api

  local saved_get_clients

  before_each(function()
    saved_get_clients = vim.lsp.get_clients
  end)

  after_each(function()
    vim.lsp.get_clients = saved_get_clients
    require("lsp.tools.lsp_signature.state").close()
    for _, win in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_config(win).relative ~= "" then
        pcall(api.nvim_win_close, win, true)
      end
    end
  end)

  --- Every floating window currently on screen.
  ---@return integer[]
  local function floats()
    local out = {}
    for _, win in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_config(win).relative ~= "" then
        out[#out + 1] = win
      end
    end
    return out
  end

  --- Let the scheduled callbacks that open the popup actually run.
  ---@param predicate fun(): boolean
  ---@return nil
  local function settle(predicate)
    vim.wait(500, predicate, 5)
  end

  ---@param text string
  ---@return integer bufnr
  local function source_buffer(text)
    local bufnr = api.nvim_create_buf(true, false)
    api.nvim_buf_set_lines(bufnr, 0, -1, false, { text })
    api.nvim_set_current_buf(bufnr)
    api.nvim_win_set_cursor(0, { 1, #text - 1 })
    return bufnr
  end

  ---@return function
  local function request_and_show()
    package.loaded["lsp.tools.lsp_signature.request_and_show"] = nil
    return require("lsp.tools.lsp_signature.request_and_show")
  end

  ---@param result table The `signatureHelp` payload the client answers with.
  ---@return table
  local function signature_client(result)
    return {
      id = 1,
      name = "sigls",
      offset_encoding = "utf-16",
      server_capabilities = { signatureHelpProvider = {} },
      request = function(_self, _method, _params, handler)
        handler(nil, result)
        return true, 1
      end,
    }
  end

  --- `foo(a, b)` with the second parameter active, the way the base protocol
  --- says it: `activeParameter` on the *result*.
  ---@return table
  local function result_level_active()
    return {
      signatures = {
        { label = "foo(a, b)", parameters = { { label = { 4, 5 } }, { label = { 7, 8 } } } },
      },
      activeSignature = 0,
      activeParameter = 1,
    }
  end

  -- The popup was opened with `footer = <path>` and read `opts.title`, so the
  -- path went nowhere: measured, `nvim_win_get_config().title` was nil and the
  -- statusline was still the default `%<%f %h%w%m%r ...`, which on a scratch
  -- buffer renders as nothing at all. The window has no other place to say
  -- where the signature came from.
  it("shows the origin path it was handed", function()
    local ofp = require("lsp.tools.lsp_signature.open_floating_preview")
    local _, win = ofp({ "foo(a, b)" }, { footer = "/src/pkg/mod.lua" })

    assert.is_not_nil(win)
    local title = api.nvim_win_get_config(win).title
    assert.is_not_nil(title, "the preview opened without a border title")
    assert.are.equal("/src/pkg/mod.lua", title[1][1])
    assert.are.equal("%=/src/pkg/mod.lua%=", api.nvim_get_option_value("statusline", { win = win }))
  end)

  -- `nvim_create_buf` signals failure by returning 0, and 0 is not an invalid
  -- handle -- it aliases the *current* buffer. An unchecked failure here
  -- would retarget every following `nvim_buf_*`/`nvim_open_win` call in this
  -- function at whatever buffer the user is editing (LUA-11).
  it("returns nil instead of retargeting the current buffer when nvim_create_buf fails", function()
    local ofp = require("lsp.tools.lsp_signature.open_floating_preview")
    local scratch = source_buffer("do not touch me")
    local before = api.nvim_buf_get_lines(scratch, 0, -1, false)

    local real_create_buf = api.nvim_create_buf
    ---@diagnostic disable-next-line: duplicate-set-field
    api.nvim_create_buf = function()
      return 0
    end

    local buf, win
    assert.has_no.errors(function()
      buf, win = ofp({ "foo(a, b)" })
    end)

    api.nvim_create_buf = real_create_buf

    assert.is_nil(buf)
    assert.is_nil(win)
    assert.are.same(before, api.nvim_buf_get_lines(scratch, 0, -1, false))
  end)

  -- `format_signature_help` accepts a result whose payload sits under
  -- `result.value`; the caller then read `result.signatures` directly, which
  -- is nil for exactly that shape. Measured: "attempt to index field
  -- 'signatures' (a nil value)" out of a `vim.schedule` callback, after the
  -- window was already open -- so the popup stood there while focusing it and
  -- the caller's callback, both further down the same callback, never ran.
  it("finishes the popup when the payload arrives under `value`", function()
    local bufnr = source_buffer("local x = foo(1, 2)")
    vim.lsp.get_clients = function()
      return {
        signature_client({
          value = {
            signatures = { { label = "foo(a, b)", parameters = { { label = { 4, 5 } } } } },
            activeSignature = 0,
          },
        }),
      }
    end

    local done = false
    request_and_show()(bufnr, function()
      done = true
    end)
    settle(function()
      return done
    end)

    assert.is_true(done, "the callback never ran: the scheduled work died halfway")
  end)

  -- `activeParameter` lives on the result in the base protocol. Only the
  -- per-signature field was read, so for the shape servers actually send the
  -- active index came out nil and the loop below defaulted to 1: measured on
  -- `foo(a, |b)`, the extmarks were `LspSignatureActiveParam` over `a` and
  -- `LspSignatureParam2` over `b` -- the emphasis pointing at the parameter
  -- the user had already finished typing.
  it("emphasises the parameter the server called active", function()
    local bufnr = source_buffer("local x = foo(1, 2)")
    vim.lsp.get_clients = function()
      return { signature_client(result_level_active()) }
    end

    local state = require("lsp.tools.lsp_signature.state")
    local shown = false
    request_and_show()(bufnr, function()
      shown = true
    end)
    settle(function()
      return shown
    end)
    assert.is_true(shown, "no popup")

    ---@type table<string, string>
    local group_at = {}
    for _, ns in pairs(api.nvim_get_namespaces()) do
      for _, mark in
        ipairs(api.nvim_buf_get_extmarks(state.current.buf, ns, 0, -1, {
          details = true,
        }))
      do
        -- `foo(a, b)`: `a` starts at byte 4, `b` at byte 7.
        group_at[tostring(mark[3])] = mark[4] and mark[4].hl_group
      end
    end

    assert.are.equal("LspSignatureActiveParam", group_at["7"], "`b` is the active parameter")
    assert.are_not.equal(
      "LspSignatureActiveParam",
      group_at["4"],
      "`a` was emphasised as if it were the active parameter"
    )
  end)

  -- The column in a position parameter is counted in the encoding the client
  -- negotiated, and "utf-8" was hardcoded. Measured on the line below with the
  -- cursor inside the call: character 26 sent, character 23 meant -- three
  -- columns past the call, where the server has nothing to say.
  it("asks in the offset encoding the client negotiated", function()
    local bufnr = source_buffer('local x = "äöü" .. foo()')
    local asked
    vim.lsp.get_clients = function()
      return {
        {
          id = 1,
          name = "utf16ls",
          offset_encoding = "utf-16",
          server_capabilities = { signatureHelpProvider = {} },
          request = function(_self, _method, params, handler)
            asked = params.position.character
            handler(nil, nil)
            return true, 1
          end,
        },
      }
    end

    request_and_show()(bufnr)
    settle(function()
      return asked ~= nil
    end)

    local expected = vim.lsp.util.make_position_params(0, "utf-16").position.character
    assert.are.equal(expected, asked)
  end)

  describe("show_hover", function()
    ---@return table
    local function hover_module()
      package.loaded["lsp.tools.lsp_signature.show_hover"] = nil
      local mod = require("lsp.tools.lsp_signature.show_hover")
      mod.clear_cache()
      return mod
    end

    --- A `textDocument/hover` answer, which is what `show_hover` asks for.
    ---
    --- This used to return `{ signatures = ... }` -- a `signatureHelp` result,
    --- the shape `format_hover` was written to parse and the shape no server
    --- sends in reply to a hover request. The cases below therefore passed
    --- against a formatter that returned nil for every answer it could really
    --- receive, and the feature they cover could not work: the test agreed with
    --- the bug instead of catching it. Anything asserting popup mechanics here
    --- needs a result the formatter accepts, so it has to be a real one.
    ---@return table
    local function hover_result()
      return { contents = { kind = "markdown", value = "foo(a, b)" } }
    end

    ---@param bufnr integer
    ---@return table
    local function params_for(bufnr)
      return {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        position = { line = 0, character = 4 },
      }
    end

    -- Two presses of `<C-b>` before the first answer is back, which is what a
    -- toggle on a slow server invites. Both answers presented, and `state`
    -- holds one window: measured, `nvim_list_wins()` ended with two floats
    -- `{1003, 1002}` while `state` knew only 1003, and closing the popup left
    -- 1002 on screen. Its only closer is an autocommand on its own buffer,
    -- which cannot fire while that buffer is the one being displayed.
    it("leaves one popup behind when two requests were in flight", function()
      local mod = hover_module()
      local bufnr = source_buffer("local x = foo(1, 2)")
      local pending = {}
      local client = {
        id = 1,
        request = function(_self, _method, _params, handler)
          pending[#pending + 1] = handler
          return true, #pending
        end,
      }

      mod.show_hover({ client }, params_for(bufnr), { mode = "i", bufnr = bufnr })
      mod.show_hover({ client }, params_for(bufnr), { mode = "i", bufnr = bufnr })
      assert.are.equal(2, #pending, "both presses should have reached the client")

      for _, handler in ipairs(pending) do
        handler(nil, hover_result())
      end
      settle(function()
        return #floats() > 0
      end)
      vim.wait(80, function()
        return false
      end)

      assert.are.equal(1, #floats(), "a second popup was stacked on the first")

      require("lsp.tools.lsp_signature.state").close()
      assert.are.equal(0, #floats(), "the toggle could not reach the popup it left behind")
    end)

    -- The clients used to be asked one at a time, the next one only once the
    -- previous had answered. A client that does not answer therefore ends the
    -- search at itself. Measured with the second client holding the hover
    -- text: it was asked 0 times in all three shapes below, no popup opened,
    -- and `show_hover` still returned true.
    for _, case in ipairs({
      {
        name = "raises from `request` (a client that is shutting down)",
        request = function()
          error("client is shutting down")
        end,
      },
      {
        name = "returns false (a server that is not ready)",
        request = function()
          return false
        end,
      },
      {
        name = "accepts the request and never answers",
        request = function()
          return true, 1
        end,
      },
    }) do
      it("asks the other client when the first one " .. case.name, function()
        local mod = hover_module()
        local bufnr = source_buffer("local x = foo(1, 2)")
        local asked = 0
        local mute = { id = 7, request = case.request }
        local answering = {
          id = 8,
          request = function(_self, _method, _params, handler)
            asked = asked + 1
            handler(nil, hover_result())
            return true, 1
          end,
        }

        mod.show_hover({ mute, answering }, params_for(bufnr), { mode = "i", bufnr = bufnr })
        settle(function()
          return #floats() > 0
        end)

        assert.are.equal(1, asked, "the client with the answer was never asked")
        assert.are.equal(1, #floats(), "no popup, although one client had hover text")
      end)
    end

    -- The module documents a normal-mode popup that "takes focus, so it can be
    -- scrolled and copied from". The hover path called the preview with no
    -- options at all, so it came out `focusable = false` -- unreachable by
    -- `wincmd` or by the mouse, in every mode. The signature path next door
    -- has always passed `focus`.
    it("opens a focusable popup in normal mode", function()
      local mod = hover_module()
      local bufnr = source_buffer("local x = foo(1, 2)")
      local client = {
        id = 1,
        request = function(_self, _method, _params, handler)
          handler(nil, hover_result())
          return true, 1
        end,
      }

      mod.show_hover({ client }, params_for(bufnr), { mode = "n", bufnr = bufnr })
      settle(function()
        return #floats() > 0
      end)

      local win = require("lsp.tools.lsp_signature.state").current.win
      assert.is_not_nil(win)
      assert.is_true(
        api.nvim_win_get_config(win).focusable,
        "the normal-mode popup cannot be focused"
      )
    end)
  end)
end)

describe("lsp.tools.lsp_signature.format_hover", function()
  -- `show_hover` sends `textDocument/hover`. The formatter read
  -- `result.signatures`, which is a `signatureHelp` field, so it returned nil
  -- for every answer it could actually be given -- the documented hover
  -- fallback, and the LRU cache built to make it cheap, were both unreachable.
  local format_hover = require("lsp.tools.lsp_signature.format_hover")

  it("formats every shape the protocol allows for Hover.contents", function()
    -- All three return nil against the previous formatter.
    assert.are.same(
      { "plain hover text" },
      format_hover({ contents = "plain hover text" }),
      "MarkedString as a bare string"
    )
    assert.are.same(
      { "**bold** docs" },
      format_hover({ contents = { kind = "markdown", value = "**bold** docs" } }),
      "MarkupContent"
    )
    assert.are.same(
      { "f()", "and prose" },
      format_hover({ contents = { { language = "lua", value = "f()" }, "and prose" } }),
      "MarkedString[]"
    )
  end)

  it("drops the code fences, because the popup renders plain text", function()
    -- `open_floating_preview` sets filetype `lsp_signature` and runs no
    -- markdown stylizer, so a fence would reach the reader as backticks.
    local lines = format_hover({
      contents = { kind = "markdown", value = "head\n\n```lua\nlocal x = 1\n```\n\ntail" },
    })
    assert.are.same({ "head", "", "local x = 1", "", "tail" }, lines)
  end)

  it("returns nil rather than an empty list when there is nothing to show", function()
    assert.is_nil(format_hover(nil))
    assert.is_nil(format_hover({}), "no contents")
    assert.is_nil(format_hover({ contents = "" }), "empty contents")
    assert.is_nil(format_hover("not a table"))
  end)

  it("no longer answers a signatureHelp result, which is the other module's job", function()
    -- The only shape the old formatter handled, and the one nothing sends here.
    -- `format_signature_help` covers it.
    assert.is_nil(format_hover({ signatures = { { label = "foo(a)" } } }))
  end)

  it("opens a popup for a real hover answer", function()
    -- End to end, and red against the previous formatter: `show_hover` returned
    -- true while no window was ever created, so the caller waited for something
    -- that was not coming.
    package.loaded["lsp.tools.lsp_signature.show_hover"] = nil
    local mod = require("lsp.tools.lsp_signature.show_hover")
    mod.clear_cache()

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 1" })

    local client = {
      id = 91,
      request = function(_self, method, _params, handler)
        if method ~= "textDocument/hover" then
          return false
        end
        vim.schedule(function()
          handler(nil, { contents = { kind = "markdown", value = "hover works" } })
        end)
        return true, 1
      end,
    }

    local shown
    local sent = mod.show_hover({ client }, {
      textDocument = { uri = vim.uri_from_bufnr(bufnr) },
      position = { line = 0, character = 0 },
    }, {
      mode = "i",
      bufnr = bufnr,
      callback = function(b, w)
        shown = { buf = b, win = w }
      end,
    })

    assert.is_true(sent, "the client accepted the request")
    vim.wait(2000, function()
      return shown ~= nil
    end, 10)
    assert.is_not_nil(shown, "a popup was opened")
    assert.are.same({ "hover works" }, vim.api.nvim_buf_get_lines(shown.buf, 0, -1, false))

    require("lsp.tools.lsp_signature.state").close()
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end)
end)

describe("lsp.tools.lsp_signature.format_signature_help", function()
  -- `signatures`, `parameters` and every other optional field in the
  -- `signatureHelp` protocol are all legal to send as JSON `null`, which
  -- decodes to `vim.NIL` -- userdata, not Lua `nil`. Both sites this module
  -- reads such a field with a plain truthiness check used to index or
  -- length-check the userdata directly and raise.
  local format_signature_help = require("lsp.tools.lsp_signature.format_signature_help")

  it("returns nil rather than raising on a vim.NIL signatures (LUA-16)", function()
    assert.has_no.errors(function()
      assert.is_nil(format_signature_help({ signatures = vim.NIL }))
    end)
  end)

  it("still finds signatures under result.value when result.signatures is vim.NIL", function()
    local lines = format_signature_help({
      signatures = vim.NIL,
      value = {
        signatures = { { label = "foo(a, b)" } },
      },
    })
    assert.are.same({ "foo(a, b)" }, lines)
  end)

  it("does not raise when the `value` envelope itself is vim.NIL (LUA-16)", function()
    -- `result.value` is the wrapped-result envelope some servers use; it is
    -- itself legal to send as JSON `null`. `result.value and
    -- result.value.signatures` does not guard that -- `vim.NIL` is truthy in
    -- Lua -- so this used to index the userdata directly and raise.
    assert.has_no.errors(function()
      assert.is_nil(format_signature_help({ value = vim.NIL }))
    end)
  end)

  it("does not raise on a vim.NIL parameters with a numeric activeParameter (LUA-16)", function()
    local lines, hl
    assert.has_no.errors(function()
      lines, hl = format_signature_help({
        signatures = { { label = "foo(a, b)", parameters = vim.NIL } },
        activeSignature = 0,
        activeParameter = 0,
      })
    end)
    assert.are.same({ "foo(a, b)" }, lines)
    assert.is_nil(hl, "no highlight to compute without real parameters")
  end)
end)
