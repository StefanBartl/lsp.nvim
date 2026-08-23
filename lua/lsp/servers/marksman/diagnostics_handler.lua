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

local M = {}

-- LSP wire-protocol severity for "Hint" (matches vim.diagnostic.severity.HINT)
local HINT_SEVERITY = 4

-- uri -> raw diagnostics[] as last received from marksman (pre hint-filter)
local last_raw = {}
-- uri -> { err, result, ctx, config } from the last publishDiagnostics call
local last_meta = {}

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

--- Main filter function for diagnostics of a single result.
--- @param diagnostics table[] diagnostics array from server
--- @return table[] filtered diagnostics
function M.filter_diagnostics(diagnostics)
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

  local out = {}
  for i = 1, #diagnostics do
    local d = diagnostics[i]
    local msg = (type(d) == "table" and type(d.message) == "string") and d.message or ""
    local diag_code = d.code or (d.user_data and d.user_data.lsp and d.user_data.lsp.code) -- try common alternate locations

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

    -- 6) "lightbulb" toggle: hide Hint-severity suggestions on demand
    if not suppressed and not hints_enabled and d.severity == HINT_SEVERITY then
      suppressed = true
    end

    -- If not suppressed, keep diagnostic
    if not suppressed then
      table.insert(out, d)
    end
  end
  return out
end

--- Re-run M.filter_diagnostics against the last raw diagnostics for every
--- known URI and re-publish. Called by lsp.servers.marksman.hints when the
--- toggle flips, so already-open buffers update immediately instead of
--- waiting for the next server push.
---@return nil
function M.republish_all()
  local default_handler = vim.lsp.handlers["textDocument/publishDiagnostics"]
  for uri, diags in pairs(last_raw) do
    local meta = last_meta[uri]
    if meta then
      local filtered = M.filter_diagnostics(diags)
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
    local filtered = M.filter_diagnostics(diags)

    -- If the filtering removed any entries, clone result with new diagnostics
    if #filtered ~= #diags then
      local new_result = vim.tbl_deep_extend("force", {}, result, { diagnostics = filtered })
      return default_handler(err, new_result, ctx, config)
    end

    -- Otherwise delegate original result
    return default_handler(err, result, ctx, config)
  end
end

return M
