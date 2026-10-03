---@module 'lsp.core.env_links'
---@brief Resolve `$VAR/...`, `${VAR}/...` and `~/...` Markdown link targets.
---@description
--- A Markdown link like `[notes]($REPOS_DIR/WKDBook/Notes/Links.md)` is a path
--- the *user* can follow -- with gopath.nvim's `gP`, or by hand -- but a
--- language server cannot: marksman resolves link targets relative to the
--- document, so it looks for a folder literally named `$REPOS_DIR`. Measured
--- against real marksman, such a link gets **no definition and no hover**, and
--- reports "Link to non-existent document" for a target that exists. The
--- blanket `suppress_missing_doc_links` in `lsp.servers.marksman.config` hid
--- that -- along with every genuinely broken link, everywhere.
---
--- This module is the resolution half of the fix; it has no LSP in it:
---
---   * `resolve(target)`     -- the file a target names, and whether it exists.
---   * `target_at(line, col)`-- the link target under a byte column.
---   * `verdict(message)`    -- what to do with a marksman diagnostic about
---                              such a link (`lsp.servers.marksman.diagnostics_handler`).
---   * `heading_line(...)`   -- the line of a `#fragment` heading in the target.
---
--- Consumers: the diagnostics filter (drop the false alarm, keep the real
--- one) and `lsp.core.env_links_server` (definition and hover).
---
--- ## Resolution order
---
--- 1. **gopath.nvim**, when it is installed and exposes `resolve_text` (its
---    public text API): it owns the env-variable rules -- `$VAR`, `${VAR}`,
---    both separators, the "well-known" directories such as `$NVIM_CONFIG_DIR`
---    that resolve with no real environment variable -- so a link resolves here
---    exactly as `gP` resolves it there, including any config the user set.
--- 2. **Built-in**, otherwise: the real environment first, `$NVIM_CONFIG_DIR`
---    from `stdpath("config")`, and `~`. Enough to work without gopath, and
---    deliberately no more than that -- the moment it grew rules of its own it
---    would start disagreeing with gopath.
---
--- `~` is always handled here: gopath's text API is about env references.
---
---@see lsp.core.env_links_server
---@see lsp.servers.marksman.diagnostics_handler

local M = {}

---@class LspNvim.EnvLink.Resolved
---@field path string # Absolute, forward slashes.
---@field exists boolean # Whether `path` is on disk (a directory counts).
---@field fragment string|nil # The `#anchor` of the target, without the `#`.
---@field source "gopath"|"builtin"

--- Directories that resolve without a real environment variable, mirroring
--- gopath's `env_variable_resolution.shorten_known_dirs` default. Used only by
--- the built-in resolver -- gopath applies its own (configurable) table.
---@type table<string, fun(): string>
local KNOWN_DIRS = {
  NVIM_CONFIG_DIR = function()
    return vim.fn.stdpath("config")
  end,
}

--- Does this link target start with something only the user's shell could
--- expand: `$VAR`, `${VAR}`, or `~`?
---@param target any
---@return boolean
function M.is_env_target(target)
  if type(target) ~= "string" then
    return false
  end
  return target:match("^%$[%a_{]") ~= nil or target == "~" or target:match("^~[/\\]") ~= nil
end

--- Separate a link target from its `#fragment`, undo percent-encoding, and
--- drop the angle brackets of `<...>` targets.
---@param target string
---@return string path
---@return string|nil fragment
function M.split(target)
  local t = target:gsub("^<(.*)>$", "%1")
  local path, fragment = t:match("^([^#]*)#(.*)$")
  path = path or t
  local ok, decoded = pcall(vim.uri_decode, path)
  return ok and decoded or path, fragment
end

---@internal
---@param base string
---@param rest string
---@return string
local function join(base, rest)
  local joined = (base:gsub("[/\\]+$", "")) .. "/" .. (rest:gsub("\\", "/"))
  return (vim.fs.normalize(joined, { expand_env = false }):gsub("/+$", ""))
end

---@internal
--- The `~` form: `~` and `~/rest`.
---@param path string
---@return string|nil
local function resolve_home(path)
  local rest = path:match("^~[/\\](.*)$")
  if rest == nil and path ~= "~" then
    return nil
  end
  local home = vim.uv.os_homedir()
  if not home or home == "" then
    return nil
  end
  return join(home, rest or "")
end

---@internal
--- The built-in `$VAR` / `${VAR}` resolver.
---@param path string
---@return string|nil
local function resolve_builtin(path)
  -- `${VAR}` and `$VAR` are followed by a separator or by nothing. `${VAR}foo`
  -- is the variable's value with `foo` glued on in a shell, not a folder
  -- below it: not something to guess at.
  local name, rest = path:match("^%${([%w_]+)}[/\\](.*)$")
  if not name then
    name, rest = path:match("^%$([%w_]+)[/\\](.*)$")
  end
  if not name then
    name = path:match("^%${([%w_]+)}$") or path:match("^%$([%w_]+)$")
    rest = ""
  end
  if not name then
    return nil
  end

  local base = vim.env[name]
  if type(base) ~= "string" or base == "" then
    local known = KNOWN_DIRS[name]
    base = known and known() or nil
  end
  if type(base) ~= "string" or base == "" then
    return nil
  end
  return join(base, rest or "")
end

--- Set once `require("gopath")` has failed: a missing module makes `require`
--- search every loader on every call (~0.4 ms measured), and this runs per
--- env-link diagnostic on every push and per hover. An already loaded gopath
--- is still found first, so installing one mid-session costs a restart at most.
---@type boolean
local gopath_absent = false

---@internal
---@return table|nil
local function gopath_module()
  local loaded = package.loaded["gopath"]
  if type(loaded) == "table" then
    return loaded
  end
  if gopath_absent then
    return nil
  end
  local ok, mod = pcall(require, "gopath")
  if ok and type(mod) == "table" then
    return mod
  end
  gopath_absent = true
  return nil
end

---@internal
--- The path gopath.nvim resolves an env reference to, or nil when gopath is
--- absent, predates `resolve_text`, does not recognise the text, or raised.
---
--- Only the *path* is taken from gopath. Its `exists` means "is a regular
--- file" (`gopath.util.path.exists`), so a link to a directory would come back
--- `exists = false` -- measured -- and be reported missing. Whether something
--- is on disk, of whatever type, is decided by the caller with `fs_stat`.
---@param path string
---@return string|nil
local function resolve_gopath(path)
  local gopath = gopath_module()
  if not gopath or type(gopath.resolve_text) ~= "function" then
    return nil
  end
  local called, res = pcall(gopath.resolve_text, path)
  if not called or type(res) ~= "table" or type(res.path) ~= "string" or res.kind == "url" then
    return nil
  end
  return (res.path:gsub("\\", "/"))
end

--- Resolve a link target.
---
--- nil when the target is not an env/home reference at all, or names a
--- variable nothing defines -- the caller then leaves the link alone, which
--- is the right answer for "cannot tell".
---@param target string
---@return LspNvim.EnvLink.Resolved|nil
function M.resolve(target)
  if not M.is_env_target(target) then
    return nil
  end
  local path, fragment = M.split(target)

  local home = resolve_home(path)
  if home then
    return {
      path = home,
      exists = vim.uv.fs_stat(home) ~= nil,
      fragment = fragment,
      source = "builtin",
    }
  end

  local via = resolve_gopath(path)
  if via then
    return {
      path = via,
      exists = vim.uv.fs_stat(via) ~= nil,
      fragment = fragment,
      source = "gopath",
    }
  end

  local resolved = resolve_builtin(path)
  if not resolved then
    return nil
  end
  return {
    path = resolved,
    exists = vim.uv.fs_stat(resolved) ~= nil,
    fragment = fragment,
    source = "builtin",
  }
end

-- ----------------------------------------------------------------------------
-- Link under the cursor
-- ----------------------------------------------------------------------------

--- Longest line `target_at` will scan, in bytes. No hand-written Markdown link
--- sits on a line this long; it caps the work a hover or `gd` does on a
--- minified or generated line of any length.
---@type integer
M.MAX_LINE_BYTES = 20000

--- Longest link target `target_at` will return, in bytes: `PATH_MAX`, and far
--- beyond anything a person types. For a bare inline target it also caps the
--- scan per link on lines such as `[a]($X/[a]($X/...`, where every target
--- would otherwise run to the end of the line. (A `<...>` target is found with
--- one plain `find`, and a reference definition with two anchored patterns,
--- each linear in a line of at most `MAX_LINE_BYTES`: the limit there is the
--- same rule, not a cost bound.)
---@type integer
M.MAX_TARGET_BYTES = 4096

---@internal
--- Bytes of link targets `target_at` examines in one call, summed over all the
--- links it tries: a few targets of the longest allowed length, and a hundred
--- times what the links around any real position add up to.
---@type integer
local TARGET_SCAN_BUDGET = 4 * M.MAX_TARGET_BYTES

---@internal
--- Whether byte `b` is what Lua's `%s` matches.
---@param b integer|nil
---@return boolean
local function is_space(b)
  return b == 32 or (b ~= nil and b >= 9 and b <= 13)
end

---@internal
--- Parse the target that starts at byte `i` of an inline link's `(`...`)`.
--- A `<...>` target may hold spaces; a bare one ends at whitespace or at the
--- unmatched `)`, and may be followed by a title.
---
--- Bounded by `MAX_TARGET_BYTES`, and hops from one byte that matters to the
--- next with `find` instead of looking at every byte: `[a]($X/[a]($X/...`
--- makes every link's target run to the end of the line, and a scan per link
--- over the rest of the line is quadratic.
---@param line string
---@param i integer # First byte after `(`.
---@return string|nil target
---@return integer|nil close # Byte of the closing `)`, or the last byte seen.
local function parse_target(line, i)
  if line:byte(i) == 60 then -- "<"
    local gt = line:find(">", i + 1, true)
    if not gt or gt - i - 1 > M.MAX_TARGET_BYTES then
      return nil, nil
    end
    return line:sub(i + 1, gt - 1), line:find(")", gt + 1, true) or gt
  end

  local depth, j = 0, i
  while true do
    local k = line:find("[%s()]", j)
    if not k then
      j = #line + 1 -- runs to the end of the line: a link still being typed
      break
    end
    if k - i > M.MAX_TARGET_BYTES then
      return nil, nil -- longer than any real target: not cut short, refused
    end
    local c = line:byte(k)
    if c == 40 then -- "("
      depth = depth + 1
    elseif c == 41 then -- ")"
      if depth == 0 then
        j = k
        break
      end
      depth = depth - 1
    else -- whitespace
      j = k
      break
    end
    j = k + 1
  end
  if j == i or j - i > M.MAX_TARGET_BYTES then
    return nil, nil
  end
  return line:sub(i, j - 1), line:find(")", j, true) or (j - 1)
end

---@internal
--- The target of a reference definition line, `[label]: target`, and the byte
--- span of that target within the line (`<>` not included).
---
--- `<...>` first: like an inline `(<...>)` target it may hold spaces (a path
--- under "Program Files"), and `%S+` alone would cut it at the first one and
--- return `<$R/my`. Two anchored patterns, each linear in a line of at most
--- `MAX_LINE_BYTES`; the target is held to the same limit as an inline one.
---@param line string
---@return string|nil target
---@return integer|nil first # 1-based byte of the target's first character.
---@return integer|nil last # 1-based byte of its last character.
local function ref_definition(line)
  local first, ref, after = line:match("^%s*%[[^%]]+%]:%s*()(<[^>]*>)()")
  local angled = ref ~= nil
  if not ref then
    first, ref, after = line:match("^%s*%[[^%]]+%]:%s*()(%S+)()")
  end
  if not ref then
    return nil
  end
  local last = after - 1
  if angled then
    ref = ref:sub(2, -2)
    first, last = first + 1, last - 1
  end
  if #ref > M.MAX_TARGET_BYTES then
    return nil
  end
  return ref, first, last
end

--- The link target of the Markdown link the byte column `col` (1-based) is
--- on: anywhere in `[text](target)` / `![alt](target)`, or anywhere on a
--- reference definition line `[label]: target`.
---
--- Works on one line, which is all a link is: this is not a Markdown parser,
--- and a link broken across lines is not one marksman resolves either.
---@param line any # A string; anything else answers nil.
---@param col any # A number (1-based byte column); anything else answers nil.
---@return string|nil target # As written, `<>` and `#fragment` included.
function M.target_at(line, col)
  -- Types first (ERR-02): a hover asks this about whatever it was handed, and
  -- "no link here" is the fail-open answer. The comparison with `#line` comes
  -- after the type check on purpose.
  --
  -- A hover or a `gd` on a minified or generated line must not be able to
  -- stall the editor. The scan below is linear in the line (measured before
  -- it was: 1.2 s on 20000 `[`), this cap only keeps it short.
  if type(line) ~= "string" or type(col) ~= "number" or #line > M.MAX_LINE_BYTES then
    return nil
  end

  -- One pass over the brackets, with a stack of the `[` not yet closed: a `]`
  -- closes the innermost one, and a `](` right after it makes an inline link
  -- whose text starts there. The text may hold balanced brackets -- an image
  -- inside a link, `[![badge](img)](target)`, is the common case -- and a
  -- backslash escapes the byte after it (`\]`). Inner links are completed, and
  -- so answered, before the ones around them. (`%[[^%]]*%]%(` did the same job
  -- for flat text, but re-scanned to the end of the line from every `[`.)
  local opens, n = {}, 0 ---@type integer[], integer
  local budget = TARGET_SCAN_BUDGET
  local pos = 1
  while true do
    local i = line:find("[%[%]\\]", pos)
    if not i then
      break
    end
    local c = line:byte(i)
    if c == 92 then -- "\": the next byte is text, whatever it is
      pos = i + 2
    elseif c == 91 then -- "["
      n = n + 1
      opens[n] = i
      pos = i + 1
    else -- "]"
      pos = i + 1
      if n > 0 then
        local open = opens[n]
        opens[n] = nil
        n = n - 1
        if line:byte(i + 1) == 40 then -- "]("
          -- A link that starts past `col` cannot hold it; and one whose target
          -- starts more than a target's length before `col` cannot reach it --
          -- counting the `>` and `)` that close a `<...>` target as part of the
          -- link. Neither is parsed: that bounds the work per link.
          if open <= col and i + 4 + M.MAX_TARGET_BYTES >= col then
            local target, close = parse_target(line, i + 2)
            if target and close and col <= close then
              return target
            end
            -- With nesting, one hostile line can make thousands of `](` each
            -- close a `[` that reaches `col`, and each of those parses a target
            -- that runs to the limit (measured: 273 ms for 10000 `[` then
            -- 5000 `](`). A real link costs its own length; this stops the sum.
            budget = budget - (close and (close - i) or M.MAX_TARGET_BYTES)
            if budget < 0 then
              break
            end
          end
          -- Links come left to right, but an enclosing one is only completed
          -- after the inner ones: nothing further right can hold `col` once
          -- this one starts past it AND no `[` still open starts before it.
          if open > col and (n == 0 or opens[1] > col) then
            break
          end
        end
      end
    end
  end

  -- A reference definition is a link too, and answers from any column of its
  -- line, the title's included.
  return (ref_definition(line))
end

-- ----------------------------------------------------------------------------
-- Every link in a buffer
-- ----------------------------------------------------------------------------

---@class LspNvim.EnvLink.Span
---@field target string # As written, `#fragment` included, `<>` not.
---@field first integer # 1-based byte of the target's first character.
---@field last integer # 1-based byte of its last character.

---@class LspNvim.EnvLink.Found : LspNvim.EnvLink.Span
---@field lnum integer # 0-based line.

--- Bytes of link targets `links` examines in one line, summed over its links.
---@type integer
local LINKS_SCAN_BUDGET = 2 * M.MAX_LINE_BYTES

--- Most env links `scan` returns for one buffer. Above this a buffer is a
--- generated file, not a note, and the answer would not be read anyway.
---@type integer
M.MAX_SCANNED_LINKS = 2000

--- Every link on one line: `[text](target)`, `![alt](target)`, and a reference
--- definition `[label]: target`, with the span of each target. The same bracket
--- rules as `target_at`, which answers for one column; this answers for all.
---@param line any
---@return LspNvim.EnvLink.Span[]
function M.links(line)
  local found = {} ---@type LspNvim.EnvLink.Span[]
  if type(line) ~= "string" or #line > M.MAX_LINE_BYTES then
    return found
  end

  local n = 0 -- how many `[` are open: a `]` closes the innermost one
  local budget = LINKS_SCAN_BUDGET
  local pos = 1
  while true do
    local i = line:find("[%[%]\\]", pos)
    if not i then
      break
    end
    local c = line:byte(i)
    pos = i + 1
    if c == 92 then -- "\": the next byte is text
      pos = i + 2
    elseif c == 91 then -- "["
      n = n + 1
    elseif n > 0 then -- "]"
      n = n - 1
      if line:byte(i + 1) == 40 then -- "]("
        local target, close = parse_target(line, i + 2)
        if target and close then
          local first = i + 2 + (line:byte(i + 2) == 60 and 1 or 0)
          found[#found + 1] = { target = target, first = first, last = first + #target - 1 }
        end
        budget = budget - (close and (close - i) or M.MAX_TARGET_BYTES)
        if budget < 0 then
          break
        end
      end
    end
  end

  local ref, first, last = ref_definition(line)
  if ref and first and last then
    found[#found + 1] = { target = ref, first = first, last = last }
  end
  return found
end

--- `line` with the inside of every code span (`` `x` ``, ``` ``x`` ```) blanked
--- out, byte for byte, so columns still line up. A span ends at the next run of
--- exactly as many backticks; a run with none stays text, as in CommonMark.
---
--- Linear: the runs are matched from the right in one pass instead of searching
--- ahead from each opener, which a line of backticks of a hundred different
--- lengths would turn quadratic.
---@param line string
---@return string
function M.mask_code_spans(line)
  if not line:find("`", 1, true) then
    return line
  end

  local starts, stops = {}, {}
  local pos = 1
  while true do
    local s, e = line:find("`+", pos)
    if not s then
      break
    end
    if s > 1 and line:byte(s - 1) == 92 then -- an escaped backtick opens nothing
      s = s + 1
    end
    if s <= e then
      starts[#starts + 1] = s
      stops[#stops + 1] = e
    end
    pos = e + 1
  end

  local next_same = {}
  local latest = {} ---@type table<integer, integer>
  for k = #starts, 1, -1 do
    local len = stops[k] - starts[k]
    next_same[k] = latest[len]
    latest[len] = k
  end

  local out, from = {}, 1
  local k = 1
  while k <= #starts do
    local close = next_same[k]
    if close then
      out[#out + 1] = line:sub(from, starts[k] - 1)
      out[#out + 1] = (" "):rep(stops[close] - starts[k] + 1)
      from = stops[close] + 1
      k = close + 1
    else
      k = k + 1
    end
  end
  out[#out + 1] = line:sub(from)
  return table.concat(out)
end

---@class LspNvim.EnvLink.Fence
---@field char string # "`" or "~".
---@field len integer # How many of them opened the block.

---@internal
--- The state of fenced-code-block tracking after `line`, and whether the line
--- is no document text: the fence line itself, or a line inside the block.
---
--- A block ends at a fence of the same character that is at least as long as
--- the one that opened it (CommonMark), so a `~~~` block that shows a "```"
--- example, or a four-backtick block around a three-backtick one, stays open
--- until its own end. (A single on/off toggle closed both at the first inner
--- fence, and the lines after it were read as document.)
---@param fence LspNvim.EnvLink.Fence|nil # State before `line`; nil outside a block.
---@param line string
---@return LspNvim.EnvLink.Fence|nil fence
---@return boolean skip
local function fence_step(fence, line)
  local char, run = "`", line:match("^%s*(```+)")
  if not run then
    char, run = "~", line:match("^%s*(~~~+)")
  end
  if not run then
    return fence, fence ~= nil
  end
  if not fence then
    return { char = char, len = #run }, true
  end
  if char == fence.char and #run >= fence.len then
    return nil, true
  end
  return fence, true
end

--- Every env link (`$VAR/...`, `${VAR}/...`, `~/...`) in a buffer's lines
--- that is a link in the Markdown sense: not inside a fenced code block or a
--- code span, not in a YAML front matter. Documentation that *shows* a link
--- must not be told its example is broken.
---@param lines string[]
---@return LspNvim.EnvLink.Found[]
function M.scan(lines)
  local found = {} ---@type LspNvim.EnvLink.Found[]

  -- Front matter: `---` on the first line, up to the next `---` or `...`.
  local from = 1
  if lines[1] and lines[1]:match("^%-%-%-%s*$") then
    for k = 2, #lines do
      if lines[k]:match("^%-%-%-%s*$") or lines[k]:match("^%.%.%.%s*$") then
        from = k + 1
        break
      end
    end
  end

  local fence ---@type LspNvim.EnvLink.Fence|nil
  local skip ---@type boolean
  for k = from, #lines do
    local line = lines[k]
    fence, skip = fence_step(fence, line)
    if not skip and #line <= M.MAX_LINE_BYTES and line:find("[$~]") then
      for _, link in ipairs(M.links(M.mask_code_spans(line))) do
        if M.is_env_target(link.target) then
          found[#found + 1] =
            { lnum = k - 1, target = link.target, first = link.first, last = link.last }
          if #found >= M.MAX_SCANNED_LINKS then
            return found
          end
        end
      end
    end
  end
  return found
end

-- ----------------------------------------------------------------------------
-- Diagnostics
-- ----------------------------------------------------------------------------

--- The link target a marksman "non-existent document" diagnostic is about.
---@param message any
---@return string|nil
function M.message_target(message)
  if type(message) ~= "string" then
    return nil
  end
  return message:match("^Link to non%-existent document '(.*)'")
end

--- What to do with a marksman diagnostic, as far as env links are concerned.
---
--- * `"drop"` -- it says the document does not exist, the target is an env
---   link, and the file it resolves to *does* exist: a false alarm.
--- * `"keep"` -- same, but the resolved file is not there: a real broken link,
---   and one that can now be reported with the path it was looked up at.
--- * `nil`    -- not about an env link, or the variable is not defined and
---   nothing can be said; the caller's own rules apply.
---@param message any
---@return "drop"|"keep"|nil verdict
---@return LspNvim.EnvLink.Resolved|nil resolved
function M.verdict(message)
  local target = M.message_target(message)
  if not target or not M.is_env_target(target) then
    return nil, nil
  end
  local resolved = M.resolve(target)
  if not resolved then
    return nil, nil
  end
  return resolved.exists and "drop" or "keep", resolved
end

-- ----------------------------------------------------------------------------
-- Target content
-- ----------------------------------------------------------------------------

--- Largest file the content helpers (`heading_line`, `preview`) will read.
---@type integer
M.MAX_READ_BYTES = 2 * 1024 * 1024

--- Longest line `heading_line` will take for a heading, in bytes. Not a limit
--- on the file: a longer line is simply not one. (It is a limit on work, too --
--- see `heading_title`.)
---@type integer
M.MAX_HEADING_BYTES = 2000

--- Longest preview line, in characters.
---@type integer
M.MAX_PREVIEW_LINE_BYTES = 200

--- Extensions of the files whose content is ever read on the strength of a
--- link. A hover previews the top of the target; without this, a document
--- linking `[x]($HOME/.ssh/id_rsa)` or `~/.aws/credentials` would put the first
--- lines of a secret into a hover the moment someone looks at the link. Only
--- documents are read; everything else is still *resolved* and jumped to, just
--- never quoted.
---@type table<string, true>
local TEXT_DOC_EXT = { md = true, markdown = true, mdx = true, txt = true }

---@internal
--- Is `path` a small regular Markdown/text file -- one it is fine to read?
---@param path string
---@return boolean
local function is_text_doc(path)
  local ext = path:match("%.(%w+)$")
  if not ext or not TEXT_DOC_EXT[ext:lower()] then
    return false
  end
  local st = vim.uv.fs_stat(path)
  return st ~= nil and st.type == "file" and st.size <= M.MAX_READ_BYTES
end

---@internal
--- The GitHub-style anchor of a heading: lowercase, punctuation dropped, spaces
--- to hyphens. Lowercasing is multibyte-aware (`Ü` -> `ü`, which `string.lower`
--- would leave alone) and non-ASCII bytes are kept -- both are what keep
--- `Übersicht` and friends working in a German document.
---@param title string
---@return string
local function slug(title)
  local s = vim.fn.tolower(title):gsub("[^%w%s%-_\128-\255]", "")
  return (s:gsub("%s", "-"))
end

---@internal
--- The title of an ATX heading line (`## Title ##`), nil for any other line.
---
--- The trailing spaces and closing `#`s are stripped by walking back from the
--- end. The obvious `^#+%s+(.-)%s*#*%s*$` is cubic on a line with a long run
--- of spaces inside it (measured: 0.5 s at 1000 bytes, 4.3 s at 2000), and the
--- line comes from a file this module does not control.
---@param line string
---@return string|nil
local function heading_title(line)
  if #line > M.MAX_HEADING_BYTES then
    return nil
  end
  local rest = line:match("^#+%s+(.*)$")
  if not rest then
    return nil
  end
  local e = #rest
  while is_space(rest:byte(e)) do
    e = e - 1
  end
  while e > 0 and rest:byte(e) == 35 do -- "#"
    e = e - 1
  end
  while is_space(rest:byte(e)) do
    e = e - 1
  end
  return rest:sub(1, e)
end

---@internal
--- `s` without trailing whitespace, by walking back from the end (see
--- `heading_title` for why not a pattern).
---@param s string
---@return string
local function rtrim(s)
  local e = #s
  while is_space(s:byte(e)) do
    e = e - 1
  end
  return s:sub(1, e)
end

---@internal
--- The `{#custom-id}` a heading may end with, and the title without it.
--- (Kramdown, pandoc, Docusaurus.) Found by looking for the last `{#`, not by a
--- pattern with a lazy prefix, which is quadratic on a long title.
---@param title string
---@return string title
---@return string|nil id
local function split_custom_id(title)
  local at ---@type integer|nil
  local from = 1
  while true do
    local p = title:find("{#", from, true)
    if not p then
      break
    end
    at, from = p, p + 1
  end
  if not at then
    return title, nil
  end
  local id = title:sub(at + 2):match("^([%w_%-%.:]+)}%s*$")
  if not id then
    return title, nil
  end
  return rtrim(title:sub(1, at - 1)), id
end

---@internal
--- A title as it reads once rendered, as far as the anchor is concerned:
--- `[text](url)` and `![alt](url)` become their text, HTML tags vanish. (A
--- changelog's `## [1.2.0](compare/...) - 2024-01-01` is `120---2024-01-01`.)
--- Both are single left-to-right sweeps: when no closing `)` or `>` is left,
--- none will be found later either, so the sweep stops instead of searching
--- again from every opener.
---@param title string
---@return string
local function rendered_title(title)
  if title:find("](", 1, true) then
    local out, piece, last_open = {}, 1, nil
    local i = 1
    while true do
      local k = title:find("[%[%]]", i)
      if not k then
        break
      end
      i = k + 1
      if title:byte(k) == 91 then -- "["
        last_open = k
      else
        local open = last_open
        last_open = nil
        if open and title:byte(k + 1) == 40 then -- "]("
          local close = title:find(")", k + 2, true)
          if not close then
            break
          end
          local from = (open > 1 and title:byte(open - 1) == 33) and open - 1 or open -- "!"
          if from >= piece then
            out[#out + 1] = title:sub(piece, from - 1)
            out[#out + 1] = title:sub(open + 1, k - 1)
            piece = close + 1
          end
          i = close + 1
        end
      end
    end
    out[#out + 1] = title:sub(piece)
    title = table.concat(out)
  end

  if title:find("<", 1, true) then
    local out, piece = {}, 1
    local i = 1
    while true do
      local k = title:find("</?%a", i)
      if not k then
        break
      end
      local close = title:find(">", k, true)
      if not close then
        break
      end
      out[#out + 1] = title:sub(piece, k - 1)
      piece = close + 1
      i = close + 1
    end
    out[#out + 1] = title:sub(piece)
    title = table.concat(out)
  end
  return title
end

---@internal
--- `s` without symbols and emoji, which GitHub drops from an anchor but
--- `slug` cannot tell from a letter in another script. Only ever used for an
--- *additional* key (`## 🚀 Features` is `#-features` on GitHub), so a wrong
--- guess here makes a link resolve that should not, never the reverse.
---@param s string
---@return string
local function without_symbols(s)
  local ok, out = pcall(function()
    local starts = vim.str_utf_pos(s)
    local kept = {}
    for k, from in ipairs(starts) do
      local char = s:sub(from, (starts[k + 1] or #s + 1) - 1)
      local cp = vim.fn.char2nr(char)
      local symbol = (cp >= 0xA0 and cp <= 0xBF)
        or cp == 0xD7
        or cp == 0xF7
        or (cp >= 0x2000 and cp <= 0x2BFF)
        or (cp >= 0xFE00 and cp <= 0xFE0F)
        or cp >= 0x1F000
      if not symbol then
        kept[#kept + 1] = char
      end
    end
    return table.concat(kept)
  end)
  return ok and out or s
end

---@class LspNvim.EnvLink.HeadingIndex : table<string, integer>

--- The anchors of the Markdown file at `path`, each with the 0-based line it
--- names: a heading's GitHub-style slug (a repeated heading `x` is `x`, `x-1`,
--- `x-2`, ...), its `{#custom-id}`, and the `id`/`name` of an HTML anchor.
--- Headings inside fenced code blocks are not headings.
---
--- nil when the file cannot be judged: not Markdown or text, too large, or
--- unreadable. That is "cannot tell", not "no anchors".
---@param path string
---@return LspNvim.EnvLink.HeadingIndex|nil
function M.heading_index(path)
  if not is_text_doc(path) then
    return nil
  end
  local content = require("lib.nvim.fs.read")(path)
  if not content then
    return nil
  end

  local index = {} ---@type LspNvim.EnvLink.HeadingIndex
  local seen = {} ---@type table<string, integer>
  ---@param key string
  ---@param n integer
  local function add(key, n)
    if key ~= "" and index[key] == nil then
      index[key] = n
    end
  end

  local fence ---@type LspNvim.EnvLink.Fence|nil
  local skip ---@type boolean
  local n = 0
  for line in (content .. "\n"):gmatch("(.-)\r?\n") do
    fence, skip = fence_step(fence, line)
    if not skip then
      local title = heading_title(line)
      if title then
        local text, id = split_custom_id(title)
        local rendered = rtrim(rendered_title(text))
        local base = slug(rendered)
        if base ~= "" then
          local repeated = seen[base]
          seen[base] = (repeated or -1) + 1
          add(repeated and (base .. "-" .. seen[base]) or base, n)
          if not repeated then
            add(slug(without_symbols(rendered)), n)
            add((base:gsub("^_+", ""):gsub("_+$", "")), n)
          end
        end
        if id then
          add(vim.fn.tolower(id), n)
        end
      end
      if line:find("<", 1, true) then
        for _, attr in ipairs({ "id", "name" }) do
          for value in line:gmatch("%s" .. attr .. "%s*=%s*[\"']([^\"']+)[\"']") do
            add(vim.fn.tolower(value), n)
          end
        end
      end
    end
    n = n + 1
  end
  return index
end

--- The 0-based line `fragment` names in `index`, nil when it names nothing.
--- The fragment is percent-decoded and matched as an anchor, so `#Second-Part`,
--- `#second%20part` and `#second-part` all find "## Second Part".
---@param index LspNvim.EnvLink.HeadingIndex
---@param fragment any
---@return integer|nil
function M.heading_lookup(index, fragment)
  if type(fragment) ~= "string" or fragment == "" then
    return nil
  end
  local ok, decoded = pcall(vim.uri_decode, fragment)
  if not ok then
    decoded = fragment
  end
  return index[slug(decoded)] or index[vim.fn.tolower(decoded)]
end

--- The 0-based line of the heading whose anchor is `fragment` in the file at
--- `path`; nil when there is none or the file cannot be read.
---@param path string
---@param fragment string
---@return integer|nil
function M.heading_line(path, fragment)
  local index = M.heading_index(path)
  return index and M.heading_lookup(index, fragment) or nil
end

--- Whether `path` names a Markdown file: the only kind whose anchors are
--- known well enough to say that one is missing.
---@param path string
---@return boolean
function M.is_markdown(path)
  local ext = path:match("%.(%w+)$")
  ext = ext and ext:lower()
  return ext == "md" or ext == "markdown" or ext == "mdx"
end

--- The first `max_lines` lines of the file at `path`, for a hover preview.
---@param path string
---@param max_lines integer
---@return string[]|nil
function M.preview(path, max_lines)
  if not is_text_doc(path) then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, path, "", max_lines)
  if not ok then
    return nil
  end
  -- One very long line would otherwise become one very long hover.
  for i, line in ipairs(lines) do
    if #line > M.MAX_PREVIEW_LINE_BYTES then
      lines[i] = vim.fn.strcharpart(line, 0, M.MAX_PREVIEW_LINE_BYTES) .. "..."
    end
  end
  return lines
end

return M
