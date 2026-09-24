--- Covers `lsp.core.winbar.render` and `lsp.core.winbar.kinds`: what the
--- breadcrumb's string is made of.
---
--- The string is what `'winbar'` evaluates, so three things have to hold or the
--- bar shows garbage rather than failing loudly: a literal `%` in a symbol name
--- is doubled (a Lua function called `50%` would otherwise open a format
--- item), every part is wrapped, and every group the string names exists --
--- Neovim renders an undefined group as no highlight at all, which for a chip
--- means text on the wrong background.

local render = require("lsp.core.winbar.render")
local kinds = require("lsp.core.winbar.kinds")

---@param group string
---@return table
local function hl(group)
  return vim.api.nvim_get_hl(0, { name = group, link = false })
end

describe("lsp.core.winbar.render", function()
  local parts = {
    { role = "folder", icon = "F", text = "src" },
    { role = "file", icon = "f", icon_hl = "Function", text = "init.lua" },
    { role = "symbol", icon = "S", icon_hl = "Type", text = "Repo" },
  }

  before_each(function()
    render.setup_highlights()
  end)

  it("renders nothing for no parts", function()
    assert.are.equal("", render.render({}, { chips = true, separator = " > " }))
    assert.are.equal("", render.render({}, { chips = false, separator = " > " }))
  end)

  describe("flat", function()
    local out = render.render(parts, { chips = false, separator = " > " })

    it("carries every part's text, in order", function()
      local a = out:find("src", 1, true)
      local b = out:find("init.lua", 1, true)
      local c = out:find("Repo", 1, true)
      assert.is_truthy(a and b and c)
      assert.is_true(a < b and b < c)
    end)

    it("joins the parts with the separator, in its own group", function()
      local _, count = out:gsub("%%#LspNvimWinbarSep# > %%%*", "")
      assert.are.equal(2, count)
    end)

    it("colours a symbol's icon by its kind and its text by the role", function()
      assert.is_truthy(out:find("%#Type#S %*", 1, true))
      assert.is_truthy(out:find("%#LspNvimWinbarSymbol#Repo%*", 1, true))
    end)

    it("starts with one space of margin", function()
      assert.are.equal(" ", out:sub(1, 1))
      assert.are_not.equal(" ", out:sub(2, 2))
    end)

    it("does not draw chip caps", function()
      assert.is_nil(out:find(vim.fn.nr2char(0xE0B6), 1, true))
    end)
  end)

  describe("chips", function()
    local out = render.render(parts, { chips = true, separator = " > " })

    it("wraps every part but the first in a left cap, and every part in a right cap", function()
      -- The first chip sits at the window edge, same as the tabline's own
      -- corner: squared off, not rounded.
      local _, left = out:gsub(vim.fn.nr2char(0xE0B6), "")
      local _, right = out:gsub(vim.fn.nr2char(0xE0B4), "")
      assert.are.equal(2, left)
      assert.are.equal(3, right)
    end)

    it("squares off the leftmost chip instead of rounding it", function()
      assert.are_not.equal(
        vim.fn.nr2char(0xE0B6),
        out:sub(1, 1),
        "the first chip should not open with the rounded left cap"
      )
    end)

    it("sits flush against the window edge, with no left margin", function()
      -- Unlike flat mode, chips mode drops the leading space: the leftmost
      -- chip's squared-off edge should touch the window edge directly, the
      -- same corner the tabline leaves flush.
      assert.are_not.equal(" ", out:sub(1, 1))
    end)

    it("names only groups that exist and carry a background", function()
      for group in out:gmatch("%%#([%w_]+)#") do
        if group:find("Chip", 1, true) and not group:find("ChipCap", 1, true) then
          assert.is_not_nil(hl(group).bg, group .. " has no background: it would punch a hole")
        end
        if group:find("ChipCap", 1, true) then
          assert.is_not_nil(hl(group).fg, group .. " has no foreground")
          assert.is_not_nil(hl(group).bg, group .. " has no background")
        end
      end
    end)

    it("keeps the file's own icon colour on the chip background", function()
      local group = out:match("%%#(LspNvimWinbarChipfile_Function)#")
      assert.is_string(group)
      assert.are.equal(hl("Function").fg, hl(group).fg)
      assert.are.equal(hl("LspNvimWinbarChipBodyfile").bg, hl(group).bg)
    end)

    it("gives the three roles three different chip backgrounds", function()
      -- One colour for all of them made the path indistinguishable from the
      -- symbols -- the reason `folder`/`file`/`symbol` read different groups.
      --
      -- The colours are set here: a bare headless session has none for these
      -- groups, and three roles with no colour to derive from are one role.
      vim.api.nvim_set_hl(0, "Special", { fg = 0xff5555 })
      vim.api.nvim_set_hl(0, "Function", { fg = 0x55ff55 })
      vim.api.nvim_set_hl(0, "String", { fg = 0x5555ff })
      render.setup_highlights()
      local seen = {}
      for _, role in ipairs({ "folder", "file", "symbol" }) do
        seen[hl("LspNvimWinbarChipBody" .. role).bg] = true
      end
      local n = 0
      for _ in pairs(seen) do
        n = n + 1
      end
      assert.are.equal(3, n)
    end)

    it("redefines its groups under the same names after a colorscheme clears them", function()
      local group = "LspNvimWinbarChipBodysymbol"
      assert.is_not_nil(hl(group).bg)
      vim.api.nvim_set_hl(0, group, {})
      assert.is_nil(hl(group).bg)
      render.setup_highlights()
      assert.is_not_nil(hl(group).bg)
    end)
  end)

  describe("align", function()
    it("is unchanged from the default (no align, or align = left)", function()
      local plain = render.render(parts, { chips = false, separator = " > " })
      local no_align = render.render(parts, { chips = false, separator = " > ", align = "left" })
      assert.are.equal(plain, no_align)
      assert.are_not.equal("%", plain:sub(1, 1))
    end)

    it("prepends the 'winbar' built-in right-align item for align = right", function()
      local left = render.render(parts, { chips = false, separator = " > " })
      local right = render.render(parts, { chips = false, separator = " > ", align = "right" })
      assert.are.equal("%=" .. left, right)
    end)

    it("prepends %= in chips mode too, ahead of the squared-off leftmost chip", function()
      local left = render.render(parts, { chips = true, separator = " > " })
      local right = render.render(parts, { chips = true, separator = " > ", align = "right" })
      assert.are.equal("%=" .. left, right)
    end)

    it("still renders an empty string for no parts, align = right included", function()
      assert.are.equal("", render.render({}, { chips = true, separator = " > ", align = "right" }))
    end)

    it(
      "wraps the body in the built-in split-point item on both sides for align = center",
      function()
        local left = render.render(parts, { chips = false, separator = " > " })
        local center = render.render(parts, { chips = false, separator = " > ", align = "center" })
        assert.are.equal("%=" .. left .. "%=", center)
      end
    )

    it("wraps in center mode too, ahead of the squared-off leftmost chip", function()
      local left = render.render(parts, { chips = true, separator = " > " })
      local center = render.render(parts, { chips = true, separator = " > ", align = "center" })
      assert.are.equal("%=" .. left .. "%=", center)
    end)

    it("still renders an empty string for no parts, align = center included", function()
      assert.are.equal("", render.render({}, { chips = true, separator = " > ", align = "center" }))
    end)
  end)

  describe("escaping", function()
    it("doubles a literal percent sign", function()
      local out = render.render(
        { { role = "symbol", text = "50%off" } },
        { chips = false, separator = " > " }
      )
      assert.is_truthy(out:find("50%%off", 1, true))
    end)

    it("collapses newlines and runs of whitespace in a name", function()
      assert.are.equal("a b c", render.escape("a\n  b\t\tc"))
    end)

    it("escapes the icon and the separator as well", function()
      local out = render.render(
        { { role = "file", icon = "%", text = "a" }, { role = "symbol", text = "b" } },
        { chips = false, separator = "%>" }
      )
      assert.is_truthy(out:find("%%", 1, true))
      assert.is_truthy(out:find("%%>", 1, true))
    end)
  end)
end)

describe("lsp.core.winbar.render as Neovim evaluates it", function()
  before_each(function()
    render.setup_highlights()
  end)

  -- Not the string, the result of `nvim_eval_statusline`: a `%` left undoubled
  -- or a stray `%=` in a name would show up here as different text or a
  -- truncated bar, where the string comparisons above cannot see it.
  for _, chips in ipairs({ true, false }) do
    it(("shows the text as written, chips = %s"):format(tostring(chips)), function()
      local out = render.render({
        { role = "folder", icon = "F", text = "src" },
        { role = "file", icon = "f", text = "a.lua" },
        { role = "symbol", icon = "S", text = "50%off %=x" },
      }, { chips = chips, separator = " > " })

      local result = vim.api.nvim_eval_statusline(out, { use_winbar = true })
      for _, want in ipairs({ "src", "a.lua", "50%off %=x" }) do
        assert.is_truthy(result.str:find(want, 1, true), want .. " in " .. result.str)
      end
      assert.is_false(result.truncated == true)
    end)
  end

  it("keeps every part's text intact when right-aligned, percent signs included", function()
    local out = render.render({
      { role = "folder", icon = "F", text = "src" },
      { role = "file", icon = "f", text = "a.lua" },
      { role = "symbol", icon = "S", text = "50%off" },
    }, { chips = false, separator = " > ", align = "right" })

    local result = vim.api.nvim_eval_statusline(out, { use_winbar = true })
    for _, want in ipairs({ "src", "a.lua", "50%off" }) do
      assert.is_truthy(result.str:find(want, 1, true), want .. " in " .. result.str)
    end
    assert.is_false(result.truncated == true)
  end)

  it("keeps every part's text intact when centered, percent signs included", function()
    local out = render.render({
      { role = "folder", icon = "F", text = "src" },
      { role = "file", icon = "f", text = "a.lua" },
      { role = "symbol", icon = "S", text = "50%off" },
    }, { chips = false, separator = " > ", align = "center" })

    local result = vim.api.nvim_eval_statusline(out, { use_winbar = true })
    for _, want in ipairs({ "src", "a.lua", "50%off" }) do
      assert.is_truthy(result.str:find(want, 1, true), want .. " in " .. result.str)
    end
    assert.is_false(result.truncated == true)
  end)

  it("resolves every highlight group it names to a defined one", function()
    local out = render.render({
      { role = "file", icon = "f", icon_hl = "Function", text = "a.lua" },
      { role = "symbol", icon = "S", icon_hl = "Type", text = "Repo" },
    }, { chips = true, separator = " > " })
    local result = vim.api.nvim_eval_statusline(out, { use_winbar = true, highlights = true })
    for _, span in ipairs(result.highlights) do
      if span.group ~= "WinBar" and span.group ~= "WinBarNC" then
        assert.is_true(
          next(vim.api.nvim_get_hl(0, { name = span.group })) ~= nil,
          span.group .. " is undefined"
        )
      end
    end
  end)
end)

describe("lsp.core.winbar.kinds", function()
  it("has an icon and a highlight group for every standard SymbolKind", function()
    for kind = 1, 26 do
      local entry = kinds.get(kind)
      assert.is_true(#entry.icon > 0, "no icon for kind " .. kind)
      assert.is_true(#entry.hl > 0, "no group for kind " .. kind)
    end
  end)

  it("gives an unknown kind an icon instead of nothing", function()
    local entry = kinds.get(9999)
    assert.is_true(#entry.icon > 0)
  end)

  it("draws a Markdown heading with a hashtag, not the boxed-letter String icon", function()
    assert.are_not.equal(kinds.get(15, "markdown").icon, kinds.get(15, "lua").icon)
    assert.are.equal(kinds.HEADING, kinds.get(15, "markdown").icon)
  end)

  it("only special-cases the String kind, and only in markdown", function()
    assert.are.equal(kinds.get(12).icon, kinds.get(12, "markdown").icon)
  end)

  it("builds its glyphs from codepoints, so the file has no private-use bytes in it", function()
    local path = vim.api.nvim_get_runtime_file("lua/lsp/core/winbar/kinds.lua", false)[1]
    local src = table.concat(vim.fn.readfile(path), "\n")
    -- U+E000..U+F8FF is UTF-8 EE 80 80 .. EF A3 BF: the range an editor pass
    -- has silently dropped before.
    assert.is_nil(src:find("[\238-\239][\128-\191][\128-\191]"))
  end)
end)
