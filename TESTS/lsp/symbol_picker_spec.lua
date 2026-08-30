--- Covers `lsp.tools.ts_type_lookup.symbol_picker`: that `:TypeDefPick` asks
--- fzf-lua the right question, and what it does when it cannot ask.
---
--- The question is the part worth pinning. fzf-lua's `lsp_workspace_symbols`
--- takes two options that both look like "the query": `lsp_query` is what goes
--- to the server in `workspace/symbol`, `query` is the filter applied to what
--- came back. Passing the second would ask the server for *everything* and
--- then filter locally -- which works on a small project and falls over on a
--- large one, i.e. exactly where it would not be noticed until it mattered.
---
--- fzf-lua is stubbed: the picker opens a terminal UI, and what is under test
--- is the call, not the window.

describe("lsp.tools.ts_type_lookup.symbol_picker", function()
  ---@return table picker, table calls
  local function reload(fzf)
    local calls = {}
    if fzf ~= false then
      package.loaded["fzf-lua"] = {
        lsp_workspace_symbols = function(opts)
          calls[#calls + 1] = opts
        end,
      }
    else
      package.loaded["fzf-lua"] = nil
      -- Make `require("fzf-lua")` fail even where the plugin is installed, so
      -- the case tests the missing-dependency path rather than the machine.
      package.preload["fzf-lua"] = function()
        error("fzf-lua not installed")
      end
    end
    package.loaded["lsp.tools.ts_type_lookup.symbol_picker"] = nil
    return (require("lsp.tools.ts_type_lookup.symbol_picker")), calls
  end

  after_each(function()
    package.loaded["fzf-lua"] = nil
    package.preload["fzf-lua"] = nil
    package.loaded["lsp.tools.ts_type_lookup.symbol_picker"] = nil
  end)

  it("sends the argument as the server-side query", function()
    local picker, calls = reload()

    assert.is_true(picker.pick("MyType"))
    assert.are.equal(1, #calls)
    assert.are.equal("MyType", calls[1].lsp_query)
  end)

  -- `query` would be fzf's own filter over a full workspace dump. Asserting
  -- its absence is the point: both options exist and only one is right.
  it("does not pass it as fzf's local filter instead", function()
    local picker, calls = reload()

    picker.pick("MyType")

    assert.is_nil(calls[1].query)
  end)

  it("falls back to the word under the cursor", function()
    local picker, calls = reload()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "SomeSymbolHere" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    assert.is_true(picker.pick(nil))
    assert.are.equal("SomeSymbolHere", calls[1].lsp_query)
  end)

  it("treats an empty string as no argument", function()
    local picker, calls = reload()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "FromCword" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    picker.pick("")

    assert.are.equal("FromCword", calls[1].lsp_query)
  end)

  it("asks nothing when there is no symbol and no argument", function()
    local picker, calls = reload()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    assert.is_false(picker.pick(nil))
    assert.are.equal(0, #calls)
  end)

  -- Soft dependency: the plugin sets this command up unconditionally, so a
  -- machine without fzf-lua must get a message rather than a stack trace.
  it("says so rather than raising when fzf-lua is absent", function()
    local picker, calls = reload(false)

    assert.is_false(picker.pick("MyType"))
    assert.are.equal(0, #calls)
  end)
end)
