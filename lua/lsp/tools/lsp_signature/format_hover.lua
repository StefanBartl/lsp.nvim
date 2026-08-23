---@module 'lsp.tools.lsp_signature.format_hover'
--- Formats an LSP `signatureHelp` result into display lines for the hover
--- window, delegating line-splitting to `split_lines`.

local split_lines = require("lsp.tools.lsp_signature.split_lines")

-- Format a signatureHelp result into a list of strings for display.
--@param result table
--@return string[]|nil
return function(result)
  if not result then
    return nil
  end

  local sigs = result.signatures or (result.value and result.value.signatures)
  if not sigs or #sigs == 0 then
    return nil
  end

  local active = nil
  if result.activeSignature then
    active = result.activeSignature
  elseif result.value and result.value.activeSignature then
    active = result.value.activeSignature
  end
  local active_idx = 1
  if type(active) == "number" then
    active_idx = math.max(1, active + 1) -- convert 0-based to 1-based when needed
  end

  local sig = sigs[active_idx] or sigs[1]
  if not sig then
    return nil
  end

  local label = sig.label or ""
  ---@type string[]
  local lines = split_lines(label)

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
        table.insert(lines, ln)
      end
    end
  end

  return lines
end
