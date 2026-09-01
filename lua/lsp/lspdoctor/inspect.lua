---@module 'lsp.lspdoctor.inspect'
---@brief The `buffer` and `capabilities` reports.
---@description
--- What is attached to this buffer, and what it can do. `buffer` caps its
--- lists at `list_limit`; `capabilities` is the same report uncapped, plus
--- root_dir, workspace folders and the full capability set per client.
---
--- Both were named for their volume until 2026-08-29 -- `quick` and `deep` --
--- which said nothing about which of the two holds the capabilities.
---
---@see lsp.lspdoctor.health

local M = {}

local api = vim.api
local lsp = vim.lsp
local diag = vim.diagnostic

local Opts = {}

---@param opts table
function M.setup(opts)
  Opts = opts or {}
end

-- Utils -----------------------------------------------------------------------

---@param b boolean|nil
---@return string
local function yesno(b)
  return b and "yes" or "no"
end

---@param t string[]
---@param n integer
---@return string[]
local function take(t, n)
  local out = {}
  local len = math.min(#t, n)
  for i = 1, len do
    out[i] = t[i]
  end
  if #t > n then
    out[#out + 1] = string.format("…(+%d more)", #t - n)
  end
  return out
end

---@param list string[]
---@param value string
---@return boolean
local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

-- Collection ------------------------------------------------------------------

---@param bufnr integer
---@return table<string, vim.lsp.Client> clients_by_name, string[] names
local function collect_clients(bufnr)
  if type(bufnr) ~= "number" or not api.nvim_buf_is_valid(bufnr) then
    return {}, {}
  end
  local by_name, names = {}, {}
  local clients = lsp.get_clients({ bufnr = bufnr }) or {}
  for _, c in ipairs(clients) do
    local name = c.name or ("client#" .. tostring(c.id or "?"))
    by_name[name] = c
    names[#names + 1] = name
  end
  table.sort(names)
  return by_name, names
end

---@param bufnr integer
---@return table<string, integer> counts_by_sev, integer total
local function collect_diagnostics(bufnr)
  local counts = { ERROR = 0, WARN = 0, INFO = 0, HINT = 0 }
  if type(bufnr) ~= "number" or not api.nvim_buf_is_valid(bufnr) then
    return counts, 0
  end
  local items = diag.get(bufnr) or {}
  for _, d in ipairs(items) do
    local s = d.severity
    if s == vim.diagnostic.severity.ERROR then
      counts.ERROR = counts.ERROR + 1
    elseif s == vim.diagnostic.severity.WARN then
      counts.WARN = counts.WARN + 1
    elseif s == vim.diagnostic.severity.INFO then
      counts.INFO = counts.INFO + 1
    elseif s == vim.diagnostic.severity.HINT then
      counts.HINT = counts.HINT + 1
    end
  end
  return counts, #items
end

-- Checks ----------------------------------------------------------------------

---@param clients_by_name table<string, vim.lsp.Client>
---@return string[] unique_encs, string[] mismatches
local function check_offset_encoding(clients_by_name)
  local set, order = {}, {}
  for name, c in pairs(clients_by_name) do
    local enc = (c.offset_encoding or "utf-16")
    if not set[enc] then
      set[enc] = {}
    end
    table.insert(set[enc], name)
  end
  for enc, _ in pairs(set) do
    order[#order + 1] = enc
  end
  table.sort(order)
  local mismatches = {}
  if #order > 1 then
    for _, enc in ipairs(order) do
      table.insert(mismatches, string.format("%s: %s", enc, table.concat(set[enc], ", ")))
    end
  end
  return order, mismatches
end

---@param clients_by_name table<string, vim.lsp.Client>
---@return string[] conflicts
local function detect_conflicts(clients_by_name)
  local conflicts = {}
  local fmt, diagp = {}, {}
  for name, c in pairs(clients_by_name) do
    local caps = c.server_capabilities or {}
    if caps.documentFormattingProvider == true then
      fmt[#fmt + 1] = name
    end
    -- Only pull diagnostics are visible here: push diagnostics
    -- (`textDocument/publishDiagnostics`) carry no server capability,
    -- so a server that sends them cannot be counted as a provider.
    if caps.diagnosticProvider then
      diagp[#diagp + 1] = name
    end
  end
  if #fmt > 1 then
    table.sort(fmt)
    conflicts[#conflicts + 1] = "Formatting providers overlap: " .. table.concat(fmt, ", ")
  end
  if #diagp > 1 then
    table.sort(diagp)
    conflicts[#conflicts + 1] = "Diagnostics providers overlap: " .. table.concat(diagp, ", ")
  end
  return conflicts
end

---What conform would actually run on this buffer, asked of conform itself.
---
---`list_formatters_to_run` is conform's own answer and accounts for
---`stop_after_first` and its LSP-fallback logic, so this cannot drift from
---what a `:LspFormat` would do. Reimplementing the decision here would be a
---second opinion, and a report whose second opinion disagrees with reality is
---worse than one that says nothing.
---@param bufnr integer
---@return string[]|nil names # nil when conform is not installed.
---@return boolean lsp_after # Whether conform hands off to an LSP client too.
local function conform_chain(bufnr)
  local ok, conform = pcall(require, "conform")
  if not (ok and type(conform.list_formatters_to_run) == "function") then
    return nil, false
  end

  local ok_call, formatters, lsp_after = pcall(conform.list_formatters_to_run, bufnr)
  if not ok_call or type(formatters) ~= "table" then
    return nil, false
  end

  ---@type string[]
  local names = {}
  for _, f in ipairs(formatters) do
    names[#names + 1] = f.name
  end
  return names, lsp_after == true
end

---Which LSP client this report would name as the preferred formatter.
---
---**This decides nothing.** `lspdoctor.formatter_priority` orders this report
---and only this report -- it is namespaced under `lspdoctor` for exactly that
---reason. What actually formats a buffer is `lsp.formatter`: conform's chain
---for the filetype, with LSP as the fallback conform falls back *to*. On every
---filetype conform covers (lua, ts, js, json, css, html, cs, markdown, sh) no
---LSP client formats at all, whatever this function returns.
---
---The report says so out loud below. It used to print `Winner: **eslint**` on
---a TypeScript buffer that `prettierd` was formatting -- a diagnostic tool
---naming the wrong culprit, which is the one thing a diagnostic tool must not
---do.
---@param clients_by_name table<string, vim.lsp.Client>
---@return string|nil winner, string[] candidates, string reason
local function pick_formatter(clients_by_name)
  local candidates = {}
  for name, c in pairs(clients_by_name) do
    local caps = c.server_capabilities or {}
    if caps.documentFormattingProvider == true then
      candidates[#candidates + 1] = name
    end
  end
  table.sort(candidates)

  if #candidates == 0 then
    return nil, candidates, "no formatting provider"
  end

  for _, prefer in ipairs(Opts.formatter_priority or {}) do
    if contains(candidates, prefer) then
      return prefer, candidates, "priority list"
    end
  end

  return candidates[1], candidates, "alphabetical fallback"
end

-- Report generation -----------------------------------------------------------

---@param mode '"buffer"'|'"capabilities"'
---@param bufnr integer
---@return string[] lines, table report
local function generate_report(mode, bufnr)
  local lines = {}
  local report = { mode = mode, ok = true }

  local clients_by_name, names = collect_clients(bufnr)
  local counts, total = collect_diagnostics(bufnr)

  -- Clients
  table.insert(lines, "### LSP Clients (current buffer)")
  if #names == 0 then
    table.insert(lines, "No LSP client attached")
  else
    local display = mode == "buffer" and take(names, Opts.list_limit or 10) or names
    for _, n in ipairs(display) do
      table.insert(lines, string.format("- `%s`", n))
    end
  end
  table.insert(lines, "")

  -- Diagnostics
  table.insert(lines, "### Diagnostics (current buffer)")
  table.insert(
    lines,
    string.format(
      "Total: **%d** [ERROR: %d, WARN: %d, INFO: %d, HINT: %d]",
      total,
      counts.ERROR,
      counts.WARN,
      counts.INFO,
      counts.HINT
    )
  )
  table.insert(lines, "")

  -- Conflicts
  if Opts.show_conflicts and #names > 1 then
    local conf = detect_conflicts(clients_by_name)
    table.insert(lines, "### Provider Conflicts")
    if #conf > 0 then
      for _, c in ipairs(conf) do
        table.insert(lines, "⚠️  " .. c)
      end
    else
      table.insert(lines, "✅ No obvious overlaps detected")
    end
    table.insert(lines, "")
  end

  -- Offset encoding
  local encs, mismatches = check_offset_encoding(clients_by_name)
  if #encs > 0 then
    table.insert(lines, "### Offset Encodings")
    if #mismatches > 0 then
      table.insert(lines, "⚠️  **Mismatch detected:**")
      for _, m in ipairs(mismatches) do
        table.insert(lines, "   - " .. m)
      end
      report.ok = false
    else
      table.insert(lines, "✅ All clients: `" .. encs[1] .. "`")
    end
    table.insert(lines, "")
  end

  -- Formatter: what actually runs first, then what this report merely ranks.
  local winner, all, reason = pick_formatter(clients_by_name)
  table.insert(lines, "### Formatter")

  local chain, lsp_after = conform_chain(bufnr)
  if chain == nil then
    table.insert(lines, "Runs: *(conform.nvim not installed -- LSP formatting only)*")
  elseif #chain == 0 then
    table.insert(
      lines,
      ("Runs: %s"):format(
        lsp_after and "the LSP client below (no conform formatter for this filetype)"
          or "*(nothing -- no conform formatter and no LSP formatting provider)*"
      )
    )
  else
    table.insert(
      lines,
      ("Runs: **%s** (conform)%s"):format(
        table.concat(chain, " -> "),
        lsp_after and ", then the LSP client below" or ""
      )
    )
  end

  table.insert(lines, "")
  table.insert(
    lines,
    "LSP clients able to format: " .. (#all == 0 and "*(none)*" or table.concat(all, ", "))
  )
  table.insert(lines, ("Preferred among them: **%s** (%s)"):format(winner or "(none)", reason))
  table.insert(
    lines,
    "*Report only.* `lspdoctor.formatter_priority` ranks this line and nothing "
      .. "else -- it does not choose what formats the buffer. The `Runs:` line above does."
  )
  table.insert(lines, "")

  -- `capabilities` only: everything the capped `buffer` report leaves out
  if mode == "capabilities" then
    -- Workspace
    if Opts.show_workspace and #names > 0 then
      for _, n in ipairs(names) do
        local c = clients_by_name[n]
        table.insert(lines, string.format("### Workspace: %s", n))
        local root = (c.config and c.config.root_dir) or c.root_dir
        table.insert(lines, "  root_dir: `" .. tostring(root) .. "`")

        local ws = {}
        if c.workspace_folders and type(c.workspace_folders) == "table" then
          for _, f in ipairs(c.workspace_folders) do
            ws[#ws + 1] = (f.name or f.uri or "?")
          end
        end

        if #ws > 0 then
          table.insert(lines, "  workspace_folders:")
          for _, w in ipairs(ws) do
            table.insert(lines, "    - " .. w)
          end
        else
          table.insert(lines, "  workspace_folders: *(none)*")
        end
        table.insert(lines, "")
      end
    end

    -- Capabilities
    if Opts.show_capabilities and #names > 0 then
      for _, n in ipairs(names) do
        local c = clients_by_name[n]
        local caps = c.server_capabilities or {}
        table.insert(lines, string.format("### Capabilities: %s", n))
        table.insert(
          lines,
          string.format("  offsetEncoding: `%s`", tostring(c.offset_encoding or "nil"))
        )
        table.insert(
          lines,
          string.format("  completionProvider: %s", yesno(caps.completionProvider ~= nil))
        )
        table.insert(
          lines,
          string.format("  definitionProvider: %s", yesno(caps.definitionProvider ~= nil))
        )
        table.insert(
          lines,
          string.format("  documentFormatting: %s", yesno(caps.documentFormattingProvider == true))
        )
        table.insert(
          lines,
          string.format("  codeAction: %s", yesno(caps.codeActionProvider ~= nil))
        )
        table.insert(
          lines,
          string.format("  semanticTokens: %s", yesno(caps.semanticTokensProvider ~= nil))
        )
        table.insert(lines, string.format("  inlayHints: %s", yesno(caps.inlayHintProvider ~= nil)))
        table.insert(lines, string.format("  codeLens: %s", yesno(caps.codeLensProvider ~= nil)))
        table.insert(lines, "")
      end
    end
  end

  -- Summary
  if #names == 0 then
    report.ok = false
    report.summary = "No LSP client attached"
  else
    report.summary = string.format(
      "Clients: %d, Diagnostics: %d (E:%d W:%d I:%d H:%d)",
      #names,
      total,
      counts.ERROR,
      counts.WARN,
      counts.INFO,
      counts.HINT
    )
  end

  table.insert(lines, 1, "")
  table.insert(lines, 1, report.summary)
  table.insert(lines, 1, string.rep("─", 50))

  return lines, report
end

---@param bufnr integer
---@return string[] lines, table report
function M.buffer(bufnr)
  return generate_report("buffer", bufnr)
end

---@param bufnr integer
---@return string[] lines, table report
function M.capabilities(bufnr)
  return generate_report("capabilities", bufnr)
end

return M
