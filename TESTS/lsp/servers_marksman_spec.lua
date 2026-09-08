--- Covers the guard that stops Marksman from ever being started for a
--- buffer with no real backing file. `buftype ~= ""` scratch/preview buffers
--- -- e.g. mdview.nvim's read-only tab preview, `filetype = "markdown"` on a
--- synthetic name like `[mdview preview] foo.md (12)` -- produce a `file://`
--- URI Marksman's .NET URI parser rejects ("Invalid URI: The hostname could
--- not be parsed."), crashing the server on `textDocument/didOpen`.

describe("lsp.servers.marksman", function()
  ---@return table
  local function server()
    package.loaded["lsp.servers.marksman"] = nil
    return require("lsp.servers.marksman")
  end

  --- The registered config, without touching the global enable machinery.
  ---@return table
  local function register()
    ---@diagnostic disable-next-line: invisible
    vim.lsp.config._configs["marksman"] = nil
    server().setup({}, { enable = false })
    return vim.lsp.config["marksman"]
  end

  it("registers root_dir as a function", function()
    local cfg = register()
    assert.are.equal("function", type(cfg.root_dir))
  end)

  it("does not call on_dir for a buffer with no real backing file", function()
    local root_dir = register().root_dir
    local bufnr = vim.api.nvim_create_buf(false, true) -- buftype=nofile
    vim.bo[bufnr].buftype = "nofile"

    local called = false
    root_dir(bufnr, function()
      called = true
    end)

    assert.is_false(called, "on_dir must not be called for a buftype ~= '' buffer")
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("calls on_dir with a resolved root for a normal file buffer", function()
    local root_dir = register().root_dir
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.getcwd() .. "/TESTS/lsp/servers_marksman_spec.lua")

    local resolved
    root_dir(bufnr, function(root)
      resolved = root
    end)

    assert.are.equal("string", type(resolved))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
