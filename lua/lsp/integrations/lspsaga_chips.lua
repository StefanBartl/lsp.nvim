---@module 'lsp.integrations.lspsaga_chips'
---@brief Rounded, coloured chips for the lspsaga winbar breadcrumb.
---@description
--- lspsaga writes the breadcrumb as one flat string: path items and symbols
--- joined by a separator, each item a run of `%#Group#` tags. Its own group
--- names for the path (`SagaFolderName`, `SagaFileName`, `SagaSep`) default to
--- a link to `Comment`, which is why an unstyled breadcrumb reads as grey
--- text on grey text.
---
--- This module rewrites that string, the same way `lspsaga.trim_winbar` does
--- for the depth cap: split on lspsaga's live separator, wrap every part in a
--- rounded chip, and leave the separator alone between chips.
---
--- A part keeps its own icon colour. What changes is the background: every
--- `%#Group#` inside a chip is replaced by a derived group with that group's
--- foreground and the chip's background, because a group without a `bg`
--- would punch a hole in the chip.
---
--- Which chip a part gets is decided from what lspsaga put in it (a
--- `SagaFolder`/`SagaFileName` tag), not from its position: the path is
--- `folder_level + 1` items only when the file sits deep enough, so counting
--- would mislabel a file in the project root.
---
---@see lsp.integrations.lspsaga

local M = {}

local api = vim.api

-- Explicit byte escapes, not literal glyphs -- same reason as
-- `ui.tabline.utils`'s LEFT_CAP/RIGHT_CAP: an editor/encoding pass has
-- silently dropped a literal private-use-area glyph before.
local LEFT_CAP = "\xEE\x82\xB6" -- U+E0B6
local RIGHT_CAP = "\xEE\x82\xB4" -- U+E0B4

--- Every group this module creates starts with this, and a winbar that
--- already contains it has been styled -- that is how a second pass knows to
--- leave the string alone.
local MARK = "SagaChip"

---@class LspNvim.SagaChipRole
---@field hl string    # Group whose foreground colours the chip's text and tints its background.
---@field bold? boolean

--- Chip roles. `folder` and `file` are the path; `symbol` is everything after.
---@type table<string, LspNvim.SagaChipRole>
M.roles = {
  folder = { hl = "Directory" },
  file = { hl = "Function", bold = true },
  symbol = { hl = "Title" },
}

--- How far the chip background is pulled from the window background towards
--- the role colour. 0 is invisible, 1 is the role colour itself.
---@type number
M.tint = 0.16

--- Groups lspsaga names for the path text. Their default colour is `Comment`,
--- so inside a chip they take the role colour instead.
---@type table<string, boolean>
local ROLE_TEXT = { SagaFolder = true, SagaFolderName = true, SagaFileName = true }

---@class LspNvim.SagaChipSpec
---@field kind "body"|"cap"|"text"
---@field role string
---@field name? string # For `text`: the lspsaga/devicon group this one is derived from.

--- Every group this module has made, and how to make it again. A colorscheme
--- change clears them all, and the strings already sitting in a winbar keep
--- naming them -- so they are redefined under the same names rather than
--- forgotten.
---@type table<string, LspNvim.SagaChipSpec>
local specs = {}

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
    -- the window's: a group without one shows the terminal default instead
    -- of the winbar.
    api.nvim_set_hl(0, group, { fg = bg, bg = window_bg() })
  elseif spec.kind == "body" or ROLE_TEXT[spec.name] then
    api.nvim_set_hl(0, group, { fg = fg, bg = bg, bold = role.bold })
  else
    local src = resolve(spec.name)
    api.nvim_set_hl(0, group, { fg = src.fg or fg, bg = bg, bold = src.bold, italic = src.italic })
  end
end

---@param group string
---@param spec LspNvim.SagaChipSpec
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
  local body = ensure(MARK .. "Body" .. role, { kind = "body", role = role })
  local cap = ensure(MARK .. "Cap" .. role, { kind = "cap", role = role })
  return body, cap
end

--- Group with `name`'s look on the chip's background.
---@param name string
---@param role string
---@return string
local function on_chip(name, role)
  local safe = name:gsub("[^%w_]", "_")
  return ensure(MARK .. role .. "_" .. safe, { kind = "text", role = role, name = name })
end

--- Give the separator a visible colour and (re)define every chip group from
--- the current colorscheme. lspsaga defines its path groups with
--- `default = true` and links them to `Comment`.
---@return nil
function M.setup_highlights()
  api.nvim_set_hl(0, "SagaSep", { link = "Operator" })
  for role in pairs(M.roles) do
    chip_groups(role)
  end
  for group in pairs(specs) do
    define(group)
  end
end

---@param part string
---@return string role
local function role_of(part)
  if part:find("%#SagaFolder", 1, true) then
    return "folder"
  end
  if part:find("%#SagaFileName#", 1, true) then
    return "file"
  end
  return "symbol"
end

---@param part string
---@return string
local function chip(part)
  local role = role_of(part)
  local body, cap = chip_groups(role)

  -- The folder icon carries a leading pad from `ui.winbar_prefix`; inside a
  -- chip it would sit between the cap and the icon.
  local inner = part:gsub("^%s+", "")
  inner = inner:gsub("^(%%#[%w_.@]+#)%s+", "%1")
  inner = inner:gsub("%%#([%w_.@]+)#", function(name)
    return "%#" .. on_chip(name, role) .. "#"
  end)
  -- `%*` would drop back to the winbar's own colours in the middle of a chip.
  inner = inner:gsub("%%%*", function()
    return "%#" .. body .. "#"
  end)

  local cap_hl = "%#" .. cap .. "#"
  return cap_hl .. LEFT_CAP .. "%#" .. body .. "# " .. inner .. " " .. cap_hl .. RIGHT_CAP .. "%*"
end

--- Wrap each part in a chip and join them again with `sep`.
---
--- A line that already holds a chip comes back unchanged.
---@param parts string[] # what `lspsaga.split_plain` produced
---@param sep string     # lspsaga's separator, exactly as it built it
---@return string
function M.style(parts, sep)
  for _, part in ipairs(parts) do
    if part:find(MARK, 1, true) then
      return table.concat(parts, sep)
    end
  end

  local out = {}
  for i, part in ipairs(parts) do
    out[i] = chip(part)
  end
  -- One space of left margin, where `ui.winbar_prefix` used to put it.
  return " " .. table.concat(out, sep)
end

return M
