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

--- A value text says what the value does. `:Lsp diag next|prev loc` was described as going through
--- the location list; it jumps to the next diagnostic of the buffer (or opens Trouble) and never
--- reads or fills one. This pins the text to the behaviour it describes: whoever makes `loc` use
--- the location list for real has to change both in the same step.
describe("the text of :Lsp diag next|prev loc", function()
  local buf, ns, orig_jump

  ---@return table|nil arg # the `list` argument of the `diag` route
  local function list_arg()
    local handle = composer.registry().Lsp
    for _, route in ipairs(handle and handle:spec().routes or {}) do
      if table.concat(route.path, " ") == "diag" then
        for _, arg in ipairs(route.args or {}) do
          if arg.name == "list" then
            return arg
          end
        end
      end
    end
  end

  before_each(function()
    require("lsp.bindings.usrcmds").setup()

    -- Trouble, when installed, would take the jump; this is the native path.
    package.loaded["lsp.config"] = nil
    require("lsp.config").setup({ diagnostics = { ui = "native" } })

    -- The float `jump` opens is scheduled and outlives the case; the jump itself is the point.
    orig_jump = vim.diagnostic.jump
    -- Test double, restored in after_each.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.diagnostic.jump = function(opts)
      return orig_jump(vim.tbl_extend("force", opts, { float = false }))
    end

    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two", "three" })
    ns = vim.api.nvim_create_namespace("lsp_nvim_spec_diag_loc_text")
    vim.diagnostic.set(ns, buf, {
      { lnum = 1, col = 0, message = "second line" },
      { lnum = 2, col = 0, message = "third line" },
    })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  end)

  after_each(function()
    vim.diagnostic.jump = orig_jump
    vim.diagnostic.reset(ns, buf)
    vim.fn.setloclist(0, {}, "f")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    pcall(vim.api.nvim_del_user_command, "Lsp")
    package.loaded["lsp.config"] = nil
    require("lsp.config").setup({})
  end)

  it("does not claim the location list, which loc never touches", function()
    if type(composer.registry) ~= "function" then
      return pending("lib.nvim has no composer.registry")
    end
    local arg = list_arg()
    assert.is_truthy(arg, "the diag route has a `list` argument")
    local text = arg.enum_desc.loc
    assert.is_nil(text:lower():find("location list", 1, true), "loc = " .. text)
    assert.is_true(text:find("buffer", 1, true) ~= nil, "loc names what it walks: " .. text)
  end)

  it("walks the diagnostics of the buffer and leaves the location list empty", function()
    vim.cmd("Lsp diag next")
    assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("Lsp diag next loc")
    assert.are.equal(3, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("Lsp diag prev loc")
    assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])

    local loclist = vim.fn.getloclist(0, { size = 0, title = 0 })
    assert.are.equal(0, loclist.size, "no location list was filled")
    assert.are.equal("", loclist.title)
  end)
end)
