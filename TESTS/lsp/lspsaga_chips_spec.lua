--- Covers `lsp.integrations.lspsaga_chips`: the rewrite that turns lspsaga's
--- flat breadcrumb string into rounded chips.
---
--- It is a string operation, so the cases are about what survives it: which
--- role a part gets, that the separator between parts is left byte for byte
--- as lspsaga wrote it (`trim_winbar` splits on it afterwards), that a second
--- pass changes nothing, and that every `%#Group#` inside a chip is replaced
--- by one that has a background -- one that has none would cut a hole in the
--- chip.

describe("lsp.integrations.lspsaga_chips", function()
  local SEP = "%#SagaSep# > %*"
  local LEFT_CAP = "\xEE\x82\xB6"
  local RIGHT_CAP = "\xEE\x82\xB4"

  ---@return table
  local function fresh()
    package.loaded["lsp.integrations.lspsaga_chips"] = nil
    return require("lsp.integrations.lspsaga_chips")
  end

  local FOLDER = "%#SagaFolder# \xF3\xB0\x89\x8B %*%#SagaFolderName#docs%*"
  local FILE = "%#DevIconMd#M %*%#SagaFileName#notes.md"
  local HEADING = "%#SagaString#\xEF\x8A\x92 Intro"

  ---@param line string
  ---@return string[]
  local function groups_in(line)
    local out = {}
    for name in line:gmatch("%%#([%w_.@]+)#") do
      out[#out + 1] = name
    end
    return out
  end

  it("wraps each part in a cap pair and keeps the separator untouched", function()
    local chips = fresh()
    local out = chips.style({ FOLDER, FILE, HEADING }, SEP)

    local _, caps = out:gsub(LEFT_CAP, "")
    assert.are.equal(3, caps)
    local _, rights = out:gsub(RIGHT_CAP, "")
    assert.are.equal(3, rights)

    local _, seps = out:gsub(vim.pesc(SEP), "")
    assert.are.equal(2, seps)
  end)

  it("gives folder, file and symbol their own chip", function()
    local chips = fresh()
    local out = chips.style({ FOLDER, FILE, HEADING }, SEP)

    assert.is_truthy(out:find("SagaChipBodyfolder", 1, true))
    assert.is_truthy(out:find("SagaChipBodyfile", 1, true))
    assert.is_truthy(out:find("SagaChipBodysymbol", 1, true))
  end)

  it("classifies by content, not position: a lone file is a file", function()
    local chips = fresh()
    local out = chips.style({ FILE }, SEP)

    assert.is_truthy(out:find("SagaChipBodyfile", 1, true))
    assert.is_nil(out:find("SagaChipBodyfolder", 1, true))
  end)

  it("moves the folder icon's leading pad out of the chip", function()
    local chips = fresh()
    local out = chips.style({ "%#SagaFolder#  \xF3\xB0\x89\x8B %*%#SagaFolderName#docs" }, SEP)

    -- cap, body, one space of our own, then the icon's group -- not two spaces.
    assert.is_truthy(
      out:find(LEFT_CAP .. "%#SagaChipBodyfolder# %#SagaChipfolder_SagaFolder#", 1, true)
    )
  end)

  it("replaces every inner group with one that carries the chip background", function()
    local chips = fresh()
    local out = chips.style({ FOLDER, FILE, HEADING }, SEP)

    for _, name in ipairs(groups_in(out)) do
      if name ~= "SagaSep" then
        assert.is_truthy(name:find("^SagaChip"), name .. " is not a chip group")
        assert.is_not_nil(vim.api.nvim_get_hl(0, { name = name }).bg, name .. " has no background")
      end
    end
  end)

  it("turns the grey path text into the role colour", function()
    local chips = fresh()
    vim.api.nvim_set_hl(0, "Special", { fg = 0x7aa2f7 })
    vim.api.nvim_set_hl(0, "SagaFolderName", { link = "Comment" })

    chips.setup_highlights()
    chips.style({ FOLDER }, SEP)

    local hl = vim.api.nvim_get_hl(0, { name = "SagaChipfolder_SagaFolderName", link = false })
    assert.are.equal(0x7aa2f7, hl.fg)
  end)

  it("gives folder, file and symbol chips different colours", function()
    local chips = fresh()
    vim.api.nvim_set_hl(0, "Special", { fg = 0x2ac3de })
    vim.api.nvim_set_hl(0, "Function", { fg = 0x7aa2f7 })
    vim.api.nvim_set_hl(0, "String", { fg = 0x9ece6a })
    vim.api.nvim_set_hl(0, "Title", { fg = 0x7aa2f7 })

    chips.setup_highlights()
    chips.style({ FOLDER, FILE, HEADING }, SEP)

    local function fg(name)
      return vim.api.nvim_get_hl(0, { name = name, link = false }).fg
    end
    assert.are.equal(0x2ac3de, fg("SagaChipBodyfolder"))
    assert.are.equal(0x7aa2f7, fg("SagaChipBodyfile"))
    assert.are.equal(0x9ece6a, fg("SagaChipBodysymbol"))
  end)

  it("colours a symbol's icon and name in the role colour, not the kind's", function()
    local chips = fresh()
    vim.api.nvim_set_hl(0, "String", { fg = 0x9ece6a })
    vim.api.nvim_set_hl(0, "SagaString", { fg = 0xff0000 })

    chips.setup_highlights()
    chips.style({ HEADING }, SEP)

    local hl = vim.api.nvim_get_hl(0, { name = "SagaChipsymbol_SagaString", link = false })
    assert.are.equal(0x9ece6a, hl.fg)
  end)

  it("leaves an already styled line alone", function()
    local chips = fresh()
    local parts = { FOLDER, FILE }
    local once = chips.style(parts, SEP)

    -- Splitting the styled line again gives the parts a second pass sees.
    local again = chips.style(vim.split(once, SEP, { plain = true }), SEP)
    assert.are.equal(once, again)
  end)

  it("redefines the derived groups under the same names after a colorscheme reset", function()
    local chips = fresh()
    local out = chips.style({ FOLDER, FILE }, SEP)
    local names = groups_in(out)

    vim.cmd("hi clear")
    chips.setup_highlights()

    for _, name in ipairs(names) do
      if name:find("^SagaChip") then
        assert.is_not_nil(vim.api.nvim_get_hl(0, { name = name }).bg, name .. " was not redefined")
      end
    end
  end)
end)

describe("lsp.integrations.lspsaga style_winbar", function()
  local SEP = "%#SagaSep# > %*"

  ---@param cfg table|nil
  ---@param fn fun(saga: table)
  local function with_saga(cfg, fn)
    local original = package.loaded["lspsaga"]
    package.loaded["lspsaga"] = { config = { symbol_in_winbar = cfg } }
    package.loaded["lsp.integrations.lspsaga"] = nil
    package.loaded["lsp.integrations.lspsaga_chips"] = nil
    local ok, err = pcall(fn, require("lsp.integrations.lspsaga"))
    package.loaded["lspsaga"] = original
    if not ok then
      error(err, 0)
    end
  end

  local DEFAULT = { enable = true, show_file = true, folder_level = 1, separator = " > " }

  after_each(function()
    vim.wo[vim.api.nvim_get_current_win()].winbar = ""
  end)

  it("rewrites lspsaga's bar into chips", function()
    with_saga(DEFAULT, function(saga)
      local win = vim.api.nvim_get_current_win()
      vim.wo[win].winbar =
        table.concat({ "%#SagaFolder# %*%#SagaFolderName#docs%*", "%#SagaFileName#a.md" }, SEP)

      saga.style_winbar(win)

      assert.is_truthy(vim.wo[win].winbar:find("SagaChipBodyfolder", 1, true))
    end)
  end)

  it("does not touch a winbar that is not lspsaga's", function()
    with_saga(DEFAULT, function(saga)
      local win = vim.api.nvim_get_current_win()
      vim.wo[win].winbar = "%f"

      saga.style_winbar(win)

      assert.are.equal("%f", vim.wo[win].winbar)
    end)
  end)

  it("does nothing with chips switched off", function()
    with_saga(DEFAULT, function(saga)
      local win = vim.api.nvim_get_current_win()
      local line = table.concat({ "%#SagaFolderName#docs", "%#SagaFileName#a.md" }, SEP)
      vim.wo[win].winbar = line
      saga.winbar_chips = false

      saga.style_winbar(win)

      assert.are.equal(line, vim.wo[win].winbar)
    end)
  end)

  it("still lets the depth cap cut a styled bar", function()
    with_saga(DEFAULT, function(saga)
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = "markdown"
      vim.api.nvim_win_set_buf(win, buf)
      vim.wo[win].winbar = table.concat({
        "%#SagaFolder# %*%#SagaFolderName#docs%*",
        "%#SagaFileName#a.md",
        "%#SagaString#H1",
        "%#SagaString#H2",
      }, SEP)

      saga.style_winbar(win)
      saga.trim_winbar(win)

      local _, chips = vim.wo[win].winbar:gsub("\xEE\x82\xB6", "")
      assert.are.equal(3, chips) -- folder, file, H1 -- H2 is cut
    end)
  end)
end)
