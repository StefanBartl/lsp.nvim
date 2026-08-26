---@module 'lsp.tools.ts_type_lookup.ts_telescope_picker'
--- Telescope picker to show workspace symbols for a query string and open chosen item.
--- Requires 'telescope.nvim' installed. The picker uses workspace/symbol and presents
--- results with filename and kind; selection opens the location in a split.
local notify = require("lib.nvim.notify").create("[lsp.tools.ts_type_lookup.ts_telescope_picker]")

-- Telescope is required lazily inside M.pick, never at module scope. This
-- module is pulled in during LSP setup, so a top-level `require("telescope")`
-- defeated telescope's own `cmd = "Telescope"` lazy-loading and dragged it --
-- plus telescope-github.nvim and pdfport.nvim -- into every startup, ~117ms
-- for a picker nobody has invoked yet. See docs/ROADMAP/PERF-Startup-Analyse.md.
---@return { pickers: table, finders: table, conf: table, previewers: table }|nil
local function telescope_modules()
  local ok = pcall(require, "telescope")
  if not ok then
    notify.warn("telescope.nvim not found")
    return nil
  end
  return {
    pickers = require("telescope.pickers"),
    finders = require("telescope.finders"),
    conf = require("telescope.config").values,
    previewers = require("telescope.previewers"),
  }
end
-- local lsp_util = vim.lsp.util
local lsp = vim.lsp
local api = vim.api
local fn = vim.fn
local usercmd = require("lib.nvim.bindings.usercmd")

local M = {}

--- Convert workspace/symbol result into entry for telescope
---@param item table
---@return table
local function symbol_to_entry(item)
  local name = item.name or item
  -- local kind = item.kind or (item.location and item.location.kind) or ""
  local loc = item.location or item
  local uri = loc.uri or loc.targetUri
  local fname = uri and vim.uri_to_fname(uri) or "[unknown]"
  local range = loc.range or loc.targetSelectionRange or loc.targetRange
  local line = (range and range.start and (range.start.line or 0) + 1) or 1
  local display = string.format("%s — %s:%d", name, fn.fnamemodify(fname, ":."), line)
  local entry_maker = function(entry)
    return {
      value = entry,
      ordinal = display,
      display = display,
      filename = fname,
      lnum = line,
      col = (range and range.start and (range.start.character or 0) + 1) or 1,
    }
  end
  -- return a simple entry compatible with finders.new_table
  return { entry_maker = entry_maker, value = item }
end

--- Launch a telescope picker for the query (defaults to <cword>)
---@param query string|nil
function M.pick(query)
  local ts = telescope_modules()
  if not ts then
    return
  end
  local pickers, finders, conf, previewers = ts.pickers, ts.finders, ts.conf, ts.previewers

  query = query ~= nil and query ~= "" and query or fn.expand("<cword>")
  local bufnr = api.nvim_get_current_buf()
  -- request workspace/symbol from LSP
  lsp.buf_request(bufnr, "workspace/symbol", { query = query }, function(err, result)
    if err then
      notify.warn("workspace/symbol failed: " .. tostring(err))
      return
    end
    if not result or vim.tbl_isempty(result) then
      notify.info("No symbols found for: " .. query)
      return
    end
    local entries = {}
    for _, item in ipairs(result) do
      local e = symbol_to_entry(item)
      table.insert(entries, { item = item, display = e })
    end
    -- create finder using simple table
    local finder = finders.new_table({
      results = result,
      entry_maker = function(entry)
        local loc = entry.location or entry
        local uri = loc.uri or loc.targetUri
        local fname = uri and vim.uri_to_fname(uri) or "[unknown]"
        local range = loc.range or loc.targetSelectionRange or loc.targetRange
        local line = (range and range.start and (range.start.line or 0) + 1) or 1
        local display =
          string.format("%s — %s:%d", entry.name or "<anon>", fn.fnamemodify(fname, ":."), line)
        return {
          value = entry,
          ordinal = display,
          display = display,
          filename = fname,
          lnum = line,
          col = (range and range.start and (range.start.character or 0) + 1) or 1,
        }
      end,
    })

    pickers
      .new({}, {
        prompt_title = "Workspace Symbols: " .. query,
        finder = finder,
        previewer = previewers.new_buffer_previewer({
          define_preview = function(self, entry, _)
            if not entry or not entry.value then
              return
            end
            local fname = entry.filename
            local lnum = entry.lnum
            local ok, content = pcall(fn.readfile, fname)
            if not ok or not content then
              return
            end
            local start_line = math.max(1, lnum - 3)
            local end_line = math.min(#content, lnum + 3)
            vim.api.nvim_buf_set_lines(
              self.state.bufnr,
              0,
              -1,
              false,
              vim.list_slice(content, start_line, end_line)
            )
            pcall(vim.api.nvim_set_option_value, "filetype", vim.bo.filetype, { self.state.bufnr })
          end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
          local actions = require("telescope.actions")
          local action_state = require("telescope.actions.state")
          local open = function()
            local selection = action_state.get_selected_entry()
            if not selection then
              return
            end
            local val = selection.value or selection
            local loc = val.location or val
            local fname = (loc.uri and vim.uri_to_fname(loc.uri))
              or (loc.targetUri and vim.uri_to_fname(loc.targetUri))
            local range = loc.range or loc.targetSelectionRange or loc.targetRange
            local lnum = (range and range.start and (range.start.line or 0) + 1) or 1
            actions.close(prompt_bufnr)
            vim.cmd("vsplit " .. fn.fnameescape(fname))
            vim.cmd(tostring(lnum))
          end
          map("i", "<CR>", open)
          map("n", "<CR>", open)
          return true
        end,
      })
      :find()
  end)
end

--- Setup usercommand to invoke the picker
function M.attach()
  usercmd.create("TypeDefPick", function(opts)
    local sym = opts.args ~= "" and opts.args or fn.expand("<cword>")
    M.pick(sym)
  end, { nargs = "?", desc = "Telescope picker for workspace symbols (default: <cword>)" })
end

return M
