---@module 'lsp.tools.deprecated_help.help_float'
--- Shows the help entry of a symbol in a float instead of a help window.
---
--- The tag is looked up in every `doc/tags` file on the runtimepath (English
--- help only; `'helplang'` and `tags-xx` are not consulted). Two entry forms:
---
--- * a heading, the tag at the end of its line (`vim.split({s}) *vim.split()*`):
---   the entry runs to the next separator line or the next tag definition after
---   some text;
--- * a bullet, text after the tag on the same line (`deprecated.txt`:
---   `• *vim.tbl_islist()*  Use |vim.islist()| instead.`): the entry is that line
---   and the indented lines that continue it.
---
--- Either is capped at `M.MAX_LINES`.

local M = {}

---@type integer
M.MAX_LINES = 40

local TAG_DEF = "%*[^%s|*]+%*"

--- Tags to try for a symbol, best first: with `vim.` in front (the detected
--- symbol loses that prefix: `lsp.buf_get_clients` for `vim.lsp.buf_get_clients()`,
--- and a Lua API wins over the Vimscript function of the same name), then as
--- written; each as written and as a function (`name()`).
---@param symbol string
---@return string[]
function M.candidates(symbol)
  local bases = {}
  if not symbol:find("^vim%.") then
    bases[#bases + 1] = "vim." .. symbol
  end
  bases[#bases + 1] = symbol
  local list = {}
  for _, base in ipairs(bases) do
    list[#list + 1] = base
    if not base:find("%(%)$") then
      list[#list + 1] = base .. "()"
    end
  end
  return list
end

--- The help files that define the given tags, read in one pass over each `doc/tags`.
---@param tags string[]
---@return table<string, string> file by tag (the first tags file that has it wins)
function M.find_tags(tags)
  local wanted = {}
  for _, tag in ipairs(tags) do
    wanted[tag] = true
  end
  local found = {}
  for _, tags_file in ipairs(vim.api.nvim_get_runtime_file("doc/tags", true)) do
    local f = io.open(tags_file, "r")
    if f then
      local dir = vim.fs.dirname(tags_file)
      for line in f:lines() do
        local name, file = line:match("^([^\t]+)\t([^\t]+)\t")
        if name and wanted[name] and not found[name] then
          found[name] = vim.fs.joinpath(dir, file)
        end
      end
      f:close()
    end
  end
  return found
end

---@param line string
---@return boolean
local function defines_tag(line)
  return line:find(TAG_DEF) ~= nil
end

---@param line string
---@return boolean
local function is_separator(line)
  return line:match("^=+%s*$") ~= nil or line:match("^%-%-%-%-+%s*$") ~= nil
end

---@param line string
---@return boolean
local function is_blank(line)
  return line:match("^%s*$") ~= nil
end

--- The lines of the help entry for `tag` in `lines`, or nil when the tag is not defined there.
---@param lines string[]
---@param tag string
---@param max_lines? integer
---@return string[]|nil
function M.section(lines, tag, max_lines)
  max_lines = max_lines or M.MAX_LINES
  local needle = "*" .. tag .. "*"
  local start, at
  for i, line in ipairs(lines) do
    at = line:find(needle, 1, true)
    if at then
      start = i
      break
    end
  end
  if not start then
    return nil
  end

  local first = lines[start]
  local after = first:sub(at + #needle):gsub(TAG_DEF, "")
  local bullet = after:match("%S") ~= nil
  local out = { first }

  if bullet then
    for i = start + 1, #lines do
      local line = lines[i]
      if is_blank(line) or not line:match("^%s") or defines_tag(line) or #out >= max_lines then
        break
      end
      out[#out + 1] = line
    end
    return out
  end

  local seen_text = first:gsub(TAG_DEF, ""):match("%S") ~= nil
  for i = start + 1, #lines do
    local line = lines[i]
    if is_separator(line) then
      break
    end
    if defines_tag(line) then
      if seen_text then
        break
      end
    elseif not is_blank(line) then
      seen_text = true
    end
    if #out >= max_lines then
      out[#out + 1] = "..."
      break
    end
    out[#out + 1] = line
  end
  while #out > 1 and is_blank(out[#out]) do
    out[#out] = nil
  end
  return out
end

--- The help entry of `symbol`, trying each candidate tag and then the tag
--- `:help` itself would pick, or nil.
---@param symbol string
---@return string[]|nil
function M.lookup(symbol)
  local tags = M.candidates(symbol)
  local ok, completion = pcall(vim.fn.getcompletion, symbol, "help")
  if ok and type(completion) == "table" and completion[1] then
    tags[#tags + 1] = completion[1]
  end
  local files = M.find_tags(tags)
  local cache = {}
  for _, tag in ipairs(tags) do
    local file = files[tag]
    if file and vim.fn.filereadable(file) == 1 then
      cache[file] = cache[file] or vim.fn.readfile(file)
      local lines = M.section(cache[file], tag)
      if lines then
        return lines
      end
    end
  end
  return nil
end

--- Open the help entry of `symbol` in a float; focus stays where it is.
---@param symbol string
---@return boolean shown
function M.show(symbol)
  local lines = M.lookup(symbol)
  if not lines then
    return false
  end
  vim.lsp.util.open_floating_preview(lines, "help", {
    focus = false,
    focus_id = "lsp_deprecated_help",
    max_width = math.max(40, math.floor(vim.o.columns * 0.8)),
    max_height = math.max(5, math.floor(vim.o.lines * 0.5)),
  })
  return true
end

return M
