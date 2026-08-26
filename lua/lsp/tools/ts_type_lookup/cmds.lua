---@module 'lsp.tools.ts_type_lookup.cmds'
--- Utilities and usercommands to lookup TypeScript type definitions by symbol string.
--- Commands accept an optional argument; when omitted the current word (`<cword>`) is used.
local notify = require("lib.nvim.notify").create("[lsp.tools.ts_type_lookup.cmds]")
local usercmd = require("lib.nvim.bindings.usercmd")
local viewer = require("lib.nvim.ui.kit.viewer")

local api = vim.api
local lsp = vim.lsp
local fn = vim.fn
local M = {}

--- Helper: get workspace root via active LSP client or fallback to cwd
---@return string
local function get_root()
  local bufnr = api.nvim_get_current_buf()
  local clients = lsp.get_clients({ bufnr = bufnr })
  for _, c in ipairs(clients) do
    local cfg = c.config
    if cfg then
      if cfg.root_dir and type(cfg.root_dir) == "string" then
        return cfg.root_dir
      end
      if cfg.workspace_folders and cfg.workspace_folders[1] and cfg.workspace_folders[1].uri then
        return vim.uri_to_fname(cfg.workspace_folders[1].uri)
      end
    end
  end
  return fn.getcwd()
end

--- Request LSP workspace/symbol for given query
---@param bufnr number
---@param query string
---@param cb function
local function workspace_symbol(bufnr, query, cb)
  local params = { query = query }
  lsp.buf_request(bufnr, "workspace/symbol", params, function(err, result)
    if err then
      cb(nil, err)
      return
    end
    if not result or vim.tbl_isempty(result) then
      cb(nil, "no results")
      return
    end
    cb(result, nil)
  end)
end

--- Normalize Location or LocationLink -> fname, srow, scol, erow, ecol
---@param item table
---@return string|nil, number, number, number, number
local function loc_to_path_range(item)
  local uri = item.uri
    or item.targetUri
    or (item.location and (item.location.uri or item.location.targetUri))
  local range = item.range
    or item.targetSelectionRange
    or item.targetRange
    or (item.location and item.location.range)
  local fname = uri and vim.uri_to_fname(uri) or nil
  local srow = (range and range.start and range.start.line or 0) + 1
  local scol = (range and range.start and range.start.character or 0) + 1
  local erow = (range and range["end"] and range["end"].line or 0) + 1
  local ecol = (range and range["end"] and range["end"].character or 0) + 1
  return fname, srow, scol, erow, ecol
end

--- Open a file in vertical split at given line
---@param fname string
---@param line number
local function open_in_vsplit(fname, line)
  if not fname then
    return
  end
  -- Escape filename to avoid issues with spaces/special chars.
  vim.cmd("vsplit " .. fn.fnameescape(fname))
  if line and line > 0 then
    -- Move cursor to requested line after opening
    vim.cmd(tostring(line))
  end
end

--- Public: try to go to a type definition for `symbol` using workspace/symbol then open found location
---@param symbol string
function M.go_to_type_definition_for(symbol)
  symbol = symbol ~= nil and symbol ~= "" and symbol or fn.expand("<cword>")
  local bufnr = api.nvim_get_current_buf()
  local clients = lsp.get_clients({ bufnr = bufnr })
  if not clients or vim.tbl_isempty(clients) then
    notify.warn("No active LSP client")
    return
  end

  workspace_symbol(bufnr, symbol, function(results, _)
    if not results then
      -- fallback: search in node_modules
      require("lsp.tools.ts_type_lookup.cmds").find_in_node_modules(symbol)
      return
    end
    -- Prefer the first result with a location
    for _, r in ipairs(results) do
      local loc = r.location or r
      if loc then
        local fname, srow = loc_to_path_range(loc)
        if fname then
          open_in_vsplit(fname, srow)
          return
        end
      end
    end
    -- fallback if nothing worked
    require("lsp.tools.ts_type_lookup.cmds").find_in_node_modules(symbol)
  end)
end

--- Public: peek type definition for symbol string (floating preview); default to <cword>
---@param symbol string|nil
function M.peek_type_definition_for(symbol)
  symbol = symbol ~= nil and symbol ~= "" and symbol or fn.expand("<cword>")
  local bufnr = api.nvim_get_current_buf()
  workspace_symbol(bufnr, symbol, function(results, _)
    if not results then
      notify.info("No workspace symbol found for: " .. symbol)
      require("lsp.tools.ts_type_lookup.cmds").find_in_node_modules(symbol)
      return
    end
    local r = results[1]
    local loc = r.location or r
    if not loc then
      notify.warn("No location in workspace symbol result")
      return
    end
    local fname, srow, _, erow = loc_to_path_range(loc)
    if not fname then
      return
    end
    local ok, content = pcall(fn.readfile, fname)
    if not ok or not content then
      notify.warn("Could not read " .. fname)
      return
    end
    local start_line = math.max(1, srow - 2)
    local end_line = math.min(#content, erow + 2)
    local lines = {}
    for i = start_line, end_line do
      table.insert(lines, content[i])
    end
    local width = math.min(120, math.max(60, math.floor(vim.o.columns * 0.6)))
    local height = math.min(20, #lines)
    local surf = viewer.open({
      lines = lines,
      title = ("[peek] %s:%d — 'o' open in split, 'q' close"):format(
        fn.fnamemodify(fname, ":."),
        srow
      ),
      width = width,
      height = height,
    })
    if not surf then
      return
    end
    -- map 'o' in preview to open actual location in vsplit
    -- ...use the correct module path here to call the internal helper.
    api.nvim_buf_set_keymap(
      surf.bufnr,
      "n",
      "o",
      ("<cmd>lua require('lsp.tools.ts_type_lookup.cmds')._open_loc_in_split(%q,%d)<CR>"):format(
        fname,
        srow
      ),
      { nowait = true, noremap = true, silent = true }
    )
  end)
end

--- Internal helper used by preview mapping
---@param fname string
---@param line number
function M._open_loc_in_split(fname, line)
  open_in_vsplit(fname, line)
end

--- Fallback: ripgrep in node_modules; opens first match in vsplit
---@param symbol string|nil
function M.find_in_node_modules(symbol)
  symbol = symbol or fn.expand("<cword>")
  local cwd = get_root()
  local node_dir = cwd .. "/node_modules"
  if fn.isdirectory(node_dir) == 0 then
    notify.warn("No node_modules in project root: " .. cwd)
    return
  end
  if fn.executable("rg") == 1 then
    local cmd = { "rg", "--no-ignore", "-n", "--hidden", "-S", symbol, node_dir }
    -- Run ripgrep and collect lines
    local result = fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 or vim.tbl_isempty(result) then
      notify.info("No results for '" .. symbol .. "' in node_modules")
      return
    end
    local first = result[1]

    -- Robust parsing:
    -- Reason:
    --  * On Windows absolute paths contain ":" (e.g., "C:\path\to\file.ts"), so naive patterns
    --    that stop at the first ":" will fail and only capture "C".
    --  * rg output format is typically "path:line:col:match" or "path:line:match".
    -- Approach:
    --  * Split on ":" and treat the last two fields as line and possibly column.
    --  * Reconstruct path from the remaining leading fields. This preserves colons inside paths.
    local parts = vim.split(first, ":", { plain = true })
    local path, lnum

    if #parts >= 3 then
      -- Most common case: path:line:col:...  -> line is at index #parts-2
      -- Or: path:line:match -> line is at index #parts-1 (but column absent)
      -- We prioritize extracting the line number from #parts-2 if it is numeric,
      -- otherwise from #parts-1.
      local maybe_line = tonumber(parts[#parts - 2])
      if maybe_line then
        lnum = maybe_line
        path = table.concat(parts, ":", 1, #parts - 2)
      else
        local maybe_line2 = tonumber(parts[#parts - 1])
        if maybe_line2 then
          lnum = maybe_line2
          path = table.concat(parts, ":", 1, #parts - 1)
        end
      end
    elseif #parts == 2 then
      -- Simple case: path:line
      path = parts[1]
      lnum = tonumber(parts[2])
    end

    if not path or not lnum then
      -- Last-resort fallback: try a greedy Lua pattern that captures everything before the last ":<digits>:" or last ":<digits>"
      local p, ln = first:match("^(.*):(%d+):") -- greedy capture should handle drive-colon paths
      if not p then
        p, ln = first:match("^(.*):(%d+)$")
      end
      if p and ln then
        path = p
        lnum = tonumber(ln)
      end
    end

    if not path then
      notify.error("Could not parse rg result: " .. first)
      return
    end

    local safe_lnum = tonumber(lnum)
    if safe_lnum ~= nil then
      open_in_vsplit(path, safe_lnum)
    else
      notify.error("Could not parse line number from rg result: " .. first)
    end
  else
    notify.warn("ripgrep (rg) not found; install rg or rely on LSP")
  end
end

--- Setup convenience usercommands with optional argument (default: <cword>)
function M.attach()
  usercmd.create(
    "TypeDefGoTo",
    function(opts)
      local sym = opts.args ~= "" and opts.args or fn.expand("<cword>")
      M.go_to_type_definition_for(sym)
    end,
    { nargs = "?", desc = "Go to type definition for symbol string (vsplit). Defaults to <cword>." }
  )

  usercmd.create("TypeDefPeek", function(opts)
    local sym = opts.args ~= "" and opts.args or fn.expand("<cword>")
    M.peek_type_definition_for(sym)
  end, {
    nargs = "?",
    desc = "Peek type definition for symbol string (floating). Defaults to <cword>.",
  })

  usercmd.create("TypeDefFindInNodeModules", function(opts)
    local sym = opts.args ~= "" and opts.args or fn.expand("<cword>")
    M.find_in_node_modules(sym)
  end, { nargs = "?", desc = "Search symbol in node_modules (rg fallback). Defaults to <cword>." })
end

return M
