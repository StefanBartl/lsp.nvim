# Strategie & Architektur (Kurzüberblick)

Man entwickelt eine erweiterbare Pipeline, die bestehende LSP-Diagnostik weiterverarbeitet und server-/themen-spezifische Aktionen anbietet. Kernideen:

* Ein zentrales "publishDiagnostics"-Wrapper-Modul (bestehendes `lsp_common`) bleibt Quelle der Ereignisse und ruft registrierte Server-Handler auf.
* Pro-Server-Module (z. B. `lua_ls`, `uv_doc`) registrieren sich beim Wrapper und filtern nur die für sie relevanten Diagnostics.
* Ein kleines "catch"-Modul kapselt Extraktionslogik (Range → Symbol, Nachricht → heuristische Extraktion); kann später mit treesitter ersetzt/ergänzt werden.
* Ein "action"-Modul pro Thema (z. B. `uv_doc`) entscheidet, welche Aktion anzubieten ist: `:help`, externe Doku öffnen, Vorschlag zum Fix, Code-Action, Tests etc.
* Erweiterbarkeit: Registrierungstabelle + Policy-Plugins (z. B. mdn_lookup, go_pkg_lookup) erlauben spätere Plugins ohne Änderung des Core.

---

# Ablauf / Datenfluss

1. LSP sendet `publishDiagnostics`.
2. `lsp_common.wrapper` ruft original handler (unverändert) und danach registrierte Callbacks.
3. Server-Callback (z. B. `lua_ls`) filtert auf server-name + severity.
4. Für jede Diagnostic:

   * `catch.extract_symbol()` ermittelt symbol (range / heuristics).
   * Thema-Detector (z. B. `uv_doc.is_uv_related()`) entscheidet, ob Aktion sinnvoll ist.
   * Falls ja: Erzeuge annotierte Notify-Nachricht + buffer-lokales Mapping (einmal pro symbol).
   * Mapping führt zu Aktion: open help, open URL, popup mit snippet, v.s.
5. Caching sorgt dafür, dass pro Buffer/Symbol nur einmal gemappt/notify ausgeführt wird.

---

# Heuristiken zum Erkennen von libuv-Fehlern (Beispiele)

* Nachrichtstext-Keywords: `libuv`, `uv_`, `uv.` , `uv_loop`, `uv_handle`, `UV_E*` (errno names).
* Symbol-Name: extrahiertes Symbol beginnt mit `uv_` oder beinhaltet `uv.` oder `uv:`.
* Diagnostic Source: some servers annotate `source` (z. B. `lua_ls`, `sumneko_lua`) → prüfen.
* Kontext: wenn filetype == "lua" und server == "lua_ls" erhöhte Präferenz.

---

# Datenquellen für Hilfs-Aktionen

* libuv API-Dokumentation (online) — feste URL-Mapping: symbol → `http(s)://libuv.org/docs.html` (oder konkrete URL pattern).
* Lokale Hilfetexte: falls symbol in `:help` existiert (für vim/neovim-spezifische APIs).
* MDN für JS/Node: MDN-API-URLs per symbol lookup.
* Go: pkg.go.dev pattern `https://pkg.go.dev/<module>#<symbol>`.

---

# Sicherheits- & UX-Überlegungen

* Keine Änderungen an originaler LSP-Handler-Logik (non-breaking).
* Aktionen niemals automatisch invasive (kein automatisches Editieren); nur suggestive: notify + mapping.
* Mappings buffer-local & dedupliziert.
* Cross-platform Öffnen externer URLs sicher abfangen (Linux/macOS `xdg-open`/`open`, Windows `start`).

---

# Proof-of-Concept: `lsp.tools.uv_doc` (PoC-Modul)

Die folgende Modul-Implementierung ist ein PoC, das sich in die vorgesehene Architektur integriert. Es:

* erkennt libuv-bezogene Diagnostics in Lua-Dateien,
* extrahiert das Symbol,
* bietet eine buffer-lokale Mapping an, die die passende libuv-Doku im Browser öffnet,
* annotiert die Diagnostic-Nachricht (optional).

Die Kommentare sind auf Englisch (Projektkonvention). EmmyLua-Annotationen sind enthalten.

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

# Integration / Beispielkonfiguration

* Dateien ablegen unter `lua/lsp/tools/uv_doc.lua`.
* In der Haupt-Init/Plugin-Datei aufrufen:

```lua
-- in init.lua or plugin config
require("lsp.tools.uv_doc").setup({
  help_mapping = "<leader>uv",
  doc_url_template = "https://libuv.org/API.html#%s", -- anpassen falls gewünschtes Ziel
})
```

* Sicherstellen, dass `myplugin.lsp_common` (oder analoger wrapper) geladen ist, damit die Callback-Registrierung funktioniert.

---

# Erweiterungsideen & Roadmap (konkrete Schritte)

1. Robustere Symbol-Extraktion:

   * Fallback auf Treesitter: bei komplexen Expressions das Node-Text extrahieren.
   * Wenn Range mehrzeilig ist → read multiple lines, normalize.

2. Dokumentsource-Adapter:

   * Implementiere ein kleines Adapter-Interface: `adapter:lookup(symbol) -> { type = "url"|"help", target = "..." }`
   * Adapter-Beispiele: `uv_adapter`, `mdn_adapter`, `pkg_go_adapter`, `pkg_godoc_adapter`.
   * Priorisierung: local help > internal docs > external docs.

3. UI-Verbesserungen:

   * statt nur notify: ein kleines floating window mit Kurzinfo + Buttons (Open doc / Copy link / Search web).
   * optional: quickfix-Eintrag oder Telescope-Picker mit relevanten Links.

4. Testing:

   * Unit Tests für `extract_symbol`-Heuristiken (Stubs für buffer lines).
   * Integrationstest: Simuliere `publishDiagnostics` mit uv-Messages und prüfe Mapping/Notify/Caching.

5. Weitere Sprachen:

   * JS/TS: MDN-Adapter (symbol -> MDN search URL).
   * Node.js Errors: Node API docs oder `nodejs.org/api/<module>.html`.
   * Go: `pkg.go.dev` Adapter.

---

# Testplan (kurz)

* Unit: feed verschiedene `diag`-Fixtures (range present/absent, different messages) an `extract_symbol`; assert expected output.
* Integration: trigger `publishDiagnostics` für eine Buffer mit lua_ls client; prüfen:

  * mapping erstellt (api.nvim_buf_get_keymap)
  * notify aufgerufen (stuben `vim.notify`).
  * Aufruf `open_doc` öffnet jobstart mit korrekter URL (mock `vim.fn.jobstart`).
* Cross-platform: prüfen `open_doc` auf Linux/Mac/Win.

---

# Abschluss (Pragmatische Hinweise)

* Dieses PoC fügt keine invasive Änderung am Codeflow hinzu und ist rückwärtskompatibel zur bestehenden Architektur (original handler bleibt unangetastet).
* Nächste Implementationsschritte: Treesitter-Fallback einpflegen, Adapter-Interface für mehrere Doc-Quellen, kleine UI-Komponente (Floating window) für bessere UX.

---
