---@module 'lsp.integrations.mason.ensure_install.project'
--- Tells lib.nvim's project scan which Mason packages a filetype wants, so
--- `:Lib deps project` (in a root holding Lua files, say) lists
--- `lua-language-server` or `luacheck` as missing when they are not installed.
---
--- The packages are the ones `ensure_install` would ask Mason for
--- (`ensure_install.wanted`: the four default lists, `mason.overrides` on
--- top, minus what `gate_by_system_deps` refuses on this machine). Which
--- filetype a package serves is not in those lists -- they are flat
--- `name -> boolean` maps -- so `FILETYPES` below says it. A package that is
--- switched on but has no entry there is not registered; the spec keeps every
--- default package covered.
---
--- Registering installs nothing and needs no `mason.ensure_install = true`:
--- the scan only reports, and `:Lib deps project install` asks first. The
--- table is a function, built at report time, so a `PATH` change (dotnet
--- installed later) and a Mason that is not loadable are seen when the report
--- is asked for, not when `setup()` ran. Without Mason the table is empty --
--- every package would otherwise land under "Could not be checked".
---
--- `lib.nvim.deps.project` is newer than the rest of lib.nvim this plugin
--- uses. When it is missing (an older lib.nvim), `register` says so and does
--- nothing else; `:checkhealth lsp` carries the hint to update.

local M = {}

--- The name the table is registered under.
M.OWNER = "lsp.nvim"

local JS_TS = { "javascript", "javascriptreact", "typescript", "typescriptreact" }

---@param ... string[]
---@return string[]
local function concat(...)
  local out = {}
  for _, list in ipairs({ ... }) do
    vim.list_extend(out, list)
  end
  return out
end

--- Mason package -> the filetypes it serves. Covers every package of the
--- `ensure_install` default lists (also the ones switched off by default,
--- since `mason.overrides` can switch them on).
---@type table<string, string[]>
M.FILETYPES = {
  -- LSP servers
  ["asm-lsp"] = { "asm", "nasm" },
  ["ast-grep"] = concat(
    JS_TS,
    { "c", "cpp", "cs", "css", "go", "html", "java", "lua", "python", "rust" }
  ),
  ["bash-language-server"] = { "sh", "bash" },
  ["cmake-language-server"] = { "cmake" },
  ["csharp-language-server"] = { "cs" },
  ["css-lsp"] = { "css", "scss", "less" },
  ["eslint-lsp"] = concat(JS_TS, { "vue", "svelte", "astro" }),
  ["html-lsp"] = { "html" },
  ["htmx-lsp"] = { "html" },
  ["json-lsp"] = { "json", "jsonc" },
  ["jsonld-lsp"] = { "jsonld" },
  ["lua-language-server"] = { "lua" },
  ["markdown-oxide"] = { "markdown" },
  ["marksman"] = { "markdown" },
  ["omnisharp"] = { "cs" },
  ["sqlls"] = { "sql", "mysql" },
  ["sqls"] = { "sql", "mysql" },
  ["svelte-language-server"] = { "svelte" },
  ["tailwindcss-language-server"] = concat(
    { "html", "css" },
    { "javascriptreact", "typescriptreact", "vue", "svelte", "astro" }
  ),
  ["ts_query_ls"] = { "query" },
  ["typescript-language-server"] = JS_TS,
  ["vim-language-server"] = { "vim" },
  ["vtsls"] = JS_TS,
  ["vue-language-server"] = { "vue" },
  ["yaml-language-server"] = { "yaml" },

  -- DAP adapters
  ["bash-debug-adapter"] = { "sh", "bash" },
  ["codelldb"] = { "c", "cpp", "rust", "zig" },
  ["firefox-debug-adapter"] = JS_TS,
  ["js-debug-adapter"] = JS_TS,
  ["netcoredbg"] = { "cs" },
  ["node-debug2-adapter"] = JS_TS,

  -- Linters
  ["cmakelang"] = { "cmake" },
  ["cmakelint"] = { "cmake" },
  ["eslint_d"] = JS_TS,
  ["htmlhint"] = { "html" },
  ["jsonlint"] = { "json" },
  ["luacheck"] = { "lua" },
  ["markdownlint"] = { "markdown" },
  ["markdownlint-cli2"] = { "markdown" },
  ["markuplint"] = { "html", "vue", "svelte", "astro" },
  ["sqlfluff"] = { "sql" },
  ["yamllint"] = { "yaml" },

  -- Formatters
  ["asmfmt"] = { "asm" },
  ["luaformatter"] = { "lua" },
  ["markdown-toc"] = { "markdown" },
  ["mdformat"] = { "markdown" },
  ["prettier"] = concat(
    JS_TS,
    { "css", "scss", "less", "html", "json", "jsonc", "yaml", "markdown", "vue", "svelte" }
  ),
  ["sql-formatter"] = { "sql" },
  ["sqlfmt"] = { "sql" },
  ["xmlformatter"] = { "xml" },
  ["yamlfix"] = { "yaml" },
  ["yamlfmt"] = { "yaml" },
}

--- Turn a package list into lib.nvim's `{ [filetype] = { { mason = pkg }, ... } }`.
--- Pure. Packages without a `FILETYPES` entry are left out; each filetype's
--- list keeps the order of `packages`.
---@param packages string[]
---@return table<string, { mason: string }[]> tools
function M.tools(packages)
  local out = {}
  for _, name in ipairs(packages) do
    for _, ft in ipairs(M.FILETYPES[name] or {}) do
      local list = out[ft]
      if not list then
        list = {}
        out[ft] = list
      end
      list[#list + 1] = { mason = name }
    end
  end
  return out
end

---@type "registered"|"unavailable"|nil
local STATE = nil

--- Register the tools table with `lib.nvim.deps.project`.
---
--- Returns false and the reason when that module is not there (lib.nvim
--- older than it) or has no `register_tools`; nothing raises.
---@param overrides {lsp?:Cfg.Mason.EnsureMap, dap?:Cfg.Mason.EnsureMap, linters?:Cfg.Mason.EnsureMap, formatters?:Cfg.Mason.EnsureMap}|nil # `mason.overrides`
---@return boolean registered
---@return string|nil reason
function M.register(overrides)
  local ok, project = pcall(require, "lib.nvim.deps.project")
  if not ok or type(project) ~= "table" or type(project.register_tools) ~= "function" then
    STATE = "unavailable"
    return false, "lib.nvim.deps.project not available (lib.nvim too old)"
  end
  project.register_tools(M.OWNER, function()
    if not pcall(require, "mason-registry") then
      return {}
    end
    return M.tools(require("lsp.integrations.mason.ensure_install").wanted(overrides))
  end)
  STATE = "registered"
  return true, nil
end

--- What the last `register` call found: `"registered"`, `"unavailable"`, or
--- nil when it has not run.
---@return "registered"|"unavailable"|nil
function M.state()
  return STATE
end

return M
