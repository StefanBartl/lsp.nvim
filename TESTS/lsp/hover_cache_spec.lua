--- Covers the hover cache in `lsp.tools.lsp_signature.show_hover`.
---
--- The cache is only worth having if it is right about *when* an answer is
--- still the answer, so these cases are mostly about the key: an edit, a
--- different position and a restarted client each have to miss, and only a
--- genuine repeat may hit. A cache that hits too often shows stale hover text
--- for a line that has since changed, which is worse than the roundtrip it
--- saves.
---
--- The clients are stubs. A real one would need a real server, and the
--- question here is not whether hover works -- it is whether the second press
--- of `<C-b>` reaches the wire.

describe("lsp.tools.lsp_signature.show_hover", function()
  local requests

  ---@return table
  local function fresh()
    requests = 0

    package.loaded["lsp.tools.lsp_signature.open_floating_preview"] = function(_lines)
      -- Fake handles: they only have to be truthy and to fail
      -- `nvim_win_is_valid`, so nothing tries to focus a window that is not
      -- there.
      return 9001, 9002
    end
    package.loaded["lsp.tools.lsp_signature.format_hover"] = function(_result)
      return { "hover line" }
    end

    package.loaded["lsp.tools.lsp_signature.show_hover"] = nil
    return require("lsp.tools.lsp_signature.show_hover")
  end

  ---@param id integer
  ---@return table
  local function client(id)
    return {
      id = id,
      request = function(_self, _method, _params, handler, _bufnr)
        requests = requests + 1
        handler(nil, { contents = "anything" })
        return true, 1
      end,
    }
  end

  ---@param line integer
  ---@param character integer
  ---@return table
  local function params_at(line, character)
    return {
      textDocument = { uri = "file:///probe.lua" },
      position = { line = line, character = character },
    }
  end

  ---@return integer
  local function scratch()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 1" })
    return bufnr
  end

  --- One hover, run to completion: the preview is opened from a scheduled
  --- callback, so the cache is not written until the loop has turned.
  ---@param mod table
  ---@param clients table[]
  ---@param bufnr integer
  ---@param params table
  ---@return nil
  local function hover(mod, clients, bufnr, params)
    local shown = false
    mod.show_hover(clients, params, {
      bufnr = bufnr,
      callback = function()
        shown = true
      end,
    })
    vim.wait(200, function()
      return shown
    end, 5)
    assert.is_true(shown, "no preview was opened")
  end

  after_each(function()
    package.loaded["lsp.tools.lsp_signature.open_floating_preview"] = nil
    package.loaded["lsp.tools.lsp_signature.format_hover"] = nil
    package.loaded["lsp.tools.lsp_signature.show_hover"] = nil
  end)

  it("answers a repeat on an unchanged buffer without a request", function()
    local mod = fresh()
    local bufnr, clients, params = scratch(), { client(1) }, params_at(0, 4)

    hover(mod, clients, bufnr, params)
    assert.are.equal(1, requests)

    hover(mod, clients, bufnr, params)
    assert.are.equal(1, requests)
  end)

  it("asks again after the buffer changed", function()
    local mod = fresh()
    local bufnr, clients, params = scratch(), { client(1) }, params_at(0, 4)

    hover(mod, clients, bufnr, params)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 2" })
    hover(mod, clients, bufnr, params)

    assert.are.equal(2, requests)
  end)

  it("asks again for a different position in the same buffer", function()
    local mod = fresh()
    local bufnr, clients = scratch(), { client(1) }

    hover(mod, clients, bufnr, params_at(0, 4))
    hover(mod, clients, bufnr, params_at(0, 9))

    assert.are.equal(2, requests)
  end)

  -- The reason the client ids are in the key: a restart leaves the buffer
  -- untouched, so `changedtick` alone would keep serving the answer the old
  -- server gave.
  it("asks again once the client has been replaced", function()
    local mod = fresh()
    local bufnr, params = scratch(), params_at(0, 4)

    hover(mod, { client(1) }, bufnr, params)
    hover(mod, { client(2) }, bufnr, params)

    assert.are.equal(2, requests)
  end)

  it("asks again after the cache is cleared", function()
    local mod = fresh()
    local bufnr, clients, params = scratch(), { client(1) }, params_at(0, 4)

    hover(mod, clients, bufnr, params)
    mod.clear_cache()
    hover(mod, clients, bufnr, params)

    assert.are.equal(2, requests)
  end)

  -- A position-less request cannot be keyed, and guessing a key would collapse
  -- two different questions onto one answer. It has to stay uncached.
  it("caches nothing when the params carry no position", function()
    local mod = fresh()
    local bufnr, clients = scratch(), { client(1) }
    local params = { textDocument = { uri = "file:///probe.lua" } }

    hover(mod, clients, bufnr, params)
    hover(mod, clients, bufnr, params)

    assert.are.equal(2, requests)
  end)
end)
