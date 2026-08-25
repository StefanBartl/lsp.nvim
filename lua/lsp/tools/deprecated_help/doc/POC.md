# Strategy & architecture (short overview)

The idea is an extensible pipeline that post-processes existing LSP diagnostics and offers server- and topic-specific actions. Core ideas:

* A central "publishDiagnostics" wrapper module (the existing `lsp_common`) stays the source of the events and calls registered server handlers.
* Per-server modules (e.g. `lua_ls`, `uv_doc`) register with the wrapper and filter only the diagnostics relevant to them.
* A small "catch" module encapsulates the extraction logic (range → symbol, message → heuristic extraction); it can later be replaced/complemented by treesitter.
* An "action" module per topic (e.g. `uv_doc`) decides which action to offer: `:help`, opening external documentation, a fix suggestion, a code action, tests, etc.
* Extensibility: a registration table + policy plugins (e.g. mdn_lookup, go_pkg_lookup) allow later plugins without changing the core.

---

# Flow / data flow

1. The LSP sends `publishDiagnostics`.
2. `lsp_common.wrapper` calls the original handler (unchanged) and afterwards the registered callbacks.
3. The server callback (e.g. `lua_ls`) filters on server name + severity.
4. For every diagnostic:

   * `catch.extract_symbol()` determines the symbol (range / heuristics).
   * The topic detector (e.g. `uv_doc.is_uv_related()`) decides whether an action makes sense.
   * If so: produce an annotated notify message + a buffer-local mapping (once per symbol).
   * The mapping leads to an action: open help, open URL, popup with a snippet, and so on.
5. Caching makes sure that mapping/notify happens only once per buffer/symbol.

---

# Heuristics for detecting libuv errors (examples)

* Message-text keywords: `libuv`, `uv_`, `uv.`, `uv_loop`, `uv_handle`, `UV_E*` (errno names).
* Symbol name: the extracted symbol starts with `uv_` or contains `uv.` or `uv:`.
* Diagnostic source: some servers annotate `source` (e.g. `lua_ls`, `sumneko_lua`) → check it.
* Context: if filetype == "lua" and server == "lua_ls", raise the preference.

---

# Data sources for helper actions

* libuv API documentation (online) — a fixed URL mapping: symbol → `http(s)://libuv.org/docs.html` (or a concrete URL pattern).
* Local help texts: if the symbol exists in `:help` (for vim/neovim-specific APIs).
* MDN for JS/Node: MDN API URLs via symbol lookup.
* Go: the pkg.go.dev pattern `https://pkg.go.dev/<module>#<symbol>`.

---

# Security & UX considerations

* No changes to the original LSP handler logic (non-breaking).
* Actions are never automatically invasive (no automatic editing); only suggestive: notify + mapping.
* Mappings are buffer-local and deduplicated.
* Opening external URLs cross-platform is intercepted safely (Linux/macOS `xdg-open`/`open`, Windows `start`).

---

# Proof of concept: `lsp.tools.uv_doc` (PoC module)

The module implementation below is a PoC that integrates into the intended architecture. It:

* detects libuv-related diagnostics in Lua files,
* extracts the symbol,
* offers a buffer-local mapping that opens the matching libuv documentation in the browser,
* annotates the diagnostic message (optional).

The comments are in English (project convention). EmmyLua annotations are included.

```lua
---@module 'lsp.tools.uv_doc'
--- Proof-of-concept module to handle libuv-related diagnostics for lua_ls.
--- - Detect libuv-related diagnostics
--- - Extract symbol or token
--- - Annotate diagnostics (optional)
--- - Add buffer-local mapping to open an external documentation URL for the symbol
--- All comments are in English per project convention.

local uv = vim.loop
local api = vim.api
local fn = vim.fn
local M = {}

-- Configuration defaults with explicit known-length string[] using indexed form
---@type table
local defaults = {
  help_mapping = "<leader>uv", -- mapping to open doc for detected symbol
  map_opts = { noremap = true, silent = true }, -- buffer keymap options
  annotate_diagnostics = true,
  diagnostic_hint = "", -- filled in setup
  doc_url_template = "https://libuv.org/docs.html#%s", -- naive template; adapt as needed
  os_open_cmd = nil, -- computed
}

-- per-buffer cache to avoid duplicates
---@type table<number, table<string, boolean>>
local buf_cache = {}

--- Ensure per-buffer cache table exists
---@param bufnr number
---@return table<string, boolean>
local function ensure_buf_cache(bufnr)
  if buf_cache[bufnr] == nil then
    buf_cache[bufnr] = {}
  end
  return buf_cache[bufnr]
end

--- Return platform-appropriate opener command and args for a URL.
---@return function(url:string)
local function make_open_url()
  local uname = vim.loop.os_uname().sysname
  if uname == "Windows_NT" then
    return function(url)
      -- use start via cmd
      vim.fn.jobstart({ "cmd", "/c", "start", "", url }, { detach = true })
    end
  elseif uname == "Darwin" then
    return function(url)
      vim.fn.jobstart({ "open", url }, { detach = true })
    end
  else
    return function(url)
      vim.fn.jobstart({ "xdg-open", url }, { detach = true })
    end
  end
end

--- Escape a string for safe inclusion in URL fragment
---@param s string
---@return string
local function url_escape(s)
  if not s then return "" end
  -- simple percent-encoding for common characters
  return (s:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", string.byte(c)) end))
end

--- Determine whether a diagnostic is libuv-related.
--- Heuristics:
--- - message contains 'libuv' or 'uv_' prefix or 'UV_' errno like UV_EINVAL
---@param diag table
---@return boolean
local function diagnostic_is_uv_related(diag)
  if not diag or type(diag.message) ~= "string" then return false end
  local msg = string.lower(diag.message)
  if msg:match("libuv") then return true end
  if msg:match("uv[_%.]") then return true end
  if msg:match("uv_[%w_]+") then return true end
  if msg:match("uv[%u_%u%d]+") then return true end
  return false
end

--- Try to extract symbol text from diagnostic range or message.
---@param bufnr number
---@param diag table
---@return string
local function extract_symbol(bufnr, diag)
  -- try range-based extraction if available
  if diag.range then
    local s_row = diag.range.start.line or 0
    local s_col = diag.range.start.character or 0
    local e_row = (diag["end"] and diag["end"].line) or s_row
    local e_col = (diag["end"] and diag["end"].character) or s_col
    if s_row == e_row then
      local ok, line = pcall(api.nvim_buf_get_lines, bufnr, s_row, s_row + 1, false)
      if ok and line and line[1] then
        local text = line[1]:sub(s_col + 1, e_col)
        if text and text ~= "" then
          return text
        end
      end
    end
  end

  -- fallback: try to find uv-like token in message
  local msg = diag.message or ""
  local token = msg:match("([%w_]*uv[_%w]+)") or msg:match("([Uu][Vv]_[%w_]+)")
  if token and token ~= "" then return token end

  -- last fallback: word under diagnostic start position (best-effort)
  if diag.range and diag.range.start then
    local row = diag.range.start.line or 0
    local ok_line, line = pcall(api.nvim_buf_get_lines, bufnr, row, row + 1, false)
    if ok_line and line and line[1] then
      local l = line[1]
      local col = diag.range.start.character or 0
      col = math.max(0, math.min(#l, col))
      -- find word boundaries around col
      local i = col + 1
      while i > 0 and l:sub(i, i):match("[%w_%.]") do i = i - 1 end
      local s = i + 1
      i = col + 1
      while i <= #l and l:sub(i, i):match("[%w_%.]") do i = i + 1 end
      local e = i - 1
      local w = l:sub(s, e)
      if w and w ~= "" then return w end
    end
  end

  return ""
end

--- Open documentation in browser or fallback to notify.
---@param symbol string
---@param opts table
local function open_doc(symbol, opts)
  if not symbol or symbol == "" then
    vim.notify("uv_doc: no symbol to open", vim.log.levels.INFO)
    return
  end
  local safe_sym = url_escape(symbol)
  local url = string.format(opts.doc_url_template, safe_sym)
  local opener = opts.os_open_cmd or make_open_url()
  -- attempt to open; jobstart is used to avoid blocking
  pcall(opener, url)
  vim.notify("Opening documentation: " .. url, vim.log.levels.INFO)
end

--- Core handler for diagnostics from lua_ls (registered via lsp_common)
---@param err any
---@param result table
---@param ctx table
---@param config table
local function on_publish(err, result, ctx, config)
  if not result or not result.diagnostics then return end
  -- find client
  local client = nil
  if ctx and ctx.client_id then client = vim.lsp.get_client_by_id(ctx.client_id) end
  if not client or client.name ~= "lua_ls" then return end

  local bufnr = result.uri and vim.uri_to_bufnr(result.uri) or nil
  if not bufnr or not api.nvim_buf_is_loaded(bufnr) then return end

  local cache = ensure_buf_cache(bufnr)

  for _, diag in ipairs(result.diagnostics) do
    if diagnostic_is_uv_related(diag) then
      local symbol = extract_symbol(bufnr, diag)
      if symbol == nil or symbol == "" then
        symbol = (diag.message or ""):match("([%w_%.:]+)") or ""
      end
      if symbol ~= "" and not cache[symbol] then
        cache[symbol] = true

        -- annotate diagnostic message if desired (non-destructive: append hint)
        if M.opts.annotate_diagnostics and type(diag.message) == "string" then
          if not diag.message:find(M.opts.diagnostic_hint, 1, true) then
            diag.message = diag.message .. M.opts.diagnostic_hint
          end
        end

        -- notify user and create buffer-local mapping
        local hint = string.format("%s — press %s to open libuv docs for '%s'", diag.message, M.opts.help_mapping, symbol)
        vim.notify(hint, vim.log.levels.WARN)

        -- set buffer-local mapping once
        local lhs = M.opts.help_mapping
        local rhs = function()
          open_doc(symbol, M.opts)
        end
        -- ensure we don't create duplicate mapping
        local existing = api.nvim_buf_get_keymap(bufnr, "n")
        local found = false
        for _, m in ipairs(existing) do
          if m.lhs == lhs then found = true; break end
        end
        if not found then
          vim.keymap.set("n", lhs, rhs, vim.tbl_extend("force", { buffer = bufnr, noremap = true, silent = true, desc = "Open libuv docs for " .. symbol }, M.opts.map_opts or {}))
        end
      end
    end
  end
end

--- Setup function to configure module and register callback
---@param user_opts table|nil
function M.setup(user_opts)
  M.opts = vim.tbl_deep_extend("force", defaults, user_opts or {})
  -- prepare diagnostic hint text
  M.opts.diagnostic_hint = " — press " .. M.opts.help_mapping .. " to open libuv docs"

  -- compute os_open_cmd if not provided
  if not M.opts.os_open_cmd then
    M.opts.os_open_cmd = make_open_url()
  end

  -- register callback with lsp_common if available; fallback to wrapping publishDiagnostics
  local ok, lsp_common = pcall(require, "myplugin.lsp_common")
  if ok and type(lsp_common.register_server_callback) == "function" then
    lsp_common.register_server_callback("lua_ls", on_publish)
  else
    -- fallback: wrap global publishDiagnostics (defensive; non-destructive)
    local orig = vim.lsp.handlers["textDocument/publishDiagnostics"]
    vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
      if orig then orig(err, result, ctx, config) end
      pcall(on_publish, err, result, ctx, config)
    end
  end
end

return M
```

---

# Integration / example configuration

* Place the files under `lua/lsp/tools/uv_doc.lua`.
* Call it from the main init/plugin file:

```lua
-- in init.lua or plugin config
require("lsp.tools.uv_doc").setup({
  help_mapping = "<leader>uv",
  doc_url_template = "https://libuv.org/API.html#%s", -- adapt if a different target is wanted
})
```

* Make sure that `myplugin.lsp_common` (or an analogous wrapper) is loaded, so that the callback registration works.

---

# Extension ideas & roadmap (concrete steps)

1. More robust symbol extraction:

   * Fall back to treesitter: extract the node text for complex expressions.
   * If the range spans several lines → read multiple lines, normalise.

2. Doc-source adapters:

   * Implement a small adapter interface: `adapter:lookup(symbol) -> { type = "url"|"help", target = "..." }`
   * Adapter examples: `uv_adapter`, `mdn_adapter`, `pkg_go_adapter`, `pkg_godoc_adapter`.
   * Prioritisation: local help > internal docs > external docs.

3. UI improvements:

   * Instead of only notify: a small floating window with a short summary + buttons (open doc / copy link / search the web).
   * Optional: a quickfix entry or a Telescope picker with the relevant links.

4. Testing:

   * Unit tests for the `extract_symbol` heuristics (stubs for buffer lines).
   * Integration test: simulate `publishDiagnostics` with uv messages and check mapping/notify/caching.

5. Further languages:

   * JS/TS: an MDN adapter (symbol -> MDN search URL).
   * Node.js errors: the Node API docs or `nodejs.org/api/<module>.html`.
   * Go: a `pkg.go.dev` adapter.

---

# Test plan (short)

* Unit: feed various `diag` fixtures (range present/absent, different messages) into `extract_symbol`; assert the expected output.
* Integration: trigger `publishDiagnostics` for a buffer with a lua_ls client; check that:

  * the mapping was created (api.nvim_buf_get_keymap)
  * notify was called (stub `vim.notify`).
  * calling `open_doc` starts a jobstart with the correct URL (mock `vim.fn.jobstart`).
* Cross-platform: check `open_doc` on Linux/Mac/Win.

---

# Conclusion (pragmatic notes)

* This PoC adds no invasive change to the code flow and is backwards compatible with the existing architecture (the original handler stays untouched).
* Next implementation steps: add the treesitter fallback, an adapter interface for several doc sources, a small UI component (floating window) for better UX.

---
