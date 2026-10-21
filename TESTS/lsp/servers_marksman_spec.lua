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

--- marksman reads a link target without `./` as a workspace-wide path suffix:
--- `[x](Replies/a.md)` in a case's own `State.md` is "Ambiguous link to
--- document" as soon as another case has a `Replies/a.md` too, while
--- `./Replies/a.md` is clean (measured against marksman). The filter drops the
--- message when the target exists relative to the document.
describe("lsp.servers.marksman.diagnostics_handler: ambiguous relative links", function()
  local handler = require("lsp.servers.marksman.diagnostics_handler")
  local cfg = require("lsp.servers.marksman.config")

  ---@param message string
  ---@return table
  local function diag(message)
    return {
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 1 } },
      severity = 1,
      message = message,
    }
  end

  ---@type string
  local root, uri
  before_each(function()
    root = vim.fs.normalize(vim.fn.tempname())
    for _, case in ipairs({ "A", "B" }) do
      vim.fn.mkdir(root .. "/Cases/" .. case .. "/Replies", "p")
      vim.fn.writefile({ "# pso" }, root .. "/Cases/" .. case .. "/Replies/00_PSO.md")
    end
    vim.fn.writefile({ "# state" }, root .. "/Cases/A/State.md")
    uri = vim.uri_from_fname(root .. "/Cases/A/State.md")
  end)
  after_each(function()
    vim.fn.delete(root, "rf")
    cfg.resolve_ambiguous_relative = true
  end)

  ---@param message string
  ---@param doc_uri? string
  ---@return integer kept
  local function kept(message, doc_uri)
    return #handler.filter_diagnostics({ diag(message) }, false, doc_uri)
  end

  it("drops it when the target exists relative to the document", function()
    assert.are.equal(0, kept("Ambiguous link to document 'Replies/00_PSO.md'", uri))
  end)

  it("also with an anchor and a percent-encoded name", function()
    vim.fn.writefile({ "# x" }, root .. "/Cases/A/Replies/My Reply.md")
    vim.fn.writefile({ "# x" }, root .. "/Cases/B/Replies/My Reply.md")
    assert.are.equal(0, kept("Ambiguous link to document 'Replies/My%20Reply.md#top'", uri))
  end)

  it("keeps it when the target is not there relative to the document", function()
    assert.are.equal(1, kept("Ambiguous link to document 'Other/00_PSO.md'", uri))
  end)

  it("keeps it without a document to resolve against", function()
    assert.are.equal(1, kept("Ambiguous link to document 'Replies/00_PSO.md'", nil))
  end)

  it("keeps a root-relative target", function()
    assert.are.equal(1, kept("Ambiguous link to document '/Replies/00_PSO.md'", uri))
  end)

  it("leaves other messages alone", function()
    assert.are.equal(1, kept("Ambiguous link to document heading 'x'", uri))
  end)

  it("keeps it with resolve_ambiguous_relative = false", function()
    cfg.resolve_ambiguous_relative = false
    assert.are.equal(1, kept("Ambiguous link to document 'Replies/00_PSO.md'", uri))
  end)
end)
