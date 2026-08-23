---@module 'lsp.tools.lsp_signature.format_signature_help'
--- Formats a `signatureHelp` result for the signature-help popup, including
--- `strip_comment_prefix` -- a heuristic multi-language comment-marker
--- stripper (`//`, `/* */`, `#`, `--`, `%`) for parameter doc lines.
local split_lines = require("lsp.tools.lsp_signature.split_lines")

-- Strip common comment prefixes for many languages from a single line.
-- This is heuristic: handles //, /* */, #, --, % and leading whitespace.
---@param line string
---@return string
local function strip_comment_prefix(line)
  if not line then
    return line
  end
  -- trim leading whitespace
  local s = line:gsub("^%s+", "")
  -- patterns for common prefixes
  s = s:gsub("^//%s*", "")
  s = s:gsub("^%-%-%s*", "")
  s = s:gsub("^#%s*", "")
  s = s:gsub("^%%s*", "") -- lua/comment %
  -- block-comment start like /* ... */ -> remove leading /* and trailing */
  s = s:gsub("^/%*%s*", "")
  s = s:gsub("%s*%*/%s*$", "")
  return s
end

return function(result)
  if not result then
    return nil
  end
  local sigs = result.signatures or (result.value and result.value.signatures)
  if not sigs or #sigs == 0 then
    return nil
  end

  local active = result.activeSignature
  if result.value and type(result.value.activeSignature) == "number" then
    active = result.value.activeSignature
  end
  local idx = (type(active) == "number") and (active + 1) or 1
  local sig = sigs[idx] or sigs[1]
  if not sig then
    return nil
  end

  local label = sig.label or ""
  -- split label into lines and strip comment prefixes from each line (helpful when servers include comment markers)
  local lines = {}
  for _, ln in ipairs(split_lines(label)) do
    table.insert(lines, strip_comment_prefix(ln))
  end

  -- compute active parameter hl info if available
  local hl = nil
  if sig.parameters and sig.activeParameter then
    local param = sig.parameters[sig.activeParameter + 1]
    if param and param.label then
      if type(param.label) == "table" and #param.label == 2 then
        hl = { line = 1, col_start = param.label[1] + 1, col_end = param.label[2] }
      elseif type(param.label) == "string" then
        local s, e = string.find(label, vim.pesc(param.label), 1, true)
        if s and e then
          hl = { line = 1, col_start = s, col_end = e }
        end
      end
    end
  end

  -- append documentation (strip comment prefixes per line)
  if sig.documentation then
    local doc_text = ""
    if type(sig.documentation) == "string" then
      doc_text = sig.documentation
    elseif type(sig.documentation) == "table" and sig.documentation.value then
      doc_text = sig.documentation.value
    end
    if doc_text ~= "" then
      table.insert(lines, "")
      for _, ln in ipairs(split_lines(doc_text)) do
        table.insert(lines, strip_comment_prefix(ln))
      end
    end
  end

  return lines, hl
end
