---@module 'lsp.core.winbar.kinds'
---@brief Icon and highlight group per LSP SymbolKind, for the breadcrumb.
---@description
--- Codepoints, not literal glyphs, and turned into UTF-8 at load time: a
--- private-use-area glyph written into a source file is one editor or encoding
--- pass away from silently becoming nothing -- it has happened to this
--- plugin's own chip caps -- while `U+EB5B` in a table survives anything.
---
--- The set is the one lspsaga shipped (which is where the breadcrumb came
--- from), so the icons on screen did not change when it was replaced. Kinds
--- above 26 are the extensions lspsaga added for ccls and for completion
--- items; servers do send them.
---
---@see lsp.core.winbar

local M = {}

---@class LspWinbar.Kind
---@field name string
---@field icon string
---@field hl string # Highlight group that colours the icon in the flat (non-chip) breadcrumb.

---@param codepoint integer
---@return string
local function glyph(codepoint)
  return vim.fn.nr2char(codepoint)
end

--- Folder icon in front of the path items.
---@type string
M.FOLDER = glyph(0xF07C)

--- File icon when `nvim-web-devicons` has nothing for the filetype.
---@type string
M.FILE = glyph(0xF15C)

--- Icon for the `String` kind, overridden for Markdown headings: the LSP
--- protocol has no "Heading" kind, so marksman reports them as `String`, and a
--- hashtag reads as "heading" where lspsaga's boxed letter reads as "a data
--- type".
---@type string
M.HEADING = glyph(0xF292)

---@type table<integer, LspWinbar.Kind>
local kinds = {
  [1] = { name = "File", icon = glyph(0xF15C), hl = "Tag" },
  [2] = { name = "Module", icon = glyph(0xE624), hl = "Exception" },
  [3] = { name = "Namespace", icon = glyph(0xEA8B), hl = "Include" },
  [4] = { name = "Package", icon = glyph(0xEB29), hl = "Label" },
  [5] = { name = "Class", icon = glyph(0xEB5B), hl = "Include" },
  [6] = { name = "Method", icon = glyph(0xEA8C), hl = "Function" },
  [7] = { name = "Property", icon = glyph(0xEB65), hl = "@property" },
  [8] = { name = "Field", icon = glyph(0xEB5F), hl = "@variable.member" },
  [9] = { name = "Constructor", icon = glyph(0xF425), hl = "@constructor" },
  [10] = { name = "Enum", icon = glyph(0xEA95), hl = "@number" },
  [11] = { name = "Interface", icon = glyph(0xEB61), hl = "Type" },
  [12] = { name = "Function", icon = glyph(0xF0871), hl = "Function" },
  [13] = { name = "Variable", icon = glyph(0xEA88), hl = "@variable" },
  [14] = { name = "Constant", icon = glyph(0xEB5D), hl = "Constant" },
  [15] = { name = "String", icon = glyph(0xF0173), hl = "String" },
  [16] = { name = "Number", icon = glyph(0xF03A0), hl = "Number" },
  [17] = { name = "Boolean", icon = glyph(0xEA8F), hl = "Boolean" },
  [18] = { name = "Array", icon = glyph(0xF0168), hl = "Type" },
  [19] = { name = "Object", icon = glyph(0xEB5B), hl = "Type" },
  [20] = { name = "Key", icon = glyph(0xEA93), hl = "Constant" },
  [21] = { name = "Null", icon = glyph(0xF07E2), hl = "Constant" },
  [22] = { name = "EnumMember", icon = glyph(0xEB5E), hl = "Number" },
  [23] = { name = "Struct", icon = glyph(0xEA91), hl = "Type" },
  [24] = { name = "Event", icon = glyph(0xEA86), hl = "Constant" },
  [25] = { name = "Operator", icon = glyph(0xEB64), hl = "Operator" },
  [26] = { name = "TypeParameter", icon = glyph(0xEB97), hl = "Type" },
  -- ccls
  [252] = { name = "TypeAlias", icon = glyph(0xE75E), hl = "Type" },
  [253] = { name = "Parameter", icon = glyph(0xEA92), hl = "@variable.parameter" },
  [254] = { name = "StaticMethod", icon = glyph(0xEA8C), hl = "Function" },
  [255] = { name = "Macro", icon = glyph(0xF136), hl = "Macro" },
}

--- Shown for a kind this table does not know, rather than for nothing: an
--- unknown kind is a symbol like any other, and dropping its icon would shift
--- the text of one part against its neighbours.
---@type LspWinbar.Kind
local UNKNOWN = { name = "Symbol", icon = glyph(0xEA88), hl = "@variable" }

--- The icon and highlight group for a SymbolKind.
---
--- `filetype` only matters for Markdown, where the `String` kind means a
--- heading (see `HEADING`).
---@param kind integer
---@param filetype? string
---@return LspWinbar.Kind
function M.get(kind, filetype)
  local entry = kinds[kind] or UNKNOWN
  if kind == 15 and filetype == "markdown" then
    return { name = "Heading", icon = M.HEADING, hl = "Title" }
  end
  return entry
end

return M
