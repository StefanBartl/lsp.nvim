---@module 'lsp.core.winbar.render'
---@brief Turn breadcrumb parts into a `'winbar'` string: rounded chips, or flat.
---@description
--- Input is a list of |LspWinbar.Part| -- what the breadcrumb says -- and the
--- output is the string `'winbar'` wants, `%#Group#` tags and all. Nothing here
--- knows about LSP, windows or buffers, which is what lets the spec suite feed
--- it plain tables.
---
--- **Chips.** Every part is wrapped in a rounded chip: a left cap, a body with
--- a background tinted from the part's role colour, a right cap. A part keeps
--- its own icon colour where it has one (the file's devicon); the background is
--- the chip's, because a highlight group without a `bg` would punch a hole in
--- the chip. Each `%#Group#` is therefore replaced by a derived group with that
--- group's foreground and the chip's background, created on first use.
---
--- Which chip a part gets comes from its `role`, not its position: the path is
--- `folder_level + 1` items only when the file sits deep enough, so counting
--- would mislabel a file in the project root.
---
--- The leftmost chip squares off its left edge instead of rounding it: it sits
--- at the window edge, the same corner the tabline leaves square, so a rounded
--- cap there would be the odd one out rather than the rest of the chips.
---
--- The three role colours are picked so they differ in the common
--- colourschemes: `Directory`, `Function` and `Title` are one and the same
--- blue in tokyonight, which made all three chips look alike.
---
--- **Flat.** With `chips = false` the parts are joined by the separator with no
--- background at all, coloured by highlight groups that are linked (not
--- defined), so a user's `:hi link` wins.
---
--- A colorscheme change clears every group. The strings already sitting in a
--- window's `'winbar'` keep naming them, so the derived groups are redefined
--- under the same names on `setup_highlights()` instead of being forgotten.
---
---@see lsp.core.winbar

local api = vim.api

local M = {}

-- Explicit codepoints, not literal glyphs -- same reason as `winbar.kinds`.
local LEFT_CAP = vim.fn.nr2char(0xE0B6)
local RIGHT_CAP = vim.fn.nr2char(0xE0B4)

---@class LspWinbar.Part
---@field role "folder"|"file"|"symbol"
---@field text string
---@field icon string|nil
---@field icon_hl string|nil # Group that colours the icon: the devicon's, or the symbol kind's.

---@class LspWinbar.RenderOpts
---@field chips boolean # Rounded chips, or the flat string.
---@field separator string # Between parts.
---@field align? "left"|"right"|"center" # `"right"` pushes the breadcrumb to the right edge, `"center"` splits it evenly between both; default is `"left"`.

--- Groups that appear in the strings this module writes. Every one of them
--- starts with this, and the winbar owner check in `lsp.core.winbar` relies on
--- it to tell its own strings from another plugin's.
---@type string
M.MARK = "LspNvimWinbar"

---@class LspWinbar.ChipRole
---@field hl string # Group whose foreground colours the chip's text and tints its background.
---@field bold? boolean

--- Chip roles: `folder` and `file` are the path, `symbol` everything after.
---@type table<string, LspWinbar.ChipRole>
M.roles = {
  folder = { hl = "Special" },
  file = { hl = "Function", bold = true },
  symbol = { hl = "String" },
}

--- How far the chip background is pulled from the window background towards
--- the role colour. 0 is invisible, 1 is the role colour itself.
---@type number
M.tint = 0.2

--- Flat-mode groups. Linked with `default = true`, so `:hi link` in a user's
--- config is not overwritten.
---@type table<string, string>
local FLAT_LINKS = {
  LspNvimWinbarFolder = "Directory",
  LspNvimWinbarFile = "Title",
  LspNvimWinbarSymbol = "String",
  LspNvimWinbarSep = "Operator",
}

---@type table<string, string>
local FLAT_GROUP = {
  folder = "LspNvimWinbarFolder",
  file = "LspNvimWinbarFile",
  symbol = "LspNvimWinbarSymbol",
}

---@class LspWinbar.ChipSpec
---@field kind "body"|"cap"|"text"
---@field role string
---@field name? string # For `text`: the group this one is derived from.

--- Every derived group this module has made, and how to make it again.
---@type table<string, LspWinbar.ChipSpec>
local specs = {}

-- --------------------------------------------------------------------- colour

---@param name string
---@return { fg?: integer, bg?: integer, bold?: boolean, italic?: boolean }
local function resolve(name)
  local ok, hl = pcall(api.nvim_get_hl, 0, { name = name, link = false })
  return ok and hl or {}
end

---@param fg integer
---@param bg integer
---@param amount number
---@return integer
local function mix(fg, bg, amount)
  local out = 0
  for _, unit in ipairs({ 65536, 256, 1 }) do
    local f = math.floor(fg / unit) % 256
    local b = math.floor(bg / unit) % 256
    out = out * 256 + math.floor(b + (f - b) * amount + 0.5)
  end
  return out
end

---@return integer
local function window_bg()
  local bg = resolve("WinBar").bg or resolve("Normal").bg
  if bg then
    return bg
  end
  return vim.o.background == "light" and 0xeff1f5 or 0x1f2335
end

---@param role string
---@return integer fg, integer chip_bg
local function role_colors(role)
  local fg = resolve(M.roles[role].hl).fg or resolve("Normal").fg or 0xc0caf5
  return fg, mix(fg, window_bg(), M.tint)
end

---@param group string
---@return nil
local function define(group)
  local spec = specs[group]
  local fg, bg = role_colors(spec.role)
  local role = M.roles[spec.role]

  if spec.kind == "cap" then
    -- The cap is the chip's colour drawn on the window's, so its `bg` must be
    -- the window's: a group without one shows the terminal default instead of
    -- the winbar.
    api.nvim_set_hl(0, group, { fg = bg, bg = window_bg() })
  elseif spec.kind == "body" then
    api.nvim_set_hl(0, group, { fg = fg, bg = bg, bold = role.bold })
  else
    local src = resolve(spec.name)
    api.nvim_set_hl(0, group, { fg = src.fg or fg, bg = bg, bold = src.bold, italic = src.italic })
  end
end

---@param group string
---@param spec LspWinbar.ChipSpec
---@return string group
local function ensure(group, spec)
  if not specs[group] then
    specs[group] = spec
    define(group)
  end
  return group
end

---@param role string
---@return string body, string cap
local function chip_groups(role)
  local body = ensure(M.MARK .. "ChipBody" .. role, { kind = "body", role = role })
  local cap = ensure(M.MARK .. "ChipCap" .. role, { kind = "cap", role = role })
  return body, cap
end

--- Group with `name`'s foreground on the chip's background.
---@param name string
---@param role string
---@return string
local function on_chip(name, role)
  local safe = name:gsub("[^%w_]", "_")
  return ensure(
    M.MARK .. "Chip" .. role .. "_" .. safe,
    { kind = "text", role = role, name = name }
  )
end

--- (Re)define every highlight group from the current colorscheme: the flat
--- links, and each derived chip group that has ever been used.
---@return nil
function M.setup_highlights()
  for group, target in pairs(FLAT_LINKS) do
    api.nvim_set_hl(0, group, { link = target, default = true })
  end
  for role in pairs(M.roles) do
    chip_groups(role)
  end
  for group in pairs(specs) do
    define(group)
  end
end

-- ------------------------------------------------------------------ rendering

---@internal
--- Text that is safe inside a `'winbar'` string: `%` doubled, and whitespace
--- runs (a heading with a trailing newline, a signature spread over lines)
--- collapsed to one space.
---@param s string
---@return string
local function escape(s)
  local flat = s:gsub("%s+", " ")
  return (flat:gsub("%%", "%%%%"))
end

M.escape = escape

---@param part LspWinbar.Part
---@param leftmost boolean|nil # Square off the left edge instead of rounding it:
--- the first chip sits at the window edge, same as the tabline's own corner.
---@return string
local function chip(part, leftmost)
  local role = part.role
  local body, cap = chip_groups(role)

  local inner = ""
  if part.icon and part.icon ~= "" then
    -- A file keeps its devicon colour; everything else takes the role's.
    local icon_group = (role == "file" and part.icon_hl) and on_chip(part.icon_hl, role) or body
    inner = "%#" .. icon_group .. "#" .. escape(part.icon) .. " "
  end
  inner = inner .. "%#" .. body .. "#" .. escape(part.text)

  local cap_hl = "%#" .. cap .. "#"
  local left = leftmost and ("%#" .. body .. "#") or (cap_hl .. LEFT_CAP .. "%#" .. body .. "#")
  return left .. " " .. inner .. " " .. cap_hl .. RIGHT_CAP .. "%*"
end

---@param part LspWinbar.Part
---@return string
local function flat(part)
  local out = ""
  if part.icon and part.icon ~= "" then
    out = "%#" .. (part.icon_hl or FLAT_GROUP[part.role]) .. "#" .. escape(part.icon) .. " %*"
  end
  return out .. "%#" .. FLAT_GROUP[part.role] .. "#" .. escape(part.text) .. "%*"
end

--- The `'winbar'` string for a list of parts.
---
--- Empty input is an empty string, which callers treat as "nothing to show".
---@param parts LspWinbar.Part[]
---@param opts LspWinbar.RenderOpts
---@return string
function M.render(parts, opts)
  if #parts == 0 then
    return ""
  end

  local sep = "%#LspNvimWinbarSep#" .. escape(opts.separator) .. "%*"
  local drawn = {}
  for i, part in ipairs(parts) do
    drawn[i] = opts.chips and chip(part, i == 1) or flat(part)
  end

  local body
  if opts.chips then
    -- No left margin: the leftmost chip's squared-off edge sits flush
    -- against the window edge, the same corner the tabline leaves flush.
    body = table.concat(drawn, sep)
  else
    -- Flat mode keeps one space of left margin: the first glyph would
    -- otherwise sit tighter against the window edge than the rest.
    body = " " .. table.concat(drawn, sep)
  end

  if opts.align == "right" then
    -- `%=` is a built-in 'statusline' (and so 'winbar') item: everything
    -- after it is pushed to the right edge. No padding math needed -- it is
    -- a literal format item, not user text, so it is prepended after
    -- `escape()` has already run on every part, icon and separator above.
    return "%=" .. body
  end
  if opts.align == "center" then
    -- Two split points instead of one: 'statusline' spaces the section
    -- between them evenly from both sides, which centres it. Nothing before
    -- the first `%=` and nothing after the second, so the body is the whole
    -- middle section.
    return "%=" .. body .. "%="
  end
  return body
end

return M
