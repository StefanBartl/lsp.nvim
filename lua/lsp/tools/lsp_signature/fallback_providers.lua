---@module 'lsp.tools.lsp_signature.fallback_providers'
--- Query alternative LSP providers when signatureHelp and hover return nothing.
--- Tries a sequence of LSP methods (typeDefinition, implementation, references)
--- and formats the first non-empty result into a list of lines suitable for
--- `open_floating_preview`. The preview will receive a `footer` (shortened path)
--- so the UI can show the origin centered at the bottom.
---
--- API:
---   M.try_providers(clients, params, opts)
--- opts:
---   - mode: string|nil  -- passed to open_floating_preview / callbacks
---   - callback: fun(buf,win)|nil
---   - providers: string[]|nil  -- override default provider list
local notify = require("lib.nvim.notify").create("[lsp.tools.lsp_signature.fallback_providers]")

local M = {}

local open_floating_preview = require("lsp.tools.lsp_signature.open_floating_preview")
local state = require("lsp.tools.lsp_signature.state")
local helper = require("lsp.tools.lsp_signature.utils.helper")
local api = vim.api
local schedule = vim.schedule
local uri_to_fname = vim.uri_to_fname

--- Provider list in preferred order. Can be adjusted.
local DEFAULT_PROVIDERS = {
  "textDocument/typeDefinition",
  "textDocument/implementation",
  "textDocument/references",
}

-- Helper: obtain a short preview snippet from a file/uri at a 0-based line index.
--- @param uri_or_fname string
--- @param lnum0 integer
--- @return string
local function get_line_preview(uri_or_fname, lnum0)
  local fname = uri_or_fname or ""
  -- if it looks like a URI, convert
  if fname:match("^%a[%w+.-]*://") then
    fname = uri_to_fname(fname)
  end

  -- try to read the buffer for that file, or load file contents temporarily
  local ok, lines
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(bufnr) then
      local bufname = api.nvim_buf_get_name(bufnr)
      if bufname ~= "" and bufname == fname then
        ok = true
        lines = api.nvim_buf_get_lines(bufnr, lnum0, lnum0 + 1, false)
        break
      end
    end
  end

  if not ok then
    local f_ok, f = pcall(io.open, fname, "r")
    if f_ok and f then
      local skip = 0
      local content_line
      for line in f:lines() do
        if skip == lnum0 then
          content_line = line
          break
        end
        skip = skip + 1
      end
      f:close()
      if content_line then
        lines = { content_line }
      end
    end
  end

  local snippet = ""
  if type(lines) == "table" and lines[1] then
    snippet = lines[1]:gsub("^%s+", ""):gsub("%s+$", "")
    if #snippet > 140 then
      snippet = snippet:sub(1, 137) .. "..."
    end
  end
  return snippet
end

-- Helper: normalize Location, LocationLink, or array into a flat list of {uri, lnum0, col0, name?}
--- @param result any
--- @return table[] list
local function flatten_locations(result)
  local out = {}
  if not result then
    return out
  end

  local function push_loc(uri, range, name)
    local s = range and range.start
    if s then
      table.insert(out, { uri = uri, lnum = (s.line or 0), col = (s.character or 0), name = name })
    end
  end

  local function handle_item(item)
    if item == nil then
      return
    end
    -- LocationLink has targetUri and targetRange / targetSelectionRange
    if item.targetUri and item.targetRange then
      push_loc(
        item.targetUri,
        item.targetRange,
        (item.targetSelectionRange and item.targetSelectionRange) or nil
      )
    elseif item.uri and item.range then
      push_loc(item.uri, item.range, nil)
    elseif type(item) == "string" then
      -- if server returned string (rare), just add as name-only
      table.insert(out, { uri = nil, lnum = 0, col = 0, name = item })
    end
  end

  if vim.islist(result) then
    for _, item in ipairs(result) do
      handle_item(item)
    end
  else
    handle_item(result)
  end

  return out
end

-- Formats one location entry into a displayable main line and a display_path footer.
-- Returns: main_line (string), display_path (string)
--- @param entry table
--- @return string|nil, string|nil, string|nil, number|nil, number|nil
local function format_location_line_for_preview(entry)
  if not entry then
    return nil, nil, nil, nil, nil
  end

  local uri = entry.uri or ""
  local fname = uri ~= "" and vim.uri_to_fname(uri) or "[unknown]"
  local display_path = helper.shorten_display_path(fname)

  local lnum = (entry.lnum or 0) + 1
  local col = (entry.col or 0) + 1
  local snippet = get_line_preview(uri or fname, entry.lnum or 0)
  local name = entry.name and tostring(entry.name) or ""

  -- Prefer to show the actual snippet (code/signature) as the main line.
  -- Fallback to symbol name or a compact "line X, col Y" notation when snippet missing.
  local main = nil
  if snippet and snippet ~= "" then
    main = snippet
  elseif name ~= "" then
    main = name
  else
    main = string.format("line %d, col %d", lnum, col)
  end

  -- append a small suffix (symbol name) if available and not redundant
  if name ~= "" and (not main:find(name, 1, true)) then
    main = main .. "  –  " .. name
  end

  return main, display_path, fname, lnum, col
end

--- Try providers for a single client sequentially. On first non-empty result,
--- open floating preview and invoke callback(buf,win).
--- @param client table
--- @param params table
--- @param providers string[] list of LSP method names
--- @param opts table|nil
local function try_client_providers(client, params, providers, opts)
  opts = opts or {}
  local mode = opts.mode
  local callback = opts.callback

  local i = 1
  local function next_provider()
    local method = providers[i]
    if not method then
      -- exhausted providers for this client
      return
    end
    i = i + 1

    local handler = function(_, result)
      local locs = flatten_locations(result)
      if locs and #locs > 0 then
        local lines = {}
        local footer = nil
        local first_fname, first_lnum, first_col = nil, nil, nil

        for _, entry in ipairs(locs) do
          local main, dp, full_fname, lnum, col = format_location_line_for_preview(entry)
          if main then
            table.insert(lines, main)
            if not footer and dp then
              footer = dp
            end
            if not first_fname and full_fname then
              first_fname = full_fname
              first_lnum = lnum
              first_col = col
            end
          end
        end

        schedule(function()
          -- build title as "path:line:col" (compact display_path plus numeric position)
          local title = footer or ""
          if first_fname and first_lnum and first_col then
            title = string.format(
              "%s:%d:%d",
              footer or helper.shorten_display_path(first_fname),
              first_lnum,
              first_col
            )
          end

          -- pass orig file/pos so preview can set buffer name / attempt filetype & highlighting
          local buf, win = open_floating_preview(lines, {
            title = title,
            focus = (mode == "n"),
            orig_fname = first_fname,
            orig_line = first_lnum,
            orig_col = first_col,
          })
          if buf and first_fname then
            -- attempt to set bufname so filetype detection can run (helps syntax highlight)
            pcall(api.nvim_buf_set_name, buf, first_fname)
            -- simple extension->filetype hints for common languages (improves highlight chance)
            local ext = first_fname:match("%.([^.]+)$")
            if ext then
              local map = {
                ts = "typescript",
                tsx = "typescriptreact",
                js = "javascript",
                jsx = "javascriptreact",
                lua = "lua",
                py = "python",
                rs = "rust",
                go = "go",
                java = "java",
                cpp = "cpp",
                c = "c",
                h = "c",
                hpp = "cpp",
                sh = "sh",
                zsh = "sh",
                fish = "fish",
                php = "php",
              }
              local ft = map[ext]
              if ft then
                pcall(function()
                  api.nvim_set_option_value("filetype", ft, { buf = buf })
                end)
                -- trigger FileType autocommands if needed
                pcall(function()
                  vim.cmd("doautocmd FileType " .. ft)
                end)
              end
            end
          end

          state.set(buf, win)
          if mode == "n" and win and api.nvim_win_is_valid(win) then
            api.nvim_set_current_win(win)
          end
          if callback and buf and win then
            callback(buf, win)
          end
        end)
        return
      end
      -- nothing found for this provider — try next one
      next_provider()
    end

    -- protect request call
    pcall(function()
      if method == "textDocument/references" then
        local rparams = vim.deepcopy(params)
        rparams.context = rparams.context or {}
        rparams.context.includeDeclaration = true
        pcall(client.request, client, method, rparams, handler, vim.api.nvim_get_current_buf())
      else
        pcall(client.request, client, method, params, handler, vim.api.nvim_get_current_buf())
      end
    end)
  end

  next_provider()
end

--- Public API: try a set of providers across clients.
--- Tries each client in order; for each client it tries providers sequentially until a result.
--- @param clients table[] list of LSP client objects
--- @param params table request params (position params)
--- @param opts table|nil
function M.try_providers(clients, params, opts)
  opts = opts or {}
  local providers = opts.providers or DEFAULT_PROVIDERS
  local callback = opts.callback
  local mode = opts.mode

  if not clients or vim.tbl_isempty(clients) then
    schedule(function()
      notify.info("[signature_help] fallback: no clients available")
    end)
    return
  end

  -- iterate clients one by one; try providers on each until one produces output
  local ci = 1
  local function next_client()
    local client = clients[ci]
    ci = ci + 1
    if not client then
      schedule(function()
        notify.info("[signature_help] fallback: no provider returned results")
      end)
      return
    end

    -- timeout guard per client
    local timer = vim.uv.new_timer()
    if not timer then
      notify.warn("timer is nil")
      return
    end
    local timeout_ms = 800
    timer:start(
      timeout_ms,
      0,
      vim.schedule_wrap(function()
        next_client()
      end)
    )

    -- wrapped callback to cancel timer when preview shown
    local wrapped_cb = function(buf, win)
      if timer and not timer:is_closing() then
        pcall(function()
          timer:stop()
          timer:close()
        end)
      end
      if callback then
        callback(buf, win)
      end
    end

    try_client_providers(client, params, providers, { mode = mode, callback = wrapped_cb })
  end

  next_client()
end

return M
