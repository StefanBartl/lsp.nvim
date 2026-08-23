---@meta
---@module 'lsp.lspdoctor.@types'
--- Pure LuaCATS type scaffolding for lspdoctor's `Lsp.Doctor.Options` --
--- no runtime code, `---@meta` only.

---@class Lsp.Doctor.Options
---@field use_notify? boolean Render via vim.notify instead of print (default: false)
---@field list_limit? integer Max items per section in quick mode (default: 10)
---@field show_capabilities? boolean Include per-client capability table in deep mode (default: true)
---@field show_workspace? boolean Include workspace folders and root_dir checks (default: true)
---@field show_tools? boolean Check for common external tools (default: true)
---@field show_conflicts? boolean Detect potential provider conflicts (formatting, diagnostics) (default: true)
---@field formatter_priority? string[] Preferred order of formatting providers (default: {})
---@field semantic_tokens_timeout? integer Timeout (ms) for semantic tokens probe (default: 300)
---@field scratch_filetype? string Filetype for scratch export buffer (default: 'markdown')
---@field scratch_threshold? number
---@field auto_open_scratch? boolean

---@class Lsp.Doctor.Section
---@field title string
---@field lines string[]

---@class Lsp.Doctor.Report
---@field mode '"quick"'|'"deep"'
---@field ok boolean
---@field summary string
---@field sections Lsp.Doctor.Section[]
---@field extras table<string, any> -- extended machine-readable info for tooling
