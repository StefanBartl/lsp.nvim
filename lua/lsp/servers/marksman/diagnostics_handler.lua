---@module 'lsp.servers.marksman.diagnostics_handler'
--- Marksman diagnostics filter factory.
--- Filters diagnostics based on multiple config heuristics:
---  - suppressed_message_patterns (Lua patterns, anchored or partial)
---  - suppressed_message_substrings (plain substring matching, case-sensitive)
---  - suppressed_codes (string or number matching diagnostic.code)
---  - suppress_toc_checks (filter any diag mentioning "TOC" / "table of contents")
---  - missing_doc_links_pattern (legacy single-pattern toggle)
---  - Hint-severity diagnostics, gated by lsp.servers.marksman.hints (the
---    "lightbulb" toggle: <leader>lb / :LspMdHints)
--- The filter is conservative: it only removes diagnostics that match **any**
--- of the configured suppression checks. Non-matching diagnostics are left untouched.
---
--- M.make_handler() returns a function suitable for use as a handler for
--- "textDocument/publishDiagnostics" (same signature as vim.lsp.handlers).
---
--- Also caches the last raw (server-side) diagnostics per URI so
--- lsp.servers.marksman.hints can force an instant re-filter (e.g. on
--- <leader>lb / :LspMdHints) without waiting for the next server push —
--- marksman uses push diagnostics, so there is no "pull current state" LSP
--- request to fall back on.
local cfg = require("lsp.servers.marksman.config")
local env_links = require("lsp.core.env_links")
local file_key = require("lsp.core.workspace_projects").key

local M = {}

-- LSP wire-protocol severity for "Hint" (matches vim.diagnostic.severity.HINT)
local HINT_SEVERITY = 4

-- uri -> raw diagnostics[] as last received from marksman (pre hint-filter)
local last_raw = {}
-- uri -> { err, result, ctx, config } from the last publishDiagnostics call
local last_meta = {}

--- Whether env-link resolution is on (`languages.env_links`, default on). Read
--- per call rather than captured: the config layers can change after this
--- module loads, and a failed read must mean "on", the default.
--- @return boolean
local function env_links_enabled()
  local ok, config = pcall(require, "lsp.config")
  if not ok then
    return true
  end
  local languages = config.get().languages
  return type(languages) ~= "table" or languages.env_links ~= false
end

--- Whether the in-process env-link client is running. While it is, it reports
--- the broken env links itself (`lsp.core.env_links_server`, which also covers
--- the ones marksman never reports), so marksman's own message about one would
--- be a second diagnostic on the same range. A failed load means "not running".
--- @return boolean
local function env_client_active()
  local ok, server = pcall(require, "lsp.core.env_links_server")
  return ok and type(server.active) == "function" and server.active() == true
end

--- Whether the in-process client reports the env links of the document `uri`
--- names: it is running AND attached to that document's buffer. marksman
--- publishes for the whole workspace, files nobody has open included; the
--- client answers for loaded buffers only, so for any other document dropping
--- marksman's message would leave the broken link unreported.
--- (Files are compared by path, not through `vim.uri_to_bufnr`, which creates
--- a buffer for a name that has none.)
--- @param uri string|nil
--- @return boolean
local function env_client_covers(uri)
  if type(uri) ~= "string" or not env_client_active() then
    return false
  end
  local ok, fname = pcall(vim.uri_to_fname, uri)
  if not ok or type(fname) ~= "string" then
    return false
  end
  local want = file_key(fname)
  local name = require("lsp.core.env_links_server").NAME
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      if bufname ~= "" and file_key(bufname) == want then
        return #vim.lsp.get_clients({ bufnr = bufnr, name = name }) > 0
      end
    end
  end
  return false
end

--- Helper: safe conversion of diag.code to string for comparison
--- @param code any
--- @return string
local function code_to_string(code)
  if code == nil then
    return ""
  end
  if type(code) == "string" then
    return code
  end
  if type(code) == "number" then
    return tostring(code)
  end
  -- some servers put complex code objects; try to stringify
  local ok, s = pcall(vim.inspect, code)
  if ok and type(s) == "string" then
    return s
  end
  return ""
end

--- Helper: check if message matches any lua patterns
--- @param msg string
--- @param patterns string[]
--- @return boolean
local function matches_any_pattern(msg, patterns)
  if not patterns or type(patterns) ~= "table" then
    return false
  end
  for _, patt in ipairs(patterns) do
    if type(patt) == "string" and patt ~= "" then
      -- pcall to guard against bad patterns
      local ok, res = pcall(function()
        return msg:match(patt)
      end)
      if ok and res then
        return true
      end
    end
  end
  return false
end

--- Helper: check if message contains any of the plain substrings
--- @param msg string
--- @param substrings string[]
--- @return boolean
local function contains_any_substring(msg, substrings)
  if not substrings or type(substrings) ~= "table" then
    return false
  end
  for _, sub in ipairs(substrings) do
    if type(sub) == "string" and sub ~= "" and msg:find(sub, 1, true) then
      return true
    end
  end
  return false
end

--- Helper: check code membership
--- @param diag_code any
--- @param list table
--- @return boolean
local function code_in_list(diag_code, list)
  if not list or type(list) ~= "table" then
    return false
  end
  local sdiag = code_to_string(diag_code)
  for _, v in ipairs(list) do
    if type(v) == "number" then
      if tonumber(sdiag) == v then
        return true
      end
    elseif type(v) == "string" then
      if sdiag == v then
        return true
      end
    else
      -- fallback stringify compare
      if sdiag == tostring(v) then
        return true
      end
    end
  end
  return false
end

--- The pre-existing suppression rules (1-5 below), unchanged, as one function
--- so the env-link verdict can be decided *before* them: a link whose target
--- is `$VAR/...` is judged by whether the file it names exists, not by a
--- pattern that would hide the broken ones together with the false alarms.
--- @param msg string
--- @param diag_code any
--- @return boolean suppressed
local function suppressed_by_rules(msg, diag_code)
  local suppressed = false

  -- 1) explicit missing-doc-link legacy pattern (kept for backward compat)
  if
    cfg.suppress_missing_doc_links
    and cfg.missing_doc_links_pattern
    and cfg.missing_doc_links_pattern ~= ""
  then
    if pcall(function()
      return msg:match(cfg.missing_doc_links_pattern)
    end) then
      if msg:match(cfg.missing_doc_links_pattern) then
        suppressed = true
      end
    end
  end

  -- 2) general Lua pattern list
  if not suppressed and cfg.suppressed_message_patterns then
    if matches_any_pattern(msg, cfg.suppressed_message_patterns) then
      suppressed = true
    end
  end

  -- 3) plain substring matches (fast, case-sensitive)
  if not suppressed and cfg.suppressed_message_substrings then
    if contains_any_substring(msg, cfg.suppressed_message_substrings) then
      suppressed = true
    end
  end

  -- 4) TOC heuristic (case-insensitive match of 'toc' or 'table of contents')
  if not suppressed and cfg.suppress_toc_checks then
    local low = msg:lower()
    if low:find("toc", 1, true) or low:find("table of contents", 1, true) then
      suppressed = true
    end
  end

  -- 5) diagnostic code based suppression
  if not suppressed and cfg.suppressed_codes then
    if code_in_list(diag_code, cfg.suppressed_codes) then
      suppressed = true
    end
  end

  return suppressed
end

--- Main filter function for diagnostics of a single result.
--- @param diagnostics table[] diagnostics array from server
--- @param env_client? boolean the in-process env-link client reports this document's broken env links (see `env_client_covers`); nil = ask whether it runs at all
--- @return table[] filtered diagnostics
function M.filter_diagnostics(diagnostics, env_client)
  if not diagnostics or type(diagnostics) ~= "table" then
    return diagnostics
  end

  local hints_enabled = true
  do
    local ok, hints = pcall(require, "lsp.servers.marksman.hints")
    if ok and type(hints.enabled) == "function" then
      hints_enabled = hints.enabled()
    end
  end

  -- Once per push, not per diagnostic: a workspace push carries hundreds, and
  -- each `env_links_enabled()` is a `require` and a config read.
  local env_links_on = env_links_enabled()
  if env_client == nil then
    env_client = env_links_on and env_client_active()
  end
  env_client = env_links_on and env_client

  local out = {}
  for i = 1, #diagnostics do
    local d = diagnostics[i]
    local msg = (type(d) == "table" and type(d.message) == "string") and d.message or ""
    local diag_code = d.code or (d.user_data and d.user_data.lsp and d.user_data.lsp.code) -- try common alternate locations

    local suppressed
    local verdict, resolved_env
    if env_links_on then
      verdict, resolved_env = env_links.verdict(msg)
    end
    if verdict == "drop" then
      -- The server says the document does not exist, but the file the env
      -- reference names does: a false alarm.
      suppressed = true
    elseif verdict == "keep" then
      -- A genuinely broken env link. Shown even though the blanket
      -- `suppress_missing_doc_links` would hide it, now that it is known to be
      -- true -- with the path it was looked up at. The in-process client says
      -- the same, in its own words, when it is running: then only it does.
      suppressed = env_client
    else
      suppressed = suppressed_by_rules(msg, diag_code)
    end

    -- 6) "lightbulb" toggle: hide Hint-severity suggestions on demand
    if not suppressed and not hints_enabled and d.severity == HINT_SEVERITY then
      suppressed = true
    end

    -- If not suppressed, keep diagnostic
    if not suppressed then
      if verdict == "keep" and resolved_env and not env_client then
        d = vim.tbl_extend("force", {}, d, {
          message = ("%s (resolved to %s)"):format(msg, resolved_env.path),
        })
      end
      table.insert(out, d)
    end
  end
  return out
end

---@internal
--- The files of all loaded buffers, as `workspace_projects.key` spells them.
---
--- Files are compared by path, not by URI, and not resolved through
--- `vim.uri_to_bufnr`: that one *creates* a buffer when none exists, which is
--- the whole problem below. A raw URI comparison does not work either: marksman
--- spells `file:///e%3A/repos/x.md` where `vim.uri_from_bufnr` says
--- `file:///e:/repos/x.md` (measured on Windows), so every open buffer looked
--- closed.
---@return table<string, true>
local function open_files()
  local open = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" then
        open[file_key(name)] = true
      end
    end
  end
  return open
end

---@internal
--- Whether the file `uri` names is among `open` (see `open_files`).
---@param uri string
---@param open table<string, true>
---@return boolean
local function still_open(uri, open)
  local ok, fname = pcall(vim.uri_to_fname, uri)
  if not ok or type(fname) ~= "string" then
    return false
  end
  return open[file_key(fname)] == true
end

--- Re-run M.filter_diagnostics against the last raw diagnostics for every
--- open URI and re-publish. Called by lsp.servers.marksman.hints when the
--- toggle flips, so already-open buffers update immediately instead of
--- waiting for the next server push.
---
--- Only the ones still open. This used to republish every URI it had ever
--- cached, and `vim.uri_to_bufnr` inside Neovim's handler *creates* a buffer
--- for a name that has none -- so one `:LspMdHints` brought back a buffer for
--- every markdown file the session had visited, diagnostics included.
--- Measured: close a file, toggle, and it is back with its diagnostic on it.
---
--- Closing one also drops it from the cache, which is what keeps `last_raw`
--- and `last_meta` from growing for the whole session -- they are keyed by URI
--- and nothing else ever removed an entry.
---@return nil
function M.republish_all()
  local default_handler = vim.lsp.handlers["textDocument/publishDiagnostics"]
  local open = open_files()
  for uri, diags in pairs(last_raw) do
    local meta = last_meta[uri]
    if not still_open(uri, open) then
      last_raw[uri] = nil
      last_meta[uri] = nil
    elseif meta then
      local filtered = M.filter_diagnostics(diags, env_client_covers(uri))
      local new_result = vim.tbl_deep_extend("force", {}, meta.result, { diagnostics = filtered })
      default_handler(meta.err, new_result, meta.ctx, meta.config)
    end
  end
end

--- Build the "textDocument/publishDiagnostics" handler for marksman.
---@return fun(err:any, result:table|nil, ctx:table, config:table)
function M.make_handler()
  -- Keep reference to default handler to delegate after filtering
  local default_handler = vim.lsp.handlers["textDocument/publishDiagnostics"]

  return function(err, result, ctx, config)
    -- Delegate quickly if shape not as expected
    if not result or not result.diagnostics or not ctx or not ctx.client_id then
      return default_handler(err, result, ctx, config)
    end

    local client = vim.lsp.get_client_by_id(ctx.client_id)
    if not client or client.name ~= "marksman" then
      return default_handler(err, result, ctx, config)
    end

    -- Cache the raw event so the hints toggle can replay it instantly
    if result.uri then
      last_raw[result.uri] = result.diagnostics
      last_meta[result.uri] = { err = err, result = result, ctx = ctx, config = config }
    end

    -- Filter diagnostics using configured rules
    local diags = result.diagnostics
    local filtered = M.filter_diagnostics(diags, env_client_covers(result.uri))

    -- If the filtering removed or rewrote any entry (a kept env link gets the
    -- path it was looked up at), clone result with new diagnostics
    local changed = #filtered ~= #diags
    for i = 1, #filtered do
      if filtered[i] ~= diags[i] then
        changed = true
        break
      end
    end
    if changed then
      local new_result = vim.tbl_deep_extend("force", {}, result, { diagnostics = filtered })
      return default_handler(err, new_result, ctx, config)
    end

    -- Otherwise delegate original result
    return default_handler(err, result, ctx, config)
  end
end

return M
