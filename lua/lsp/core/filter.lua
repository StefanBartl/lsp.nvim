---@module 'lsp.core.filter'
--- Pure diagnostic-list helpers: `filter` drops entries whose message matches
--- a configured substring pattern, `dedup` collapses exact duplicates --
--- both operate on a plain list, no LSP client involved.

local M = {}

---Filters diagnostics by message substring patterns (pure).
---@param diags table[]
---@param opts { patterns: string[] }|nil
function M.filter(diags, opts)
  if type(diags) ~= "table" or #diags == 0 then
    return diags
  end
  if not opts or type(opts.patterns) ~= "table" or #opts.patterns == 0 then
    return diags
  end
  local out = {}
  for _, d in ipairs(diags) do
    local msg = d and d.message or ""
    local keep = true
    for _, pat in ipairs(opts.patterns) do
      if type(pat) == "string" and pat ~= "" and msg:find(pat) then
        keep = false
        break
      end
    end
    if keep then
      out[#out + 1] = d
    end
  end
  return out
end

---Deduplicate diagnostics by (lnum,col,message,severity,source).
---Keeps the first occurrence; order is preserved.
---@param diags table[]
function M.dedup(diags)
  if type(diags) ~= "table" or #diags == 0 then
    return diags
  end
  local seen, out = {}, {}
  for _, d in ipairs(diags) do
    local lnum = (d.lnum or 0)
    local col = (d.col or 0)
    local sev = (d.severity or 0)
    local src = (d.source or "")
    local msg = (d.message or ""):gsub("%s+$", "")
    local key = table.concat({ lnum, col, sev, src, msg }, "␟")
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = d
    end
  end
  return out
end

return M
