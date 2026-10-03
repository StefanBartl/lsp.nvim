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
--- one) and `lsp.core.env_links_server` (definition, hover, diagnostics, completion).
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
---@field exists boolean|nil # Whether `path` is on disk (a directory counts); nil when it was not looked at (see `opts.stat`).
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
  -- gopath reads a wider grammar than a link target has, and the built-in
  -- resolver (which answers when this returns nil) is the reference:
  --   * `${VAR}foo` is the value with `foo` glued on in a shell, not a folder
  --     below it (see `resolve_builtin`), but gopath takes the separator as
  --     optional;
  --   * a long run of blanks (allowed inside `<...>`) makes gopath's location
  --     parser quadratic: about 100 ms per link at 4000 blanks, measured, and
  --     no real path has one.
  if path:match("^%${[%w_]+}[^/\\]") or path:find("%s%s%s%s%s%s%s%s") then
    return nil
  end
  local called, res = pcall(gopath.resolve_text, path)
  if not called or type(res) ~= "table" or type(res.path) ~= "string" or res.kind == "url" then
    return nil
  end
  -- A `:12`, `(3)` or `+4` at the end is a position for gopath, but it may
  -- just as well be the name of the file (`report(1).md`): a link target is
  -- a path as written, so the answer is the built-in resolver's.
  if res.range ~= nil then
    return nil
  end
  return (res.path:gsub("\\", "/"))
end

---@class LspNvim.EnvLink.ResolveOpts
---@field stat? fun(path: string): boolean|nil # Whether `path` is on disk; nil = not looked at. Default: `fs_stat`.

--- Whether this is Windows (a spec sets it to test the network-path rules anywhere).
---@type boolean
M.windows = vim.fn.has("win32") == 1

--- Whether `path` is a Windows network path (`//host/share`, `\\host\share`). Only
--- there does a stat on a host that does not answer block for the OS connect
--- timeout; on POSIX `//data` is an ordinary local path (the same as `/data`).
---@param path string
---@param win? boolean # Default: running on Windows (a spec passes it).
---@return boolean
function M.is_network_path(path, win)
  if win == nil then
    win = M.windows
  end
  return win and (path:find("^//[^/]") ~= nil or path:find("^\\\\") ~= nil)
end

--- Most links `leads_to_network` follows by hand before it gives up.
---@type integer
M.MAX_LINK_HOPS = 8

--- Does the symbolic link at `path` lead to a network path? Read link by link,
--- not followed: a stat follows them and blocks for the OS connect timeout on a
--- share that does not answer (21 s measured), and the string of `path` alone
--- says nothing about where it leads. A path that is no link is not one that
--- leads to a share, as far as its last component goes.
---@param path string
---@return boolean
function M.leads_to_network(path)
  for _ = 1, M.MAX_LINK_HOPS do
    local target = vim.uv.fs_readlink(path)
    if not target then
      return false -- not a link (any more): a stat is safe from here
    end
    target = (target:gsub(string.char(92), "/"))
    if M.is_network_path(target) or target:find("^//%?/UNC/") or target:find("^/%?%?/UNC/") then
      return true
    end
    if not (target:find("^/") or target:find("^%a:")) then
      -- relative to the link's folder (`dirname` of `X:/l` keeps the slash: `X:/`)
      target = ((vim.fs.dirname(path) or "."):gsub("/+$", "")) .. "/" .. target
    end
    path = target
  end
  return true -- a loop, or a chain this deep: not worth a stat
end

---@internal
--- Whether `path` is on disk, by `fs_stat` -- but not for a network path
--- (`//host/share`, `\\host\share`): a stat on one that does not answer blocks Neovim
--- for the OS connect timeout (21 s measured), and a time budget cannot interrupt
--- a call that is already blocked. nil is "not looked at", the answer for a path
--- nobody asked the disk about; every caller of `resolve` gets it by default
--- (hover and definition, the marksman filter, the diagnostics).
---@param path string
---@return boolean|nil
local function on_disk(path)
  if M.is_network_path(path) or M.leads_to_network(path) then
    return nil
  end
  return vim.uv.fs_stat(path) ~= nil
end

--- Resolve a link target.
---
--- nil when the target is not an env/home reference at all, or names a
--- variable nothing defines -- the caller then leaves the link alone, which
--- is the right answer for "cannot tell". Also nil for a target that decodes
--- to a path holding a control byte (`%00`): no file has one, and a NUL would
--- cut the path short in every call that hands it to the OS.
---@param target string
---@param opts? LspNvim.EnvLink.ResolveOpts
---@return LspNvim.EnvLink.Resolved|nil
function M.resolve(target, opts)
  if not M.is_env_target(target) then
    return nil
  end
  local path, fragment = M.split(target)
  if path:find("[%z\1-\31]") then
    return nil
  end
  local stat = opts and opts.stat or on_disk

  local home = resolve_home(path)
  if home then
    return {
      path = home,
      exists = stat(home),
      fragment = fragment,
      source = "builtin",
    }
  end

  local via = resolve_gopath(path)
  if via then
    return {
      path = via,
      exists = stat(via),
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
    exists = stat(resolved),
    fragment = fragment,
    source = "builtin",
  }
end

--- Longest link target or path quoted in a message, in bytes.
---@type integer
M.MAX_QUOTED_BYTES = 200

--- `text` made safe to quote in a message: no control bytes (the link target is
--- whatever the document says, a `<...>` one may hold a tab or an escape), and
--- not longer than `MAX_QUOTED_BYTES`.
---@param text string
---@return string
function M.quoted(text)
  text = text:gsub("%c", "?")
  if #text > M.MAX_QUOTED_BYTES then
    text = text:sub(1, M.MAX_QUOTED_BYTES) .. "..."
  end
  return text
end

--- A resolved path as it may be shown, or nil when it may not: an absolute one
--- below a directory that exists (not the root alone). The path is the variable's value joined with the rest
--- of the target, and a variable can hold anything: `[x]($API_TOKEN/a.md)`
--- resolves to `<the token>/a.md`, which is not a path and must not be put on the
--- screen by a document. A secret is not a directory (and one that happens to
--- start with a slash has no directory that exists), so it is not shown; a
--- path to a file that is not there yet, in a folder that is, is.
---@param path string
---@param stat? fun(path: string): boolean|nil # Whether a path is on disk (default: guarded `fs_stat`).
---@return string|nil
function M.displayable_path(path, stat)
  if not (path:find("^/") or path:find("^%a:/")) then
    return nil
  end
  -- A directory below the root, not the root: `/` and `C:/` always exist, so a
  -- value that is nothing but `/secret` or `C:/secret` would otherwise pass.
  local dir = path:match("^(.*)/[^/]*$")
  if dir == nil or dir:find("^/*$") or dir:find("^%a:/*$") then
    return nil
  end
  if not (stat or on_disk)(dir) then
    return nil
  end
  return M.quoted(path)
end

--- Where a link was looked up, as the tail of a message: ` (resolved to <path>)`,
--- or nothing when the path may not be shown (see `displayable_path`).
---@param path string
---@param stat? fun(path: string): boolean|nil
---@return string
function M.looked_up_at(path, stat)
  local shown = M.displayable_path(path, stat)
  return shown and (" (resolved to " .. shown .. ")") or ""
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
---@return integer|nil after # First byte after the destination.
local function parse_target(line, i)
  if line:byte(i) == 60 then -- "<"
    local gt = line:find(">", i + 1, true)
    if not gt or gt - i - 1 > M.MAX_TARGET_BYTES then
      return nil, nil
    end
    return line:sub(i + 1, gt - 1), line:find(")", gt + 1, true) or gt, gt + 1
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
  if j == i then
    -- Empty or blank-led target (`[x]()`, `[x]( p)`, a trailing `[x](`): found
    -- by the first `find`, so it costs one byte, not a whole target.
    return nil, i - 1
  end
  if j - i > M.MAX_TARGET_BYTES then
    return nil, nil
  end
  return line:sub(i, j - 1), line:find(")", j, true) or (j - 1), j
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

---@internal
--- The inline links of one line, found in one left-to-right pass over its
--- brackets -- the one rule set `target_at` and `links` both go by.
---
--- A stack holds the `[` not yet closed, and a `]` closes the innermost. A `](`
--- right after it makes an inline link whose text starts there. The text may
--- hold balanced brackets and an image (the badge pattern,
--- `[![alt](img)](target)`), and a backslash escapes the byte after it (`\]`).
--- Inner links are completed, and so found, before the ones around them.
---
--- A link cannot contain a link (CommonMark): once one is formed, the `[` still
--- open around it are dead and their `](` is text -- except an image's, whose
--- description may hold a link. `dead` is how many of the lowest stack entries
--- that is true for, so it costs nothing per bracket.
---
--- With `col` (column mode) it returns the target of the link that holds the
--- byte column `col`, and skips the targets that cannot reach it: a link that
--- starts past `col`, or whose target starts more than a target's length before
--- it, is not parsed -- unless a `[` is open around it, because whether it
--- forms decides whether that one is dead. Without `col`, it appends every
--- link to `found`.
---
--- The target bytes examined are budgeted (`TARGET_SCAN_BUDGET`,
--- `LINKS_SCAN_BUDGET`): nesting lets one hostile line make thousands of `](`
--- each parse a target that runs to the limit (273 ms measured, 10000 `[` and
--- 5000 `](`). A link that fails to parse is charged what the parse cost: the
--- limit for one that ran on, a byte for an empty target.
---@param line string
---@param col integer|nil
---@param found LspNvim.EnvLink.Span[]|nil
---@return string|nil target # Column mode only.
local function walk(line, col, found)
  local opens, imgs, n = {}, {}, 0 ---@type integer[], boolean[], integer
  local dead, escaped = 0, 0 -- `escaped`: the byte the last backslash escaped
  local budget = col and TARGET_SCAN_BUDGET or LINKS_SCAN_BUDGET
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
      escaped = i + 1
    elseif c == 91 then -- "["
      n = n + 1
      opens[n] = i
      imgs[n] = i > 1 and line:byte(i - 1) == 33 and escaped ~= i - 1 -- an unescaped "!"
    elseif n > 0 then -- "]"
      local open, img = opens[n], imgs[n]
      local live = img or n > dead
      n = n - 1
      if dead > n then
        dead = n
      end
      if live and line:byte(i + 1) == 40 then -- "]("
        local reaches = true
        if col then
          -- Counting the `>` and `)` that close a `<...>` target as part of
          -- the link.
          reaches = open <= col and i + 4 + M.MAX_TARGET_BYTES >= col
        end
        if reaches or n > 0 then
          local target, close, after = parse_target(line, i + 2)
          if target and close then
            if col == nil then
              local first = i + 2 + (line:byte(i + 2) == 60 and 1 or 0)
              found[#found + 1] = { target = target, first = first, last = first + #target - 1 }
            elseif reaches and col <= close then
              return target
            end
          end
          -- The links around it are dead only when this one really is a link:
          -- the destination is followed by `)` or a title. `[x](a b)` and
          -- `[x](foo` (still being typed) are answered, leniently, but they
          -- are text to CommonMark and must not take the enclosing link with
          -- them. `[x]()` is a link.
          local formed = false
          if target then
            local nxt = after and line:find("%S", after)
            local b = nxt and line:byte(nxt)
            formed = b == 41 or b == 34 or b == 39 or b == 40
          elseif close and line:byte(i + 2) == 41 then
            formed = true
          end
          if formed and not img then
            dead = n
          end
          budget = budget - (close and (close - i) or M.MAX_TARGET_BYTES)
          if budget < 0 then
            break
          end
        end
        -- Links come left to right, but an enclosing one is only completed
        -- after the inner ones: nothing further right can hold `col` once
        -- this one starts past it AND no `[` still open starts before it.
        if col and open > col and (n == 0 or opens[1] > col) then
          break
        end
      end
    end
  end
  return nil
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

  local target = walk(line, col, nil)
  if target then
    return target
  end

  -- A reference definition is a link too, and answers from any column of its
  -- line, the title's included.
  return (ref_definition(line))
end

-- ----------------------------------------------------------------------------
-- Every link in a buffer
-- ----------------------------------------------------------------------------

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

  walk(line, nil, found)

  local ref, first, last = ref_definition(line)
  if ref and first and last then
    found[#found + 1] = { target = ref, first = first, last = last }
  end
  return found
end

--- `text` with the inside of every code span (`` `x` ``, ``` ``x`` ```) blanked
--- out, byte for byte, so columns still line up. A span ends at the next run of
--- exactly as many backticks; a run with none stays text, as in CommonMark.
---
--- A backslash escapes a backtick only outside a span: an odd number of them
--- right before a run makes it open with one backtick less, and a run that ends
--- a span counts in full (`C:\` is a span that ends in a backslash).
---
--- Linear: the runs are matched from the right in one pass instead of searching
--- ahead from each opener, which a line of backticks of a hundred different
--- lengths would turn quadratic.
---@param text string
---@return string
function M.mask_code_spans(text)
  if not text:find("`", 1, true) then
    return text
  end

  local starts, stops, escaped = {}, {}, {}
  local pos = 1
  while true do
    local s, e = text:find("`+", pos)
    if not s then
      break
    end
    local b = s - 1 -- an odd number of backslashes right before the run
    while b >= 1 and text:byte(b) == 92 do
      b = b - 1
    end
    starts[#starts + 1], stops[#stops + 1] = s, e
    escaped[#escaped + 1] = (s - 1 - b) % 2 == 1
    pos = e + 1
  end

  local next_same, next_less, latest = {}, {}, {} ---@type table<integer, integer>, table<integer, integer>, table<integer, integer>
  for k = #starts, 1, -1 do
    local len = stops[k] - starts[k] + 1
    next_same[k] = latest[len]
    next_less[k] = latest[len - 1]
    latest[len] = k
  end

  local out, from, k = {}, 1, 1
  while k <= #starts do
    local first = starts[k]
    local close ---@type integer|nil
    if escaped[k] then
      first = first + 1 -- the escaped backtick is text, the rest of the run opens
      close = next_less[k]
    else
      close = next_same[k]
    end
    if close and first <= stops[k] then
      out[#out + 1] = text:sub(from, first - 1)
      out[#out + 1] = (" "):rep(stops[close] - first + 1)
      from = stops[close] + 1
      k = close + 1
    else
      k = k + 1
    end
  end
  out[#out + 1] = text:sub(from)
  return table.concat(out)
end

---@class LspNvim.EnvLink.Fence
---@field char string # "`" or "~".
---@field len integer # How many of them opened the block.
---@field quote integer # Block quote depth the block was opened at.
---@field indent integer # Columns of the list item it was opened in (0: none).

---@internal
--- The block quote depth of `line` (how many `>`), and the line without them.
---@param line string
---@return integer depth
---@return string rest
---@return string[] leads # The blanks before each `>`.
local function unquote(line)
  -- One `>` and at most one blank after it, per level: what follows keeps its
  -- own indentation (`>   [x]` is a continuation line of a list item).
  local pos, depth, leads = 1, 0, {}
  while true do
    local _, e, lead = line:find("^([ \t]*)>[ \t]?", pos)
    if not e then
      break
    end
    depth = depth + 1
    leads[depth] = lead
    pos = e + 1
  end
  if depth == 0 then
    return 0, line, leads
  end
  return depth, line:sub(pos), leads
end

---@internal
--- The width in columns of `s`, a tab going to the next multiple of four.
---@param s string
---@return integer
local function columns(s)
  local w = 0
  for k = 1, #s do
    w = s:byte(k) == 9 and w + 4 - w % 4 or w + 1
  end
  return w
end

---@internal
--- The state of fenced-code-block tracking after `line`, and whether the line
--- is no document text: the fence line itself, or a line inside the block.
---
--- CommonMark's rules, as far as a line-by-line pass can follow them:
---   * a block ends at a fence of the same character at least as long as the
---     opener, followed by nothing but blanks (so a "```js" inside a block is
---     content, not its end);
---   * the info string of a backtick fence holds no backtick (a line that
---     starts with "```x``` is inline code" is a paragraph, not an opener);
---   * a fence may open behind a list marker (`- ```md`), where it ends with
---     the list item (a line indented less than the item's content), and inside
---     a block quote (`> ```md`), where it ends with the quote; a fence line
---     closes a block only at the block's own quote depth.
--- (A single on/off toggle closed a `~~~` block at the first inner "```" line
--- and a four-backtick block at an inner three-backtick one, and the lines
--- after it were read as document; one such slip inverted the rest of the file.)
---@param fence LspNvim.EnvLink.Fence|nil # State before `line`; nil outside a block.
---@param line string
---@return LspNvim.EnvLink.Fence|nil fence
---@return boolean skip
local function fence_step(fence, line)
  local quote, rest, leads = unquote(line)
  if fence and quote < fence.quote then
    fence = nil -- the block quote that held the block ended, and the block with it
  end
  -- The list item the block was opened in ends at a line indented less than its
  -- content. Inside a deeper block quote the indentation is the blanks before the
  -- `>` (a `>` that starts before the content column is a quote of its own,
  -- and one at the content column is code), otherwise the blanks that remain
  -- after the quote prefix.
  if fence and fence.indent > 0 and rest:find("%S") then
    local cols = quote > fence.quote and columns(leads[fence.quote + 1])
      or columns(rest:match("^[ \t]*"))
    if cols < fence.indent then
      fence = nil
    end
  end
  local indent = 0
  if not fence then
    local item = rest:match("^%s*[-*+]%s+()") or rest:match("^%s*%d+[.)]%s+()")
    if item then
      indent = columns(rest:sub(1, item - 1))
      rest = rest:sub(item)
    end
  end

  local char, run, info = "`", rest:match("^%s*(```+)([^`]*)$")
  if not run then
    char, run, info = "~", rest:match("^%s*(~~~+)(.*)$")
  end
  if not run then
    return fence, fence ~= nil
  end
  if not fence then
    return { char = char, len = #run, quote = quote, indent = indent }, true
  end
  if quote == fence.quote and char == fence.char and #run >= fence.len and info:match("^%s*$") then
    return nil, true
  end
  return fence, true
end

---@internal
--- Does `line` start a block of its own (or is it blank)? Then it cannot go on
--- the paragraph above it: blank, heading, block quote, table row, list item,
--- thematic break.
---@param line string
---@param head? string # The first line of the paragraph the line would go on.
---@return boolean
local function opens_block(line, head)
  return line:find("^%s*$") ~= nil
    or line:find("^%s*[>|]") ~= nil
    or line:find("^%s*#+%s") ~= nil
    or line:find("^%s*#+$") ~= nil
    or line:find("^%s*[-*+]%s") ~= nil
    or line:find("^%s*1[.)]%s") ~= nil
    -- Another number cannot interrupt a paragraph, but after a numbered item it
    -- is the next item of the list.
    or (head ~= nil and line:find("^%s*%d+[.)]%s") ~= nil and head:find("^%s*%d+[.)]%s") ~= nil)
    or line:find("^%s*[-*_=][-*_= ]*[-*_=][-*_= ]*[-*_=]") ~= nil
end

---@internal
--- The last line of a YAML front matter: `---` on the first line, up to the next
--- `---` or `...`. 0 when there is none, or it is not closed.
---@param lines string[]
---@return integer
local function front_matter_end(lines)
  if lines[1] and lines[1]:match("^%-%-%-%s*$") then
    for k = 2, #lines do
      if lines[k]:match("^%-%-%-%s*$") or lines[k]:match("^%.%.%.%s*$") then
        return k
      end
    end
  end
  return 0
end

---@internal
--- Walk the paragraphs of a buffer's lines, front matter and fenced code blocks
--- left out: `visit(para)` gets each one as a list of `{ lnum, line }` (`lnum`
--- is 0-based) and answers true to stop the walk.
---
--- A paragraph ends at a blank line, a fence, or a line that opens a block of its
--- own (`opens_block`), and is cut at `MAX_LINE_BYTES`. (The lines of a block
--- quote are paragraphs of their own.)
---@param lines string[]
---@param visit fun(para: { lnum: integer, line: string }[]): boolean|nil
---@return nil
local function each_paragraph(lines, visit)
  local para, bytes = {}, 0 ---@type { lnum: integer, line: string }[], integer
  local stopped = false

  --- Hand the paragraph collected so far to `visit`.
  ---@return nil
  local function flush()
    if #para == 0 then
      return
    end
    local current = para
    para, bytes = {}, 0
    if visit(current) == true then
      stopped = true
    end
  end

  local fence ---@type LspNvim.EnvLink.Fence|nil
  local skip ---@type boolean
  for k = front_matter_end(lines) + 1, #lines do
    local line = lines[k]
    fence, skip = fence_step(fence, line)
    if skip or #line > M.MAX_LINE_BYTES then
      flush()
    else
      if opens_block(line, para[1] and para[1].line) or bytes + #line > M.MAX_LINE_BYTES then
        flush()
      end
      if not stopped and not line:find("^%s*$") then
        para[#para + 1] = { lnum = k - 1, line = line }
        bytes = bytes + #line + 1
      end
      if line:find("^%s*|") or line:find("^%s*#+%s") or line:find("^%s*#+$") then
        flush() -- a heading or a table row is a block of one line
      end
    end
    if stopped then
      return
    end
  end
  flush()
end

---@internal
--- The lines of a paragraph with the inside of every code span blanked out (see
--- `mask_code_spans`), cut by offset, not by splitting on "\n": a span that wraps
--- blanks the line break inside it too.
---@param para { lnum: integer, line: string }[]
---@return string[]
local function masked_lines(para)
  local texts = {}
  for i, entry in ipairs(para) do
    texts[i] = entry.line
  end
  local masked = M.mask_code_spans(table.concat(texts, "\n"))
  local out, off = {}, 1
  for i, entry in ipairs(para) do
    out[i] = masked:sub(off, off + #entry.line - 1)
    off = off + #entry.line + 1
  end
  return out
end

--- Every env link (`$VAR/...`, `${VAR}/...`, `~/...`) in a buffer's lines
--- that is a link in the Markdown sense: not inside a fenced code block or a
--- code span, not in a YAML front matter. Documentation that *shows* a link
--- must not be told its example is broken.
---
--- Code spans are found per paragraph, not per line: a span may wrap over a
--- line break (hard-wrapped prose does exactly that), and read line by line
--- the closing backtick would pair with the next one on its line, and the
--- link between them would be missed or an example in the next span exposed.
--- (See `each_paragraph` for where a paragraph ends: the lines of a block
--- quote are paragraphs of their own, a span that wraps over `>` lines is not
--- followed.)
---@param lines string[]
---@return LspNvim.EnvLink.Found[]
function M.scan(lines)
  local found = {} ---@type LspNvim.EnvLink.Found[]
  each_paragraph(lines, function(para)
    for i, text in ipairs(masked_lines(para)) do
      if text:find("[$~]") then
        for _, link in ipairs(M.links(text)) do
          if M.is_env_target(link.target) and #found < M.MAX_SCANNED_LINKS then
            found[#found + 1] =
              { lnum = para[i].lnum, target = link.target, first = link.first, last = link.last }
          end
        end
      end
    end
    return #found >= M.MAX_SCANNED_LINKS
  end)
  return found
end

--- Line `lnum` (1-based) of `lines` as `scan` sees it -- its code spans blanked
--- out, also the ones that wrap over a line break -- or nil when the line is no
--- document text: in a fenced code block or a front matter, blank, or too long.
---@param lines string[]
---@param lnum integer
---@return string|nil
function M.masked_line_at(lines, lnum)
  local result ---@type string|nil
  each_paragraph(lines, function(para)
    if para[#para].lnum + 1 < lnum then
      return false -- an earlier paragraph
    end
    for i, text in ipairs(masked_lines(para)) do
      if para[i].lnum + 1 == lnum then
        result = text
      end
    end
    return true -- the paragraph of `lnum`, or one past it: done
  end)
  return result
end

-- ----------------------------------------------------------------------------
-- Typing a link target
-- ----------------------------------------------------------------------------

---@class LspNvim.EnvLink.Typing
---@field text string # The target as typed so far, up to the cursor.
---@field start integer # 1-based byte of its first character (after a `<`).
---@field angled boolean # Written in `<...>`: blanks are allowed.

--- The link target being typed at the byte column `col` (1-based: the cursor
--- sits before that byte): the text from the start of the target up to the
--- cursor, in `[text](target`, `![alt](target` or `[label]: target`. nil when the
--- cursor is not in a target, or the target is already closed (`)` or `>`
--- before it) or has a blank in it (a bare target ends at one).
---
--- Works on one line, like `target_at`.
---@param line any
---@param col any
---@return LspNvim.EnvLink.Typing|nil
function M.typing_at(line, col)
  if type(line) ~= "string" or type(col) ~= "number" or #line > M.MAX_LINE_BYTES then
    return nil
  end
  local before = line:sub(1, col - 1)

  local last ---@type integer|nil
  local pos = 1
  while true do
    local at = before:find("](", pos, true)
    if not at then
      break
    end
    last, pos = at, at + 1
  end

  local start ---@type integer|nil
  if last then
    start = last + 2
  else
    -- A reference definition: `[label]: target`.
    start = before:match("^%s*%[[^%]]+%]:%s*()")
  end
  if not start then
    return nil
  end

  local angled = before:byte(start) == 60 -- "<"
  if angled then
    start = start + 1
  end
  local text = before:sub(start)
  if angled then
    if text:find(">", 1, true) then
      return nil
    end
  else
    if text:find("%s") then
      return nil
    end
    local depth = 0
    for c in text:gmatch("[()]") do
      depth = depth + (c == "(" and 1 or -1)
      if depth < 0 then
        return nil -- the `)` that closes the link is before the cursor
      end
    end
  end
  -- An escaped `[`, or a link inside link text, opens nothing: use the rule set
  -- `target_at` goes by, with the target closed so an empty one forms. (A line
  -- with no `[` before the `](` is the continuation of link text that wrapped.)
  if last and before:sub(1, last):find("[", 1, true) then
    local closed = before .. (angled and "x>)" or "x)")
    if M.target_at(closed, #before) == nil then
      return nil
    end
  end
  return { text = text, start = start, angled = angled }
end

--- Is line `lnum` (1-based) of `lines` no document text: inside a fenced code
--- block or a YAML front matter, or a fence line itself?
---@param lines string[]
---@param lnum integer
---@return boolean
function M.fenced_at(lines, lnum)
  local front = front_matter_end(lines)
  if lnum <= front then
    return true
  end
  local fence ---@type LspNvim.EnvLink.Fence|nil
  local skip = false
  for k = front + 1, lnum do
    fence, skip = fence_step(fence, lines[k] or "")
  end
  return skip
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
  if not resolved or resolved.exists == nil then
    return nil, nil -- not looked at (a network path): cannot tell
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
--- The file `path` really is, when it is a small regular Markdown/text file --
--- one it is fine to read; nil otherwise.
---
--- Every check is made on the file that would be opened, not on how the link
--- spells it: a symlink named `x.md` that points at `~/.ssh/id_rsa` has the
--- extension of a document and the content of a key, and `x%00.md` decodes to
--- a path the OS cuts short at the NUL. So the path is resolved first, and its
--- extension, type and size are what count.
---@param path string
---@return string|nil real
---@return table|nil stat # `vim.uv.fs_stat` of `real`.
local function text_doc(path)
  if path:find("[%z\1-\31]") then
    return nil
  end
  local real = vim.uv.fs_realpath(path)
  if not real then
    return nil
  end
  local ext = real:match("%.(%w+)$")
  if not ext or not TEXT_DOC_EXT[ext:lower()] then
    return nil
  end
  local st = vim.uv.fs_stat(real)
  if not st or st.type ~= "file" or st.size > M.MAX_READ_BYTES then
    return nil
  end
  return real, st
end

---@internal
--- Lowercase `s`, multibyte-aware. A NUL is dropped first: `vim.fn.tolower`
--- raises on one (E976), and the text comes from a link fragment or from a file
--- this module does not control.
---@param s string
---@return string
local function lower(s)
  return vim.fn.tolower((s:gsub("%z", "")))
end

---@internal
--- The GitHub-style anchor of a heading: lowercase, punctuation dropped, spaces
--- to hyphens. Lowercasing is multibyte-aware (`Ü` -> `ü`, which `string.lower`
--- would leave alone) and non-ASCII bytes are kept -- both are what keep
--- `Übersicht` and friends working in a German document.
---
--- JavaScript's `toLowerCase`, which GitHub's slugger uses, differs from Vim's
--- in two places, so both spellings are folded to one: `İ` becomes `i` plus a
--- combining dot (U+0307), and a capital sigma at the end of a word becomes
--- `ς` where Vim has `σ`. The same fold runs on the fragment of a link, so
--- whichever form is written finds the heading.
---@param title string
---@return string
local function slug(title)
  local s = lower(title):gsub("[^%w%s%-_\128-\255]", "")
  s = s:gsub("\204\135", ""):gsub("\207\130", "\207\131")
  return (s:gsub("%s", "-"))
end

---@internal
--- Where a heading's title starts in `line` after the container markers (block
--- quotes and list markers, which may nest), and that the line is a heading at
--- all: 0-3 spaces, one to six `#`, a blank. nil for any other line.
---
--- The trailing spaces and closing `#`s are stripped by walking back from the
--- end. The obvious `^#+%s+(.-)%s*#*%s*$` is cubic on a line with a long run
--- of spaces inside it (measured: 0.5 s at 1000 bytes, 4.3 s at 2000), and the
--- line comes from a file this module does not control.
---@param line string
---@return string|nil
local function heading_title(line)
  if #line > M.MAX_HEADING_BYTES or not line:find("#", 1, true) then
    return nil -- the cheap check keeps the container walk off ordinary lines
  end
  -- A heading may sit in a block quote or a list item, and GitHub gives it an
  -- anchor there too. Walked by position, bounded in depth.
  local pos = 1
  for _ = 1, 8 do
    local _, e = line:find("^%s*>%s?", pos)
    if not e then
      _, e = line:find("^%s*[-*+]%s+", pos)
    end
    if not e then
      _, e = line:find("^%s*%d%d?%d?%d?%d?%d?%d?%d?%d?[.)]%s+", pos)
    end
    if not e then
      break
    end
    pos = e + 1
  end
  local hashes, rest = line:match("^ ? ? ?(#+)%s+(.*)$", pos)
  if not hashes or #hashes > 6 then
    return nil -- seven `#` are a paragraph, not a heading
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
--- Named character references a heading is likely to hold, as code points.
--- Unknown names stay as written.
---@type table<string, integer>
local NAMED_ENTITIES = {
  amp = 0x26,
  lt = 0x3C,
  gt = 0x3E,
  quot = 0x22,
  apos = 0x27,
  nbsp = 0xA0,
  iexcl = 0xA1,
  cent = 0xA2,
  pound = 0xA3,
  yen = 0xA5,
  sect = 0xA7,
  copy = 0xA9,
  laquo = 0xAB,
  reg = 0xAE,
  deg = 0xB0,
  plusmn = 0xB1,
  para = 0xB6,
  middot = 0xB7,
  raquo = 0xBB,
  frac12 = 0xBD,
  times = 0xD7,
  Auml = 0xC4,
  Ouml = 0xD6,
  Uuml = 0xDC,
  szlig = 0xDF,
  agrave = 0xE0,
  aacute = 0xE1,
  auml = 0xE4,
  ccedil = 0xE7,
  egrave = 0xE8,
  eacute = 0xE9,
  ntilde = 0xF1,
  ouml = 0xF6,
  uuml = 0xFC,
  ndash = 0x2013,
  mdash = 0x2014,
  bull = 0x2022,
  hellip = 0x2026,
  euro = 0x20AC,
  trade = 0x2122,
  larr = 0x2190,
  rarr = 0x2192,
  hearts = 0x2665,
}

---@internal
--- `s` with `&name;`, `&#N;` and `&#xH;` decoded, as a renderer reads a heading
--- before it computes the anchor (`## Q&amp;A` is `#qa`, not `#qampa`).
--- Numeric references to 0, above U+10FFFF or to a surrogate are U+FFFD.
---@param s string
---@return string
local function decode_entities(s)
  if not s:find("&", 1, true) then
    return s
  end
  return (
    s:gsub("&(#?%w+);", function(ref)
      local named = NAMED_ENTITIES[ref]
      if named then
        return vim.fn.nr2char(named)
      end
      local cp
      local hex = ref:match("^#[xX](%x+)$")
      if hex and #hex <= 6 then
        cp = tonumber(hex, 16)
      else
        local dec = ref:match("^#(%d+)$")
        cp = dec and #dec <= 7 and tonumber(dec) or nil
      end
      if not cp then
        return nil -- not a reference: keep as written
      end
      if cp == 0 or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) then
        cp = 0xFFFD
      end
      return vim.fn.nr2char(cp)
    end)
  )
end

---@internal
--- The `)` that ends the destination of a link whose text closed at `from - 2`:
--- parentheses inside it balance (`[a](https://x/Foo_(bar))`), a backslash
--- escapes the next byte. nil when none closes it.
---@param shown string
---@param from integer # First byte after the `(`.
---@return integer|nil
local function destination_end(shown, from)
  local depth, j = 0, from
  while true do
    local c = shown:find("[()" .. string.char(92) .. "]", j)
    if not c then
      return nil
    end
    local b = shown:byte(c)
    if b == 92 then
      j = c + 2
    elseif b == 40 then
      depth = depth + 1
      j = c + 1
    elseif depth == 0 then
      return c
    else
      depth = depth - 1
      j = c + 1
    end
  end
end

---@internal
--- One rewriting pass over a title: `[text](url)` becomes its text and
--- `![alt](url)` its alt text (`keep_alt`) or nothing -- an `<img>` has no text
--- in the rendered heading, so GitHub's anchor has none of it. A single
--- left-to-right sweep over the brackets with a stack, so `[a [b] c](u)` pairs
--- the outer brackets: when no closing `)` is left, none will be found later
--- either, so the sweep stops instead of searching again from every opener.
--- What is inside a code span is literal and is left alone (the sweep looks at
--- a masked copy, and cuts the real title at the same offsets).
---@param title string
---@param keep_alt boolean
---@return string
local function strip_links(title, keep_alt)
  local shown = M.mask_code_spans(title)
  local out, piece = {}, 1
  local opens, n = {}, 0 ---@type integer[], integer
  local i = 1
  while true do
    local k = shown:find("[%[%]" .. string.char(92) .. "]", i)
    if not k then
      break
    end
    i = k + 1
    local c = shown:byte(k)
    if c == 92 then -- a backslash escapes the next byte
      i = k + 2
    elseif c == 91 then -- "["
      n = n + 1
      opens[n] = k
    elseif n > 0 then -- "]"
      local open = opens[n]
      n = n - 1
      if shown:byte(k + 1) == 40 then -- "]("
        local close = destination_end(shown, k + 2)
        if not close then
          break
        end
        local image = open > 1 and shown:byte(open - 1) == 33 -- "!"
        local from = image and open - 1 or open
        if from >= piece then
          out[#out + 1] = title:sub(piece, from - 1)
          if not image or keep_alt then
            out[#out + 1] = title:sub(open + 1, k - 1)
          end
          piece = close + 1
        end
        i = close + 1
      end
    end
  end
  out[#out + 1] = title:sub(piece)
  return table.concat(out)
end

---@internal
--- A title as it reads once rendered, as far as the anchor is concerned: links
--- and images rewritten (a badge, `[![ci](img)](url)`, takes a second pass, and
--- a third is the most any real title needs), HTML tags gone and autolinks
--- (`<https://x.org>`) unwrapped to their text, character references decoded.
--- Text in a code span is literal and stays as it is, entities included.
---@param title string
---@param keep_alt? boolean # Keep the alt text of an image (default: drop it).
---@return string
local function rendered_title(title, keep_alt)
  for _ = 1, 3 do
    if not title:find("](", 1, true) then
      break
    end
    local before = title
    title = strip_links(title, keep_alt == true)
    if title == before then
      break
    end
  end

  if title:find("<", 1, true) then
    local shown = M.mask_code_spans(title)
    local out, piece = {}, 1
    local i = 1
    while true do
      local k = shown:find("<", i, true)
      if not k then
        break
      end
      local auto = shown:match("^<(%a[%w+.-]*:[^%s<>]*)>", k)
        or shown:match("^<([%w._%%+-]+@[%w.-]+)>", k)
      if shown:sub(k, k + 3) == "<!--" then
        local close = shown:find("-->", k + 4, true)
        if not close then
          break
        end
        out[#out + 1] = title:sub(piece, k - 1)
        piece = close + 3
        i = piece
      elseif auto then
        out[#out + 1] = title:sub(piece, k - 1)
        out[#out + 1] = title:sub(k + 1, k + #auto)
        piece = k + #auto + 2
        i = piece
      elseif shown:find("^/?%a[%w:-]*[%s/>]", k + 1) then -- `<T, E>` is text, not a tag
        local close = shown:find(">", k, true)
        if not close then
          break
        end
        out[#out + 1] = title:sub(piece, k - 1)
        piece = close + 1
        i = close + 1
      else
        i = k + 1
      end
    end
    out[#out + 1] = title:sub(piece)
    title = table.concat(out)
  end

  if not title:find("&", 1, true) then
    return title
  end
  -- References are decoded outside code spans only: a span's text is literal.
  local shown = M.mask_code_spans(title)
  local out, pos = {}, 1
  while true do
    local s_, e_ = title:find("&#?%w+;", pos)
    if not s_ then
      break
    end
    out[#out + 1] = title:sub(pos, s_ - 1)
    local ref = title:sub(s_, e_)
    out[#out + 1] = shown:byte(s_) == 32 and ref or decode_entities(ref)
    pos = e_ + 1
  end
  out[#out + 1] = title:sub(pos)
  return table.concat(out)
end

---@internal
--- Ranges (`{ first, last }`, sorted) of characters GitHub drops from an anchor
--- but `slug` cannot tell from a letter in another script: Latin-1 symbols,
--- general punctuation, arrows, math and dingbats, CJK and full-width
--- punctuation, Arabic and Devanagari punctuation, variation selectors.
---@type integer[][]
local SYMBOL_RANGES = {
  { 0xA0, 0xBF },
  { 0xD7, 0xD7 },
  { 0xF7, 0xF7 },
  { 0x60C, 0x60D },
  { 0x61B, 0x61B },
  { 0x61E, 0x61F },
  { 0x66A, 0x66D },
  { 0x6D4, 0x6D4 },
  { 0x964, 0x965 },
  { 0x2000, 0x2BFF },
  { 0x3000, 0x303F },
  { 0xFE00, 0xFE0F },
  { 0xFF01, 0xFF0F },
  { 0xFF1A, 0xFF20 },
  { 0xFF3B, 0xFF40 },
  { 0xFF5B, 0xFF65 },
}

---@internal
--- Is the code point `cp` one GitHub drops from an anchor?
---@param cp integer
---@return boolean
local function is_symbol(cp)
  if cp >= 0x1F000 then
    return true
  end
  for _, range in ipairs(SYMBOL_RANGES) do
    if cp < range[1] then
      return false
    elseif cp <= range[2] then
      return true
    end
  end
  return false
end

---@internal
--- `s` without symbols and emoji, which GitHub drops from an anchor but
--- `slug` cannot tell from a letter in another script. Only ever used for an
--- *additional* key (`## 🚀 Features` is `#-features` on GitHub), so a wrong
--- guess here makes a link resolve that should not, never the reverse.
---@param s string
---@return string
local function without_symbols(s)
  if not s:find("[\128-\255]") then
    return s -- plain ASCII has none, and this runs on every heading
  end
  local ok, out = pcall(function()
    local starts = vim.str_utf_pos(s)
    local kept = {}
    for k, from in ipairs(starts) do
      local char = s:sub(from, (starts[k + 1] or #s + 1) - 1)
      if #char == 1 or not is_symbol(vim.fn.char2nr(char)) then
        kept[#kept + 1] = char
      end
    end
    return table.concat(kept)
  end)
  return ok and out or s
end

---@internal
--- Is the byte `c` part of a word: alphanumeric, or of a multibyte character?
---@param c integer|nil
---@return boolean
local function word_byte(c)
  return c ~= nil
    and (c >= 128 or (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122))
end

---@internal
--- `s` without the underscores that read as emphasis (`_x_`, `__x__`, `a _b_
--- c`): GitHub renders them as <em>/<strong> and builds the anchor from the
--- text, so they are not in it. An underscore run between two alphanumerics
--- (`snake_case`) is literal and stays. Only ever used for an *additional* key,
--- like `without_symbols`. One pass over whole runs: a run is judged by the
--- bytes on its two sides (removing a run never joins two words), and a
--- pattern that restarts at every underscore of a run is quadratic.
---@param s string
---@return string
local function without_emphasis_underscores(s)
  return (
    s:gsub("()(_+)()", function(p, run, q)
      if word_byte(s:byte(p - 1)) and word_byte(s:byte(q)) then
        return run
      end
      return ""
    end)
  )
end

---@internal
--- Is `line` a setext underline (`===` or `---`, at most three blanks before)?
---@param line string
---@return boolean
local function is_setext_underline(line)
  return line:match("^ ? ? ?=+%s*$") ~= nil or line:match("^ ? ? ?%-+%s*$") ~= nil
end

---@class LspNvim.EnvLink.HeadingIndex : table<string, integer>

---@class LspNvim.EnvLink.IndexCacheEntry
---@field size integer
---@field sec integer
---@field nsec integer
---@field index LspNvim.EnvLink.HeadingIndex

--- How many heading indexes are kept between calls.
---@type integer
M.INDEX_CACHE_SIZE = 64

---@type table<string, LspNvim.EnvLink.IndexCacheEntry>
local index_cache = {}
---@type string[] # Keys of `index_cache`, oldest first.
local index_cache_order = {}

--- Forget every cached heading index.
---@return nil
function M.clear_cache()
  index_cache = {}
  index_cache_order = {}
end

--- The anchors of the Markdown file at `path`, each with the 0-based line it
--- names: a heading's GitHub-style slug (ATX headings, also in block quotes and
--- list items; setext headings at the top level; a repeated heading `x` is `x`,
--- `x-1`, `x-2`, ..., counted on the anchor GitHub ends up with), its
--- `{#custom-id}`, and the `id`/`name` of an HTML anchor. Headings inside fenced code blocks and a YAML
--- front matter are not headings.
---
--- Besides the exact GitHub anchor a heading is also known by a few lenient
--- spellings (its emoji or its emphasis underscores left in, an image's alt
--- text kept, the title with its `{#id}`): they can only make a link resolve
--- that GitHub would not, never the reverse.
---
--- nil when the file cannot be judged: not Markdown or text, too large, or
--- unreadable. That is "cannot tell", not "no anchors".
---
--- Diagnostics ask for the same few files on every keystroke, so an index is
--- kept (`INDEX_CACHE_SIZE` of them, by the file's real path) for as long as
--- the file's size and modification time stay the same: one `fs_stat` instead of
--- a read and a parse, and the case variants of a path on a case-insensitive
--- file system are one file. The returned table is shared: do not change it.
---@param path string
---@param only_cached? boolean # Answer from the cache or not at all: no read, no parse.
---@return LspNvim.EnvLink.HeadingIndex|nil index
---@return boolean|nil cached # True when it came from the cache: a stat, no read.
function M.heading_index(path, only_cached)
  local real, st = text_doc(path)
  if not real or not st then
    return nil
  end
  local hit = index_cache[real]
  if hit and hit.size == st.size and hit.sec == st.mtime.sec and hit.nsec == st.mtime.nsec then
    return hit.index, true
  end
  if only_cached then
    return nil
  end
  local content = require("lib.nvim.fs.read")(real)
  if not content then
    return nil
  end
  -- Neovim hides a UTF-8 byte order mark; `fs.read` does not, and it would
  -- glue itself to the first line and hide a `# Title` there.
  if content:sub(1, 3) == "\239\187\191" then
    content = content:sub(4)
  end

  local index = {} ---@type LspNvim.EnvLink.HeadingIndex
  -- The anchors GitHub gives, counted the way github-slugger counts them, and
  -- the lenient spellings a heading is also known by, counted among themselves:
  -- an exact anchor always wins over a lenient one, whatever the order.
  local occ, lenient, locc = {}, {}, {} ---@type table<string, integer>, table<string, integer>, table<string, integer>
  ---@param tbl table<string, integer>
  ---@param key string
  ---@param n integer
  local function add(tbl, key, n)
    if key ~= "" and tbl[key] == nil then
      tbl[key] = n
    end
  end
  --- Register `anchor` the way GitHub numbers it (github-slugger): the first
  --- heading with it gets it bare, later ones `-1`, `-2`, ..., skipping a number
  --- another heading's anchor already took.
  ---@param anchor string
  ---@param n integer
  ---@param tbl table<string, integer>
  ---@param counter table<string, integer>
  local function numbered(anchor, n, tbl, counter)
    if anchor == "" then
      return
    end
    local result = anchor
    while counter[result] ~= nil do
      counter[anchor] = counter[anchor] + 1
      result = anchor .. "-" .. counter[anchor]
    end
    counter[result] = 0
    add(tbl, result, n)
  end
  --- Index one heading: `title` is its source text, `n` its first line.
  ---@param title string
  ---@param n integer
  local function index_title(title, n)
    local text, id = split_custom_id(title)
    -- Not trimmed: a trailing image or tag leaves the blank before it, and that
    -- is the hyphen GitHub keeps (`## Title <img>` is `#title-`).
    local rendered = rendered_title(text)
    if rendered:match("^%s*$") then
      rendered = ""
    end
    local plain = rendered:find("_", 1, true) and without_emphasis_underscores(rendered) or rendered

    -- What GitHub ends up with: emphasis and symbols dropped.
    local exact = slug(without_symbols(plain))
    numbered(exact, n, index, occ)

    -- The lenient spellings (an emoji or emphasis left in, an image's alt text
    -- kept, the title with its `{#id}`, any of them trimmed). Each distinct one
    -- once, and none that is the exact one.
    local seen, tried = { [exact] = true }, {}
    ---@param text_ string
    local function spelled(text_)
      if tried[text_] then
        return -- the same text again (an ASCII title without `_` is all of them)
      end
      tried[text_] = true
      local anchor = slug(text_)
      if anchor ~= "" and not seen[anchor] then
        seen[anchor] = true
        numbered(anchor, n, lenient, locc)
      end
    end
    spelled(rtrim(without_symbols(plain)))
    spelled(rendered)
    spelled(rtrim(rendered))
    spelled(plain)
    spelled(without_symbols(rendered))
    if text:find("![", 1, true) then
      local alt = rendered_title(text, true)
      spelled(alt)
      spelled(rtrim(alt))
    end
    if id then
      add(index, lower(id), n)
      -- GitHub has no custom ids: it renders the braces as text.
      local full = rendered_title(title)
      spelled(full)
      spelled(rtrim(full))
    end
  end

  -- A YAML front matter is no document text: `# a comment` in it is not a
  -- heading. Only one that is closed counts, as in `scan`.
  local front_until = -1 ---@type integer # Last 0-based line of the front matter.
  if content:match("^%-%-%-[ \t]*\r?\n") then
    local k = 0
    for line in (content .. "\n"):gmatch("(.-)\r?\n") do
      if k > 0 and (line:match("^%-%-%-%s*$") or line:match("^%.%.%.%s*$")) then
        front_until = k
        break
      end
      k = k + 1
    end
  end

  local fence ---@type LspNvim.EnvLink.Fence|nil
  local skip ---@type boolean
  local para, para_first = {}, 0 ---@type string[], integer # Lines of the paragraph a setext underline would turn into a heading.
  local n = 0
  for line in (content .. "\n"):gmatch("(.-)\r?\n") do
    if n <= front_until then
      fence, skip = nil, true -- YAML is no Markdown: its lines open no fence
    else
      fence, skip = fence_step(fence, line)
    end
    if skip then
      para = {}
    else
      local title = heading_title(line)
      if is_setext_underline(line) and #para > 0 then
        index_title(table.concat(para, " "), para_first)
        para = {}
      elseif title then
        index_title(title, n)
        para = {}
      elseif opens_block(line, para[1]) then
        para = {}
      elseif #line <= M.MAX_HEADING_BYTES and #para < 8 then
        if #para == 0 then
          para_first = n
        end
        -- Leading blanks and the trailing ones before a line break are no
        -- part of the title.
        para[#para + 1] = rtrim(line:sub(line:match("^%s*()")))
      else
        para = {} -- too long to be a heading: it is not one, and neither is what follows
      end
      if line:find("<", 1, true) and not fence then
        for _, attr in ipairs({ "id", "name" }) do
          for value in line:gmatch("%s" .. attr .. "%s*=%s*[\"']([^\"']+)[\"']") do
            add(index, lower(value), n)
          end
        end
      end
    end
    n = n + 1
  end

  for key, line_no in pairs(lenient) do
    if index[key] == nil then
      index[key] = line_no
    end
  end

  if hit then
    -- A changed file is indexed again: its old place in the order goes, or the
    -- key would be in the list twice and the eviction would drop the entry just
    -- made (every call after that a miss).
    for k = #index_cache_order, 1, -1 do
      if index_cache_order[k] == real then
        table.remove(index_cache_order, k)
        break
      end
    end
  end
  index_cache[real] = { size = st.size, sec = st.mtime.sec, nsec = st.mtime.nsec, index = index }
  index_cache_order[#index_cache_order + 1] = real
  while #index_cache_order > M.INDEX_CACHE_SIZE do
    index_cache[table.remove(index_cache_order, 1)] = nil
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
  return index[slug(decoded)] or index[lower(decoded)]
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
  local real = text_doc(path)
  if not real then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, real, "", max_lines)
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
