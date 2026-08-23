---@meta
---@module 'lsp.diagnostics.@types'

---@class Lsp.Diagnostics.QfOpts
---@field open? boolean            # open quickfix/loclist window immediately
---@field severity? integer|string # numeric severity (vim.diagnostic.severity.*) or string ("error","warn","info","hint","all")
---@field bufnr? integer           # target buffer; nil = all buffers (workspace) for quickfix, or current buffer for loclist
---@field namespace? integer       # namespace filter; nil = all namespaces
---@field win_id? integer          # window id for loclist; defaults to 0 (current window)

---@class Lsp.Diagnostics.NavigationOpts
---@field wrap? boolean            # wrap at buffer ends (true = cycle, false = stop)
---@field float? boolean|table     # float window options when jumping to diagnostics
---@field severity? integer        # numeric severity

---@class Lsp.Diagnostics.SeverityMap
---@field error integer
---@field err integer
---@field e integer
---@field warn integer
---@field warning integer
---@field w integer
---@field info integer
---@field i integer
---@field hint integer
---@field h integer

---@class Lsp.Diagnostics.Quickfix
---@field to_qf fun(opts: Lsp.Diagnostics.QfOpts): nil
---@field qf_next fun(): nil
---@field qf_prev fun(): nil

---@class Lsp.Diagnostics.Loclist
---@field to_loc fun(opts: Lsp.Diagnostics.QfOpts): nil
---@field loc_next fun(): nil
---@field loc_prev fun(): nil

---@class Lsp.Diagnostics.Navigation
---@field goto_next fun(severity: integer?, opts: Lsp.Diagnostics.NavigationOpts?): nil
---@field goto_prev fun(severity: integer?, opts: Lsp.Diagnostics.NavigationOpts?): nil
---@field workspace_next fun(severity: integer?): nil
---@field workspace_prev fun(severity: integer?): nil
---@field parse_severity fun(s: string|integer?): integer?

---@class Lsp.Diagnostics.Commands
---@field setup fun(): nil

---@class Lsp.Diagnostics.Keymaps
---@field setup fun(map: fun()?): nil

---@class Lsp.Diagnostics
---@field setup fun(opts: table?): nil

--- Shared option type for diagnostics list builders.
---@class Lsp.Diagnostics.ListOpts
---@field open? boolean            # Open the list window immediately.
---@field severity? integer|string # Numeric severity or string ("error","warn","info","hint","all").
---@field bufnr? integer           # Target buffer; nil = workspace (quickfix) or current buffer (loclist).
---@field namespace? integer       # Diagnostic namespace; nil = all namespaces.
---@field win_id? integer          # Window id for loclist; defaults to 0 (current window).

return {}
