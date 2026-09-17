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

---@type Lsp.Doctor.Options
local Opts = {}

---@param opts Lsp.Doctor.Options
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

-- Collection ------------------------------------------------------------------

--- Every client on the buffer, one entry each, sorted.
---
--- Keyed by nothing: this used to build a `name -> client` map and a parallel
--- list of names, which silently loses a client whenever two of them share a
--- name -- two `lua_ls` for two roots in a monorepo, the same server started
--- twice for different projects. The map kept the last one, the list held the
--- name twice, and the report then printed one client's data under both
--- entries while the other was invisible to every check that walked the map.
---
--- Measured: two `lua_ls`, one `utf-16` and one `utf-8`, produced
--- "✅ All clients: `utf-8`", `ok = true` and the same `root_dir` printed
--- twice -- an encoding mismatch missed by the very section that exists to
--- catch it.
---
--- `label` is the name, and only becomes `name#id` where the name is not
--- unique on this buffer, so the usual report reads exactly as before.
---@param bufnr integer
---@return Lsp.Doctor.InspectClient[] entries
local function collect_clients(bufnr)
  if type(bufnr) ~= "number" or not api.nvim_buf_is_valid(bufnr) then
    return {}
  end

  ---@type Lsp.Doctor.InspectClient[]
  local entries = {}
  local seen = {}
  for _, c in ipairs(lsp.get_clients({ bufnr = bufnr }) or {}) do
    local name = c.name or ("client#" .. tostring(c.id or "?"))
    seen[name] = (seen[name] or 0) + 1
    entries[#entries + 1] = { client = c, name = name, label = name }
  end

  for _, e in ipairs(entries) do
    if seen[e.name] > 1 then
      e.label = ("%s#%s"):format(e.name, tostring(e.client.id or "?"))
    end
  end

  -- By name first so the report keeps its alphabetical order, then by id so
  -- two clients of one name have a stable order between runs.
  table.sort(entries, function(a, b)
    if a.name ~= b.name then
      return a.name < b.name
    end
    return (a.client.id or 0) < (b.client.id or 0)
  end)

  return entries
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

---@param entries Lsp.Doctor.InspectClient[]
---@return string[] unique_encs, string[] mismatches
local function check_offset_encoding(entries)
  local set, order = {}, {}
  -- Over the list, not a map: `pairs` on a map also made the order of the
  -- names inside one encoding group vary between runs, so two reports of an
  -- unchanged session did not diff clean.
  for _, e in ipairs(entries) do
    local enc = (e.client.offset_encoding or "utf-16")
    if not set[enc] then
      set[enc] = {}
    end
    set[enc][#set[enc] + 1] = e.label
  end
  for enc, _ in pairs(set) do
    order[#order + 1] = enc
  end
  table.sort(order)
  local mismatches = {}
  if #order > 1 then
    for _, enc in ipairs(order) do
      mismatches[#mismatches + 1] = string.format("%s: %s", enc, table.concat(set[enc], ", "))
    end
  end
  return order, mismatches
end

---@param entries Lsp.Doctor.InspectClient[]
---@return string[] conflicts
local function detect_conflicts(entries)
  local conflicts = {}
  local fmt, diagp = {}, {}
  for _, e in ipairs(entries) do
    local caps = e.client.server_capabilities or {}
    if caps.documentFormattingProvider == true then
      fmt[#fmt + 1] = e.label
    end
    -- Only pull diagnostics are visible here: push diagnostics
    -- (`textDocument/publishDiagnostics`) carry no server capability,
    -- so a server that sends them cannot be counted as a provider.
    if caps.diagnosticProvider then
      diagp[#diagp + 1] = e.label
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
---@param entries Lsp.Doctor.InspectClient[]
---@return string|nil winner, string[] candidates, string reason
local function pick_formatter(entries)
  -- Two lists on purpose: `formatter_priority` is written against server
  -- *names*, so matching it against a disambiguated label would silently stop
  -- honouring the option the moment a second client of that name shows up.
  -- What is printed is the label.
  local labels, names = {}, {}
  for _, e in ipairs(entries) do
    local caps = e.client.server_capabilities or {}
    if caps.documentFormattingProvider == true then
      labels[#labels + 1] = e.label
      names[#names + 1] = e.name
    end
  end

  if #labels == 0 then
    return nil, labels, "no formatting provider"
  end

  for _, prefer in ipairs(Opts.formatter_priority or {}) do
    for i, name in ipairs(names) do
      if name == prefer then
        return labels[i], labels, "priority list"
      end
    end
  end

  -- `entries` is already sorted by name, so the first candidate is the
  -- alphabetical one -- no second sort, and the label stays with its client.
  return labels[1], labels, "alphabetical fallback"
end

-- Report generation -----------------------------------------------------------

---@param mode '"buffer"'|'"capabilities"'
---@param bufnr integer
---@return string[] lines, Lsp.Doctor.InspectReport report
local function generate_report(mode, bufnr)
  local lines = {}
  local report = { mode = mode, ok = true }

  local entries = collect_clients(bufnr)
  local counts, total = collect_diagnostics(bufnr)

  -- Clients
  lines[#lines + 1] = "### LSP Clients (current buffer)"
  if #entries == 0 then
    lines[#lines + 1] = "No LSP client attached"
  else
    ---@type string[]
    local labels = {}
    for _, e in ipairs(entries) do
      labels[#labels + 1] = e.label
    end
    local display = mode == "buffer" and take(labels, Opts.list_limit or 10) or labels
    for _, n in ipairs(display) do
      lines[#lines + 1] = string.format("- `%s`", n)
    end
  end
  lines[#lines + 1] = ""

  -- Diagnostics
  lines[#lines + 1] = "### Diagnostics (current buffer)"
  lines[#lines + 1] = string.format(
    "Total: **%d** [ERROR: %d, WARN: %d, INFO: %d, HINT: %d]",
    total,
    counts.ERROR,
    counts.WARN,
    counts.INFO,
    counts.HINT
  )
  lines[#lines + 1] = ""

  -- Conflicts
  if Opts.show_conflicts and #entries > 1 then
    local conf = detect_conflicts(entries)
    lines[#lines + 1] = "### Provider Conflicts"
    if #conf > 0 then
      for _, c in ipairs(conf) do
        lines[#lines + 1] = "⚠️  " .. c
      end
    else
      lines[#lines + 1] = "✅ No obvious overlaps detected"
    end
    lines[#lines + 1] = ""
  end

  -- Offset encoding
  local encs, mismatches = check_offset_encoding(entries)
  if #encs > 0 then
    lines[#lines + 1] = "### Offset Encodings"
    if #mismatches > 0 then
      lines[#lines + 1] = "⚠️  **Mismatch detected:**"
      for _, m in ipairs(mismatches) do
        lines[#lines + 1] = "   - " .. m
      end
      report.ok = false
    else
      lines[#lines + 1] = "✅ All clients: `" .. encs[1] .. "`"
    end
    lines[#lines + 1] = ""
  end

  -- Formatter: what actually runs first, then what this report merely ranks.
  local winner, all, reason = pick_formatter(entries)
  lines[#lines + 1] = "### Formatter"

  local chain, lsp_after = conform_chain(bufnr)
  if chain == nil then
    lines[#lines + 1] = "Runs: *(conform.nvim not installed -- LSP formatting only)*"
  elseif #chain == 0 then
    lines[#lines + 1] = ("Runs: %s"):format(
      lsp_after and "the LSP client below (no conform formatter for this filetype)"
        or "*(nothing -- no conform formatter and no LSP formatting provider)*"
    )
  else
    lines[#lines + 1] = ("Runs: **%s** (conform)%s"):format(
      table.concat(chain, " -> "),
      lsp_after and ", then the LSP client below" or ""
    )
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "LSP clients able to format: "
    .. (#all == 0 and "*(none)*" or table.concat(all, ", "))
  lines[#lines + 1] = ("Preferred among them: **%s** (%s)"):format(winner or "(none)", reason)
  lines[#lines + 1] = "*Report only.* `lspdoctor.formatter_priority` ranks this line and nothing "
    .. "else -- it does not choose what formats the buffer. The `Runs:` line above does."
  lines[#lines + 1] = ""

  -- `capabilities` only: everything the capped `buffer` report leaves out
  if mode == "capabilities" then
    -- Workspace
    if Opts.show_workspace and #entries > 0 then
      for _, e in ipairs(entries) do
        local c = e.client
        lines[#lines + 1] = string.format("### Workspace: %s", e.label)
        local root = (c.config and c.config.root_dir) or c.root_dir
        lines[#lines + 1] = "  root_dir: `" .. tostring(root) .. "`"

        local ws = {}
        if c.workspace_folders and type(c.workspace_folders) == "table" then
          for _, f in ipairs(c.workspace_folders) do
            ws[#ws + 1] = (f.name or f.uri or "?")
          end
        end

        if #ws > 0 then
          lines[#lines + 1] = "  workspace_folders:"
          for _, w in ipairs(ws) do
            lines[#lines + 1] = "    - " .. w
          end
        else
          lines[#lines + 1] = "  workspace_folders: *(none)*"
        end
        lines[#lines + 1] = ""
      end
    end

    -- Capabilities
    if Opts.show_capabilities and #entries > 0 then
      for _, e in ipairs(entries) do
        local c = e.client
        local caps = c.server_capabilities or {}
        lines[#lines + 1] = string.format("### Capabilities: %s", e.label)
        lines[#lines + 1] =
          string.format("  offsetEncoding: `%s`", tostring(c.offset_encoding or "nil"))
        lines[#lines + 1] =
          string.format("  completionProvider: %s", yesno(caps.completionProvider ~= nil))
        lines[#lines + 1] =
          string.format("  definitionProvider: %s", yesno(caps.definitionProvider ~= nil))
        lines[#lines + 1] =
          string.format("  documentFormatting: %s", yesno(caps.documentFormattingProvider == true))
        lines[#lines + 1] = string.format("  codeAction: %s", yesno(caps.codeActionProvider ~= nil))
        lines[#lines + 1] =
          string.format("  semanticTokens: %s", yesno(caps.semanticTokensProvider ~= nil))
        lines[#lines + 1] = string.format("  inlayHints: %s", yesno(caps.inlayHintProvider ~= nil))
        lines[#lines + 1] = string.format("  codeLens: %s", yesno(caps.codeLensProvider ~= nil))
        lines[#lines + 1] = ""
      end
    end
  end

  -- Summary
  if #entries == 0 then
    report.ok = false
    report.summary = "No LSP client attached"
  else
    report.summary = string.format(
      "Clients: %d, Diagnostics: %d (E:%d W:%d I:%d H:%d)",
      #entries,
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
---@return string[] lines, Lsp.Doctor.InspectReport report
function M.buffer(bufnr)
  return generate_report("buffer", bufnr)
end

---@param bufnr integer
---@return string[] lines, Lsp.Doctor.InspectReport report
function M.capabilities(bufnr)
  return generate_report("capabilities", bufnr)
end

return M
