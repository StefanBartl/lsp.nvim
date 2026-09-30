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
--- one plain `find`, and a reference definition needs no scan: the limit there
--- is the same rule, not a cost bound.)
---@type integer
M.MAX_TARGET_BYTES = 4096

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

--- The link target of the Markdown link the byte column `col` (1-based) is
--- on: anywhere in `[text](target)` / `![alt](target)`, or anywhere on a
--- reference definition line `[label]: target`.
---
--- Works on one line, which is all a link is: this is not a Markdown parser,
--- and a link broken across lines is not one marksman resolves either.
---@param line string
---@param col integer
---@return string|nil target # As written, `<>` and `#fragment` included.
function M.target_at(line, col)
  -- A hover or a `gd` on a minified or generated line must not be able to
  -- stall the editor. The scan below is linear in the line (measured before
  -- it was: 1.2 s on 20000 `[`), this cap only keeps it short.
  if #line > M.MAX_LINE_BYTES then
    return nil
  end

  -- One pass over the brackets. `open` is the last `[` not yet closed; a `](`
  -- after it is an inline link, whose text starts there. (`%[[^%]]*%]%(` did
  -- the same job, but re-scanned to the end of the line from every `[`.)
  local open ---@type integer|nil
  local pos = 1
  while true do
    local i = line:find("[%[%]]", pos)
    if not i then
      break
    end
    if line:byte(i) == 91 then -- "["
      open = i
    else
      if open and line:byte(i + 1) == 40 then -- "]("
        -- Links come left to right: once one starts past `col`, none further
        -- right can hold it. And one whose target starts more than a target's
        -- length before `col` cannot reach it -- counting the `>` and `)` that
        -- close a `<...>` target as part of the link.
        if open > col then
          break
        end
        if i + 4 + M.MAX_TARGET_BYTES >= col then
          local target, close = parse_target(line, i + 2)
          if target and close and col >= open and col <= close then
            return target
          end
        end
      end
      open = nil
    end
    pos = i + 1
  end

  -- `<...>` first: like an inline `(<...>)` target it may hold spaces (a path
  -- under "Program Files"), and `%S+` alone would cut it at the first one and
  -- return `<$R/my`.
  local ref = line:match("^%s*%[[^%]]+%]:%s*(<[^>]*>)") or line:match("^%s*%[[^%]]+%]:%s*(%S+)")
  if ref then
    ref = ref:gsub("^<(.*)>$", "%1")
    -- The same limit as an inline target: a reference definition is a link too.
    if #ref > M.MAX_TARGET_BYTES then
      return nil
    end
    return ref
  end
  return nil
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

--- The 0-based line of the heading whose anchor is `fragment` in the file at
--- `path`; nil when there is none or the file cannot be read. Headings inside
--- fenced code blocks are not headings.
---@param path string
---@param fragment string
---@return integer|nil
function M.heading_line(path, fragment)
  if not is_text_doc(path) then
    return nil
  end
  local content = require("lib.nvim.fs.read")(path)
  if not content then
    return nil
  end
  local want = vim.fn.tolower(fragment)
  local in_fence = false
  local n = 0
  for line in (content .. "\n"):gmatch("(.-)\r?\n") do
    if line:match("^%s*```") or line:match("^%s*~~~") then
      in_fence = not in_fence
    elseif not in_fence then
      local title = heading_title(line)
      if title and slug(title) == want then
        return n
      end
    end
    n = n + 1
  end
  return nil
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
