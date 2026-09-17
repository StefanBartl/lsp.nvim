---@module 'lsp.tools.lsp_signature.format_hover'
--- Formats a `textDocument/hover` result into display lines for the hover
--- window.
---
--- It used to format a `signatureHelp` result instead -- it read
--- `result.signatures`, which a hover result does not have. Its one caller,
--- `show_hover`, sends `textDocument/hover`, so the function returned nil for
--- every answer it was ever given. Measured against all three shapes the
--- protocol allows for `Hover.contents`, plus the one it did handle:
---
---     { contents = { kind = "markdown", value = ... } }    -> nil
---     { contents = "plain hover text" }                    -> nil
---     { contents = { { language = "lua", value = ... } } } -> nil
---     { signatures = { { label = "foo(a)" } } }            -> { "foo(a)" }
---
--- Only the last one worked, and nothing produces it here. End to end that
--- meant `show_hover` reported `sent = true` while no popup ever opened, so the
--- hover fallback this module documents -- and the LRU cache built to make it
--- cheap -- were unreachable in practice. The module header was honest about
--- what the code did; the call site was the bug, and this is the side worth
--- moving, because `format_signature_help` next door already covers the other
--- shape.
---
--- Conversion is `vim.lsp.util.convert_input_to_markdown_lines`, which is what
--- Neovim's own hover handler uses and which understands `MarkupContent`, a
--- bare string, a `MarkedString` and a list of them.

---@internal
--- Is this line a markdown fence marker, to be dropped rather than rendered?
---
--- The popup is plain text -- `open_floating_preview` sets `filetype` to
--- `lsp_signature` and does not run the content through a markdown stylizer --
--- so a ```` ```lua ```` line would reach the reader as three backticks and a
--- word. Neovim solves this with `stylize_markdown`, which needs a buffer to
--- write into; this function has to stay pure, because its result is what
--- `show_hover` puts in the cache.
---@param line string
---@return boolean
local function is_fence(line)
  return line:match("^%s*```") ~= nil
end

--- Format a hover result into a list of display lines.
---@param result table|nil A `textDocument/hover` result.
---@return string[]|nil # nil when there is nothing displayable.
return function(result)
  if type(result) ~= "table" then
    return nil
  end

  local contents = result.contents
  if contents == nil then
    return nil
  end

  -- `pcall`: the converter raises on a shape outside the protocol, and a
  -- malformed answer from one server must not take down a hover another client
  -- may still be about to provide -- every client is asked at once.
  local ok, converted = pcall(vim.lsp.util.convert_input_to_markdown_lines, contents, {})
  if not ok or type(converted) ~= "table" then
    return nil
  end

  ---@type string[]
  local lines = {}
  local blank_run = 0
  for _, line in ipairs(converted) do
    if not is_fence(line) then
      -- Dropping the fences can leave two blank lines where a code block was
      -- the only thing between them, so runs are collapsed on the way out.
      -- Leading and trailing blanks are `open_floating_preview`'s job.
      if line == "" then
        blank_run = blank_run + 1
      else
        blank_run = 0
      end
      if blank_run < 2 then
        lines[#lines + 1] = line
      end
    end
  end

  if #lines == 0 then
    return nil
  end
  return lines
end
