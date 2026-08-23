---@module 'lsp.tools.lsp_signature.highlights.parameters'
--- Manage and configure highlight groups used for LSP signature parameter emphasis.
--- This module exposes a `setup(opts)` function which creates the groups and returns
--- the namespace id (ns) to be used for range highlighting.
---
--- Usage:
---   local hl = require("lsp.tools.lsp_signature.highlights.parameters")
---   local ns = hl.setup({ -- optional overrides })
--- The function is idempotent and can be called multiple times (reconfigures).

local M = {}

local helper = require("lsp.tools.lsp_signature.utils.helper")

--- default options for highlights
---@type Lsp.Tools.SignatureTool.ParamHighlightOpts
local defaults = {
  base_fg = 0xFF8800, -- base color for param group 1 (hex number)
  step = 0x003300, -- added to base for subsequent groups
  active_fg = "#ffffff", -- foreground for active parameter
  active_bg = "#005f87", -- background for active parameter
  active_gui = "bold", -- gui attr for active parameter
  param_gui = "bold", -- gui attr for regular param groups
}

-- list of param highlight group names. fixed length known ahead of time.
---@type string[]
local param_highlight_groups =
  { "LspSignatureParam1", "LspSignatureParam2", "LspSignatureParam3", "LspSignatureParam4" }

-- internal namespace id used for hl.range calls
local ns_id = nil

--- (Re)create highlight groups according to options.
--- Returns namespace id to be used with vim.hl.range.
---@param opts Lsp.Tools.SignatureTool.ParamHighlightOpts|nil
---@return integer ns
function M.setup(opts)
  opts = opts or {}
  -- merge opts with defaults
  local base_fg = (opts.base_fg ~= nil) and opts.base_fg or defaults.base_fg
  local step = (opts.step ~= nil) and opts.step or defaults.step
  local active_fg = opts.active_fg or defaults.active_fg
  local active_bg = opts.active_bg or defaults.active_bg
  local active_gui = opts.active_gui or defaults.active_gui
  local param_gui = opts.param_gui or defaults.param_gui

  -- ensure namespace exists
  if not ns_id then
    ns_id = vim.api.nvim_create_namespace("LspSignatureParams")
  end

  -- create parameter highlight groups with computed foreground colors
  -- Explanation of color math:
  --   base_fg  = starting color for the first param group (0xRRGGBB as integer)
  --   step     = value added for each subsequent group to make a darker/shifted color
  -- The numeric math is simplistic (adds to the integer) and serves as a quick way
  -- to produce visually distinct but related colors; adjust `base_fg` and `step`
  -- in setup() if different palette behavior is desired.
  for i, grp in ipairs(param_highlight_groups) do
    local computed = base_fg + (i - 1) * step
    local guifg = helper.hexnum_to_hexstr(computed)
    -- Use `:highlight` for portability across environments (term/gui).
    -- param_gui controls text styling (e.g. "bold").
    vim.cmd(string.format("highlight %s guifg=%s gui=%s", grp, guifg, param_gui))
  end

  -- active parameter highlight group (foreground, background, style)
  vim.cmd(
    string.format(
      "highlight LspSignatureActiveParam guifg=%s guibg=%s gui=%s",
      active_fg,
      active_bg,
      active_gui
    )
  )

  return ns_id
end

--- expose param highlight group names for external use
---@return string[]
function M.group_names()
  return param_highlight_groups
end

---@return integer|nil
function M.ns_id()
  return ns_id
end

return M
