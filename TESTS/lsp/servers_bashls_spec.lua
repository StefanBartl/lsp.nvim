--- Covers the one thing about `lsp.servers.bashls` that is easy to break by
--- accident: *when* the shellcheck path is resolved.
---
--- `vim.fn.exepath()` for a binary that is not installed walks every PATH entry
--- against every PATHEXT suffix on Windows and caches nothing -- 25-200ms,
--- measured, paid by every startup that never opens a shell script. Moving it
--- into `before_init` only helps as long as it stays there, and only works
--- because the hook writes into the settings table the client already captured.

describe("lsp.servers.bashls", function()
  ---@return table
  local function server()
    package.loaded["lsp.servers.bashls"] = nil
    return require("lsp.servers.bashls")
  end

  --- The registered config, without touching the global enable machinery.
  ---@return table
  local function register()
    vim.lsp.config._configs["bashls"] = nil
    server().setup({}, { enable = false })
    return vim.lsp.config["bashls"]
  end

  it("registers the server without probing for shellcheck", function()
    local cfg = register()
    assert.are.equal("table", type(cfg))
    assert.are.equal("table", type(cfg.settings.bashIde))
    assert.is_nil(
      cfg.settings.bashIde.shellcheckPath,
      "shellcheckPath must not be resolved while the config is being registered"
    )
    assert.are.equal("function", type(cfg.before_init))
  end)

  it("keeps the settings bashls actually needs", function()
    local ide = register().settings.bashIde
    assert.is_true(ide.includeAllWorkspaceSymbols)
    assert.are.equal("*@(.sh|.inc|.bash|.zsh|.ksh|.mksh)", ide.globPattern)
    assert.are.same({ server = "off" }, ide.trace)
  end)

  it("before_init fills shellcheckPath into the table the client captured", function()
    local cfg = vim.deepcopy(register())
    -- What vim.lsp.Client.create() does: it stores this reference as
    -- `self.settings` *before* before_init runs, and sends that reference in
    -- workspace/didChangeConfiguration. A hook that reassigned config.settings
    -- would be silently dropped; this one has to be visible here.
    local captured = cfg.settings

    cfg.before_init({}, cfg)

    assert.are.equal("string", type(captured.bashIde.shellcheckPath))
    assert.are.equal(vim.fn.exepath("shellcheck"), captured.bashIde.shellcheckPath)
  end)

  it("survives settings the caller replaced with something else", function()
    local mod = server()
    local cfg = { settings = nil }
    assert.has_no.errors(function()
      mod._before_init({}, cfg)
    end)
  end)
end)
