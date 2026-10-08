--- Every positional argument of `:Lsp`, `:LspDoctor` and `:LspMdHints` has a line in the option
--- float.
---
--- lib.nvim's help float (the option cheatsheet on the command line) shows one line for the next
--- positional argument, taken from the argument's own `desc`, from the text of its type
--- (`register_type`) or -- for a closed set -- from `enum_desc`. This pins that no route ships an
--- argument without one, and that the lines keep the float's house style: one short line, no
--- trailing full stop. A value text for a value the argument does not offer shows nowhere, so that
--- is pinned too.
---
--- Skipped on a lib.nvim without `help.undocumented` / `arg_desc` (older than the argument texts).

local VERBS = { "Lsp", "LspDoctor", "LspMdHints" }

local composer = require("lib.nvim.bindings.usercmd.composer")
local ok_entries, entries = pcall(require, "lib.nvim.bindings.usercmd.composer.help.entries")

local supported = type(composer.help) == "table"
  and type(composer.help.undocumented) == "function"
  and ok_entries
  and type(entries.arg_desc) == "function"

---@param text any
---@return boolean
local function house_style(text)
  return type(text) == "string"
    and text ~= ""
    and not text:find("\n", 1, true)
    and #text <= 80
    and not text:find("%.$")
end

describe("the option float of the lsp.nvim verbs", function()
  if not supported then
    it("needs a lib.nvim with argument texts", function()
      pending("lib.nvim has no help.undocumented / entries.arg_desc")
    end)
    return
  end

  before_each(function()
    require("lsp.bindings.usrcmds").setup()
    require("lsp.lspdoctor").enable_usercmd()
    require("lsp.usercmds").attach_md_hints()
  end)

  after_each(function()
    for _, verb in ipairs(VERBS) do
      pcall(vim.api.nvim_del_user_command, verb)
    end
  end)

  it("leaves no flag and no positional argument without a text", function()
    for _, verb in ipairs(VERBS) do
      local missing = {}
      for _, m in ipairs(composer.help.undocumented(verb, { args = true })) do
        missing[#missing + 1] = ("%s %s %s"):format(m.route, m.kind, m.name)
      end
      assert.are.equal("", table.concat(missing, ", "), ":" .. verb .. " has no text for")
    end
  end)

  it("keeps every text to one short line without a trailing full stop", function()
    local walked, bad = 0, {}
    for _, verb in ipairs(VERBS) do
      local handle = composer.registry()[verb]
      assert.is_truthy(handle, ":" .. verb .. " is registered")
      for _, route in ipairs(handle:spec().routes or {}) do
        for _, arg in ipairs(route.args or {}) do
          walked = walked + 1
          local label = (":%s %s {%s}"):format(verb, table.concat(route.path, " "), arg.name)
          if not house_style(entries.arg_desc(arg)) then
            bad[#bad + 1] = label
          end
          for value, text in pairs(arg.enum_desc or {}) do
            if not house_style(text) then
              bad[#bad + 1] = label .. " = " .. value
            end
            if not vim.tbl_contains(arg.enum or arg.values or {}, value) then
              bad[#bad + 1] = label .. " = " .. value .. " (not one of its values)"
            end
          end
        end
      end
    end
    assert.is_true(walked > 0, "the routes' arguments were actually walked")
    assert.are.equal("", table.concat(bad, "\n"))
  end)

  it("describes a doctor report once for both verbs that offer it", function()
    local doctor = require("lsp.lspdoctor")
    for _, mode in ipairs(doctor.MODES) do
      assert.is_true(house_style(doctor.MODE_DESC[mode]), "report " .. mode .. " has a text")
    end
    for mode in pairs(doctor.MODE_DESC) do
      assert.is_true(vim.tbl_contains(doctor.MODES, mode), mode .. " is a report")
    end
  end)
end)
