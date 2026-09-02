--- Covers the winbar depth cap in `lsp.integrations.lspsaga`: the part that
--- rewrites what lspsaga already drew, so the breadcrumb in a Markdown buffer
--- stops at the file's own top heading instead of walking the whole heading
--- hierarchy the cursor happens to sit inside.
---
--- The cap is a string operation on lspsaga's output, which makes exactly one
--- thing worth pinning down: what counts as a part. The winbar is
--- `folder_level + 1` path items and then the symbols, all joined by the same
--- separator, and the separator comes from lspsaga's live config -- so a cap
--- that assumed the default separator would quietly trim nothing for anyone
--- who changed it, which looks identical to "there was nothing to trim".
---
--- lspsaga itself is stubbed. The cases here are about the arithmetic, and a
--- real lspsaga would need a language server to produce a single symbol.

describe("lsp.integrations.lspsaga winbar depth", function()
  ---@return table
  local function reload()
    package.loaded["lsp.integrations.lspsaga"] = nil
    return require("lsp.integrations.lspsaga")
  end

  --- Run `fn` with lspsaga's config replaced by `cfg`.
  ---@param cfg table|nil # nil stands in for a lspsaga that never ran `setup`
  ---@param fn fun(): nil
  ---@return nil
  local function with_saga(cfg, fn)
    local original = package.loaded["lspsaga"]
    package.loaded["lspsaga"] = cfg and { config = { symbol_in_winbar = cfg } } or {}
    local ok, err = pcall(fn)
    package.loaded["lspsaga"] = original
    if not ok then
      error(err, 0)
    end
  end

  --- A window showing an empty buffer of filetype `ft`, with `line` as its
  --- winbar.
  ---@param ft string
  ---@param line string
  ---@return integer win
  local function window(ft, line)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = ft
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    vim.wo[win].winbar = line
    return win
  end

  ---@param sep string
  ---@param parts string[]
  ---@return string
  local function bar(sep, parts)
    return table.concat(parts, "%#SagaSep#" .. sep .. "%*")
  end

  local DEFAULT = { enable = true, show_file = true, folder_level = 1, separator = " > " }

  after_each(function()
    vim.wo[vim.api.nvim_get_current_win()].winbar = ""
  end)

  it("cuts a markdown breadcrumb down to folder, file and one heading", function()
    local saga = reload()
    local win = window("markdown", bar(" > ", { "docs", "notes.md", "H1", "H2", "H3" }))

    with_saga(DEFAULT, function()
      saga.trim_winbar(win)
    end)

    assert.are.equal(bar(" > ", { "docs", "notes.md", "H1" }), vim.wo[win].winbar)
  end)

  it("leaves a filetype without a cap alone", function()
    local saga = reload()
    local line = bar(" > ", { "lua", "init.lua", "M.setup", "inner" })
    local win = window("lua", line)

    with_saga(DEFAULT, function()
      saga.trim_winbar(win)
    end)

    assert.are.equal(line, vim.wo[win].winbar)
  end)

  it("leaves a breadcrumb that is already short enough alone", function()
    local saga = reload()
    local line = bar(" > ", { "docs", "notes.md" })
    local win = window("markdown", line)

    with_saga(DEFAULT, function()
      saga.trim_winbar(win)
    end)

    assert.are.equal(line, vim.wo[win].winbar)
  end)

  it("counts the path items lspsaga was told to draw, not one", function()
    local saga = reload()
    local win = window("markdown", bar(" > ", { "src", "docs", "notes.md", "H1", "H2" }))

    with_saga({ enable = true, show_file = true, folder_level = 2, separator = " > " }, function()
      saga.trim_winbar(win)
    end)

    assert.are.equal(bar(" > ", { "src", "docs", "notes.md", "H1" }), vim.wo[win].winbar)
  end)

  it("counts no path items when lspsaga draws none", function()
    local saga = reload()
    local win = window("markdown", bar(" > ", { "H1", "H2", "H3" }))

    with_saga({ enable = true, show_file = false, folder_level = 1, separator = " > " }, function()
      saga.trim_winbar(win)
    end)

    assert.are.equal("H1", vim.wo[win].winbar)
  end)

  it("splits on the configured separator, not the default one", function()
    local saga = reload()
    local win = window("markdown", bar(" | ", { "docs", "notes.md", "H1", "H2" }))

    with_saga({ enable = true, show_file = true, folder_level = 1, separator = " | " }, function()
      saga.trim_winbar(win)
    end)

    assert.are.equal(bar(" | ", { "docs", "notes.md", "H1" }), vim.wo[win].winbar)
  end)

  it("takes the caps it is given and restores the default", function()
    local saga = reload()
    saga.set_winbar_max_symbols({ lua = 0 })
    local win = window("lua", bar(" > ", { "lua", "init.lua", "M.setup" }))

    with_saga(DEFAULT, function()
      saga.trim_winbar(win)
    end)
    assert.are.equal(bar(" > ", { "lua", "init.lua" }), vim.wo[win].winbar)

    saga.set_winbar_max_symbols(nil)
    assert.are.equal(1, saga.winbar_max_symbols.markdown)
  end)

  it("does nothing when lspsaga carries no winbar config", function()
    local saga = reload()
    local line = bar(" > ", { "docs", "notes.md", "H1", "H2" })
    local win = window("markdown", line)

    with_saga(nil, function()
      saga.trim_winbar(win)
    end)

    assert.are.equal(line, vim.wo[win].winbar)
  end)

  it("does nothing for a window that is gone", function()
    local saga = reload()
    assert.has_no.errors(function()
      with_saga(DEFAULT, function()
        saga.trim_winbar(999999)
      end)
    end)
  end)
end)
