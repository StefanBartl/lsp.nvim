---@meta
---@module 'lsp.tools.lsp_signature.@types'

---@class Lsp.Tools.SignatureTool.ParamHighlightOpts
---@field base_fg integer Hex base foreground color (0xRRGGBB). default 0xFF8800
---@field step integer Hex step added per parameter (0x00GG00). default 0x003300
---@field active_fg string GUI color for active parameter (e.g. "#ffffff")
---@field active_bg string GUI background for active parameter (e.g. "#005f87")
---@field active_gui string GUI style for active parameter (e.g. "bold")
---@field param_gui string GUI style for parameter groups (e.g. "bold")

return {}
