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
  local name, rest = path:match("^%${([%w_]+)}[/\\]?(.*)$")
  if not name then
    name, rest = path:match("^%$([%w_]+)[/\\](.*)$")
  end
  if not name then
    name = path:match("^%$([%w_]+)$")
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

---@internal
--- gopath.nvim's answer for an env reference, or nil when gopath is absent,
--- predates `resolve_text`, does not recognise the text, or raised.
---@param path string
---@return { path: string, exists: boolean }|nil
local function resolve_gopath(path)
  local ok, gopath = pcall(require, "gopath")
  if not ok or type(gopath) ~= "table" or type(gopath.resolve_text) ~= "function" then
    return nil
  end
  local called, res = pcall(gopath.resolve_text, path)
  if not called or type(res) ~= "table" or type(res.path) ~= "string" or res.kind == "url" then
    return nil
  end
  return { path = (res.path:gsub("\\", "/")), exists = res.exists == true }
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
    return { path = via.path, exists = via.exists, fragment = fragment, source = "gopath" }
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

---@internal
--- Parse the target that starts at byte `i` of an inline link's `(`...`)`.
--- A `<...>` target may hold spaces; a bare one ends at whitespace or at the
--- unmatched `)`, and may be followed by a title.
---@param line string
---@param i integer # First byte after `(`.
---@return string|nil target
---@return integer|nil close # Byte of the closing `)`, or the last byte seen.
local function parse_target(line, i)
  if line:sub(i, i) == "<" then
    local gt = line:find(">", i + 1, true)
    if not gt then
      return nil, nil
    end
    return line:sub(i + 1, gt - 1), line:find(")", gt + 1, true) or gt
  end

  local depth, j = 0, i
  while j <= #line do
    local c = line:sub(j, j)
    if c == "(" then
      depth = depth + 1
    elseif c == ")" then
      if depth == 0 then
        break
      end
      depth = depth - 1
    elseif c:match("%s") then
      break
    end
    j = j + 1
  end
  if j == i then
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
  local init = 1
  while true do
    local s, _, after_paren = line:find("%[[^%]]*%]%(()", init)
    if not s then
      break
    end
    local target, close = parse_target(line, after_paren)
    if target and close and col >= s and col <= close then
      return target
    end
    init = s + 1
  end

  local ref = line:match("^%s*%[[^%]]+%]:%s*(%S+)")
  if ref then
    return (ref:gsub("^<(.*)>$", "%1"))
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

--- The 0-based line of the heading whose anchor is `fragment` in the file at
--- `path`; nil when there is none or the file cannot be read. Headings inside
--- fenced code blocks are not headings.
---@param path string
---@param fragment string
---@return integer|nil
function M.heading_line(path, fragment)
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
      local title = line:match("^#+%s+(.-)%s*#*%s*$")
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
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, path, "", max_lines)
  return ok and lines or nil
end

return M
