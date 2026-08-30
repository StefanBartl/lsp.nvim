--- Covers `lsp.usercmds.start.get_servers_for_buffer` and the enumeration in
--- `lsp.core.supervisor` it is built on.
---
--- This function is not a convenience: `lspdoctor/health` calls it for the
--- expected-server list that `:LspDoctor startup` reports and that `:Lsp
--- recover` starts from, so whatever it answers is what those two believe. It
--- used to answer from a hardcoded table of seventeen filetypes that named
--- five servers this plugin does not configure and missed ones it does; every
--- filetype outside the seventeen got "no LSP configured" whatever was running.
---
--- Real `vim.lsp.config` registrations rather than stubs, because the point is
--- that the answer comes from the same place `vim.lsp.enable` attaches from.
--- Nothing is started: the configs name a command that is never run.

describe("lsp.usercmds.start", function()
  ---@return table start, table supervisor
  local function reload()
    package.loaded["lsp.core.supervisor"] = nil
    package.loaded["lsp.usercmds.start"] = nil
    return (require("lsp.usercmds.start")), (require("lsp.core.supervisor"))
  end

  ---@param ft string
  ---@return integer bufnr
  local function buffer_of(ft)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = ft
    return bufnr
  end

  before_each(function()
    vim.lsp.config("spec_go", { cmd = { "true" }, filetypes = { "go" } })
    vim.lsp.config("spec_golint", { cmd = { "true" }, filetypes = { "go", "gomod" } })
    vim.lsp.config("spec_lua", { cmd = { "true" }, filetypes = { "lua" } })
    vim.lsp.config("spec_never_enabled", { cmd = { "true" }, filetypes = { "go" } })
    vim.lsp.config("*", { capabilities = {} })
    vim.lsp.enable("spec_go")
    vim.lsp.enable("spec_golint")
    vim.lsp.enable("spec_lua")
  end)

  describe("get_servers_for_buffer", function()
    it("returns every enabled server that declares the filetype", function()
      local start = reload()

      local names = start.get_servers_for_buffer(buffer_of("go"))
      table.sort(names)

      assert.are.same({ "spec_go", "spec_golint" }, names)
    end)

    it("does not return a server declared for a different filetype", function()
      local start = reload()

      assert.are.same({ "spec_lua" }, start.get_servers_for_buffer(buffer_of("lua")))
    end)

    -- The old hardcoded table answered "no LSP configured" for every filetype
    -- outside its seventeen, which is a different statement from "none
    -- declares this one" and was usually wrong.
    it("returns nothing for a filetype no config declares", function()
      local start = reload()

      assert.are.same({}, start.get_servers_for_buffer(buffer_of("rust")))
    end)

    it("returns nothing for a buffer with no filetype", function()
      local start = reload()

      assert.are.same({}, start.get_servers_for_buffer(buffer_of("")))
    end)

    -- A config the plugin registered but never enabled is not something this
    -- buffer should expect, and `:Lsp recover` must not try to start it.
    it("leaves out a config that was registered but never enabled", function()
      local start = reload()

      local names = start.get_servers_for_buffer(buffer_of("go"))
      assert.is_false(vim.tbl_contains(names, "spec_never_enabled"))
    end)

    it("matches a secondary filetype of a multi-filetype config", function()
      local start = reload()

      assert.are.same({ "spec_golint" }, start.get_servers_for_buffer(buffer_of("gomod")))
    end)
  end)

  describe("supervisor.registered_names", function()
    it("lists the enabled configs and skips the shared base config", function()
      local _, supervisor = reload()

      local names = supervisor.registered_names()

      assert.is_true(vim.tbl_contains(names, "spec_go"))
      assert.is_true(vim.tbl_contains(names, "spec_lua"))
      -- `"*"` is the base every named config is merged from, not a server.
      assert.is_false(vim.tbl_contains(names, "*"))
      assert.is_false(vim.tbl_contains(names, "spec_never_enabled"))
    end)

    it("is sorted, so callers and reports are stable", function()
      local _, supervisor = reload()

      local names = supervisor.registered_names()
      local sorted = vim.deepcopy(names)
      table.sort(sorted)

      assert.are.same(sorted, names)
    end)
  end)
end)
