---@module 'lsp.config.project'
---@brief Per-project configuration file: find it, read it, and refuse the
--- parts a repository has no business setting.
---@description
--- The layer that answers "switch `ts_ls` off in *this* checkout without
--- touching my global config". A `.nvim-lsp.json` anywhere at or above the
--- working directory is merged over everything else -- see `lsp.config` for the
--- full precedence.
---
--- Three decisions shape this module.
---
--- **JSON, not Lua.** A project file is data written by whoever wrote the
--- repository, and Neovim reads it because you opened a directory. Lua would
--- make cloning a repository enough to run its code. JSON cannot express a
--- function, so there is nothing to execute -- the format *is* the boundary.
---
--- **An allowlist, not a filter.** `ALLOWED` names the keys a project may set,
--- and everything else is dropped with a warning. The line is not "what could
--- break" but *whose question is this*: `servers`, `formatter` and
--- `attach` describe the codebase, so a repository may answer them. Keymaps,
--- `:Lsp` registration and `mason.ensure_install` describe you and your
--- machine -- a repository does not get to move your keys or install packages.
---
--- **Read once, at `setup()`.** Nearly every option here is consumed while the
--- plugin bootstraps: servers are enabled, tools are set up, commands are
--- registered. Re-reading the file after a `:cd` would produce a config that no
--- longer matches what is running, which is worse than not re-reading it. The
--- file that counts is the one above the directory Neovim started in, and
--- `:checkhealth lsp` names it so that is never a guess.
---
---@see lsp.config
---@see lsp.config.DEFAULTS

local M = {}

--- Keys a project file may set. Everything else is dropped with a warning.
---
--- Deliberately short. A key belongs here when the *repository* is the thing
--- that knows the answer:
---
--- * `servers`      -- which languages this codebase is written in.
--- * `diagnostics`  -- how noisy this codebase is while you type.
--- * `formatter`    -- whether writing a file here should format it.
--- * `inlay_hints`  -- worth having in a typed repo, noise in a dynamic one.
--- * `lightbulb`    -- how generous this stack's servers are with code
---                     actions, which is what decides whether the indicator
---                     carries information or is simply always lit.
--- * `attach`       -- whether a workspace-wide scan is affordable here.
--- * `workspace`    -- what counts as a project root inside this tree.
--- * `tools`        -- which extra tools this stack benefits from.
--- * `languages`    -- the per-filetype setup this tree wants.
---
--- The omissions are the point, so they are named rather than left implicit:
---
--- * `preset`                -- a property of the machine, not the repository.
--- * `keymaps`, `usrcmds`,
---   `which_key`, `menu`     -- your bindings. Opening a repository must not
---                              move a key or drop a command.
--- * `mason`                 -- installs software. Never from a checkout.
--- * `completion`, `rename`  -- host data and a personal habit; neither is a
---                              property of the code being edited.
--- * `lspdoctor`             -- report formatting, which is yours to choose.
--- * `project`               -- a project file pointing at another project
---                              file is a loop with nothing to gain.
---@type table<string, true>
M.ALLOWED = {
  servers = true,
  diagnostics = true,
  formatter = true,
  inlay_hints = true,
  lightbulb = true,
  attach = true,
  workspace = true,
  tools = true,
  languages = true,
}

--- Locate the nearest project file at or above a directory.
---@param name string # File name to look for, e.g. `".nvim-lsp.json"`.
---@param start string|nil # Directory to start the upward walk at; cwd by default.
---@return string|nil path # Absolute path, or nil when there is none.
function M.find(name, start)
  start = start or vim.uv.cwd() or vim.fn.getcwd()
  local found = vim.fs.find(name, { upward = true, path = start, type = "file", limit = 1 })
  return found[1]
end

---@internal
--- Shorten a path for a warning or a health line: relative to the cwd when it
--- is below it (the usual case -- you started Neovim in the project), relative
--- to `$HOME` otherwise.
---@param path string
---@return string
local function display(path)
  local short = vim.fn.fnamemodify(path, ":~:.")
  return short ~= "" and short or path
end

---@internal
--- Read and decode the file. Every failure is a warning, never an error: a
--- broken project file must cost the override, not the startup.
---@param path string
---@param label string # Short path, for the warnings.
---@return table|nil data
---@return string[] warnings
local function decode(path, label)
  local ok, content = pcall(vim.fn.readfile, path)
  if not ok or type(content) ~= "table" then
    return nil, { ("%s: cannot be read, ignoring"):format(label) }
  end

  local text = table.concat(content, "\n")
  if text:match("^%s*$") then
    -- An empty file is a plausible placeholder ("I will fill this in"), not a
    -- mistake worth reporting.
    return nil, {}
  end

  -- `luanil` turns JSON `null` into an absent key instead of `vim.NIL`. In a
  -- config file `null` reads as "no opinion", and letting `vim.NIL` through
  -- would put a sentinel userdata where every consumer expects a value.
  local decoded
  ok, decoded = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
  if not ok then
    return nil, { ("%s: invalid JSON (%s), ignoring"):format(label, tostring(decoded)) }
  end
  if type(decoded) ~= "table" or vim.islist(decoded) then
    return nil, { ("%s: expected a JSON object, ignoring"):format(label) }
  end

  return decoded, {}
end

--- Find, read and filter the project file.
---
--- Returns `nil` when there is nothing to merge -- no file, an unreadable or
--- malformed one, or one whose every key was refused. Callers treat all four
--- the same; the warnings say which it was.
---@param opts LspNvim.ProjectOpts # Resolved `project` options (enable, file).
---@param start string|nil # Directory to start the upward walk at; cwd by default.
---@return { path: string, label: string, data: table }|nil layer
---@return string[] warnings
function M.read(opts, start)
  if not opts.enable then
    return nil, {}
  end

  local path = M.find(opts.file, start)
  if path == nil then
    return nil, {}
  end

  local label = display(path)
  local data, warnings = decode(path, label)
  if data == nil then
    return nil, warnings
  end

  ---@type table
  local clean = {}
  ---@type string[]
  local refused = {}
  for key, value in pairs(data) do
    if M.ALLOWED[key] then
      clean[key] = value
    else
      refused[#refused + 1] = tostring(key)
    end
  end

  if #refused > 0 then
    table.sort(refused)
    local allowed = vim.tbl_keys(M.ALLOWED)
    table.sort(allowed)
    -- One line for all of them: a file that sets five refused keys has one
    -- mistaken idea about this feature, not five separate problems.
    warnings[#warnings + 1] = ("%s: %s cannot be set from a project file, ignoring (allowed: %s)"):format(
      label,
      table.concat(refused, ", "),
      table.concat(allowed, ", ")
    )
  end

  if next(clean) == nil then
    return nil, warnings
  end

  return { path = path, label = label, data = clean }, warnings
end

return M
