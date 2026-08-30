---@module 'lsp.lspdoctor'
---@brief Comprehensive LSP diagnostics and health checking system
---@description
--- Six reports, each answering one question. Five observe; `probe` provokes.
---
--- The names say which question, because the previous ones said how much
--- output to expect instead: `quick`/`deep` described volume rather than
--- content -- nothing in "deep" hinted that it is where the capabilities
--- live, which is what one opens it for -- and `health` collided with
--- |:checkhealth-lsp| and `:Lsp health`, which report on the *plugin*, not on
--- this buffer's servers.
---
--- - startup:      Is the server running, and if not, why? Executable found,
---                 attempts made, last error, what to run next.
--- - resolve:      Where does the filetype -> server chain break? Five steps,
---                 from "which servers should this filetype get" down to what
---                 `:Lsp start` would offer.
--- - buffer:       What is going on in this buffer right now? Clients,
---                 diagnostic counts, provider conflicts, offset encodings,
---                 formatter. Lists capped at `list_limit`.
--- - capabilities: What can the servers here actually do? The `buffer` report
---                 uncapped, plus root_dir/workspace folders and the full
---                 capability set per client.
--- - probe:        Do diagnostics actually arrive? The only report that
---                 provokes rather than observes: a buffer of deliberately
---                 broken content, handed to the clients on this buffer.
--- - all:          The four observing reports. Not `probe` -- see below.
---
--- Commands:
---   :LspDoctor               -> the four observing reports combined
---   :LspDoctor startup       -> why a server is (not) running
---   :LspDoctor resolve       -> filetype to server resolution chain
---   :LspDoctor buffer        -> what is going on in this buffer
---   :LspDoctor capabilities  -> per-client capabilities and workspace
---   :LspDoctor probe         -> whether diagnostics come back at all
---   :LspDoctor! [mode]       -> open in scratch buffer instead of printing
---
--- `probe` stays out of `all` on purpose. The other four read state and are
--- instant; `probe` creates a buffer, talks to the servers and waits up to
--- `probe_timeout` for an answer. Folding it in would make the default
--- `:LspDoctor` -- the one people reach for first -- slow and side-effectful
--- for the sake of a question they did not ask.
---
--- The old names (`health`, `debug`, `quick`, `deep`) still work, as command
--- arguments and as functions -- renaming a command someone has in a mapping
--- is not worth a broken mapping. They are not offered in completion.
---
--- Keymaps in scratch buffer:
---   q     -> close buffer
---   y     -> yank entire buffer to clipboard
---   gw    -> write to timestamped file in cache
---   ?     -> show this keymap cheatsheet

require("lsp.lspdoctor.@types")

local notify = require("lib.nvim.notify").create("[lspdoctor]")
local map = require("lib.nvim.bindings.keymap")
local composer = require("lib.nvim.bindings.usercmd.composer")
local argtypes = require("lib.nvim.bindings.usercmd.composer.argtypes")
local kit = require("lib.nvim.ui.kit")

local M = {}

local api = vim.api
local fn = vim.fn

-- Configuration ---------------------------------------------------------------

local Defaults = {
  use_notify = false,
  list_limit = 10,
  show_capabilities = true,
  show_workspace = true,
  show_tools = true,
  show_conflicts = true,
  formatter_priority = {},
  semantic_tokens_timeout = 300,
  probe_timeout = 5000,
  scratch_filetype = "markdown",
  auto_open_scratch = false, -- open scratch buffer automatically for long output
  scratch_threshold = 20, -- lines before auto-opening scratch
}

---@type Lsp.Doctor.Options
local Opts = vim.deepcopy(Defaults)

-- Submodules ------------------------------------------------------------------

local health = require("lsp.lspdoctor.health")
local debug = require("lsp.lspdoctor.debug")
local inspect = require("lsp.lspdoctor.inspect")
local probe = require("lsp.lspdoctor.probe")

-- Utils -----------------------------------------------------------------------

local SCRATCH_KEYMAPS = {
  { keys = { "q" }, desc = "Close buffer" },
  { keys = { "y" }, desc = "Yank entire buffer to clipboard" },
  { keys = { "gw" }, desc = "Write report to a timestamped file in cache" },
  { keys = { "?" }, desc = "Show this keymap cheatsheet" },
}

---@internal
---Read-only cheatsheet of every key bound on the LSP Doctor scratch buffer.
---@return nil
local function show_help()
  local widest = 0
  for _, entry in ipairs(SCRATCH_KEYMAPS) do
    widest = math.max(widest, #table.concat(entry.keys, ", "))
  end

  local lines = { "", " LSP Doctor Report keys", "" }
  local function row(lhs, desc)
    lines[#lines + 1] = ("  %-" .. widest .. "s   %s"):format(lhs, desc)
  end
  for _, entry in ipairs(SCRATCH_KEYMAPS) do
    row(table.concat(entry.keys, ", "), entry.desc)
  end
  lines[#lines + 1] = ""

  local width = 40
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  kit.viewer({
    lines = lines,
    title = "LSP Doctor Keys",
    filetype = "lsp-doctor-help",
    width = math.min(width + 2, math.floor(vim.o.columns * 0.9)),
    height = math.min(#lines, math.floor(vim.o.lines * 0.8)),
  })
end

---@param lines string[]
---@return integer bufnr
local function render_to_scratch(lines)
  vim.cmd("botright new")
  local scratch = api.nvim_get_current_buf()
  api.nvim_buf_set_name(scratch, "LSP Doctor Report")
  api.nvim_set_option_value("buftype", "nofile", { buf = scratch })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = scratch })
  api.nvim_set_option_value("swapfile", false, { buf = scratch })
  api.nvim_set_option_value("modifiable", true, { buf = scratch })
  api.nvim_set_option_value("filetype", Opts.scratch_filetype, { buf = scratch })

  api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = scratch })

  -- Buffer-local keymaps
  local opts = { nowait = true, noremap = true, silent = true, buffer = scratch }
  map("n", "q", "<cmd>bd!<CR>", opts)
  map("n", "y", "ggyG", opts)
  map("n", "gw", function()
    local path = fn.stdpath("cache") .. "/lspdoctor_" .. os.date("%Y%m%d_%H%M%S") .. ".md"
    api.nvim_command("silent keepalt keepjumps write! " .. fn.fnameescape(path))
    notify.info("Wrote report to: " .. path)
  end, opts)
  map("n", "?", show_help, opts)

  return scratch
end

---@param lines string[]
---@param use_scratch boolean
---@return nil
local function render_output(lines, use_scratch)
  -- Auto-open scratch if output is long
  if use_scratch or (Opts.auto_open_scratch and #lines > Opts.scratch_threshold) then
    render_to_scratch(lines)
    return
  end

  -- Otherwise print/notify
  local text = table.concat(lines, "\n")
  if Opts.use_notify then
    notify.info(text)
  else
    print(text)
  end
end

-- Public API ------------------------------------------------------------------

---Configure LSP Doctor behavior
---@param opts Lsp.Doctor.Options|nil
---@return nil
function M.setup(opts)
  if opts ~= nil then
    for k, v in pairs(opts) do
      if Defaults[k] ~= nil then
        Opts[k] = v
      end
    end
  end

  -- Pass options to submodules
  health.setup(Opts)
  inspect.setup(Opts)
  probe.setup(Opts)
end

---Why a server is, or is not, running for this buffer.
---@param bufnr integer|nil
---@param use_scratch boolean|nil
---@return table results
function M.startup(bufnr, use_scratch)
  bufnr = bufnr or 0
  local lines, results = health.check(bufnr)
  render_output(lines, use_scratch or false)
  return results
end

---Where the filetype to server resolution chain breaks.
---@param bufnr integer|nil
---@param use_scratch boolean|nil
---@return table info
function M.resolve(bufnr, use_scratch)
  bufnr = bufnr or 0
  local lines, info = debug.info(bufnr)
  render_output(lines, use_scratch or false)
  return info
end

---What is going on in this buffer right now.
---@param bufnr integer|nil
---@param use_scratch boolean|nil
---@return table report
function M.buffer(bufnr, use_scratch)
  bufnr = bufnr or 0
  local lines, report = inspect.buffer(bufnr)
  render_output(lines, use_scratch or false)
  return report
end

---What the servers attached here can actually do, plus their workspaces.
---@param bufnr integer|nil
---@param use_scratch boolean|nil
---@return table report
function M.capabilities(bufnr, use_scratch)
  bufnr = bufnr or 0
  local lines, report = inspect.capabilities(bufnr)
  render_output(lines, use_scratch or false)
  return report
end

---Whether diagnostics actually arrive, proven rather than assumed.
---
---Unlike the other reports this one has side effects and takes time: it builds
---a buffer of broken content, attaches this buffer's clients to it, and waits
---up to `probe_timeout` for something to come back. See `lsp.lspdoctor.probe`.
---@param bufnr integer|nil
---@param use_scratch boolean|nil
---@return table report
function M.probe(bufnr, use_scratch)
  bufnr = bufnr or 0
  local lines, report = probe.run(bufnr)
  render_output(lines, use_scratch or false)
  return report
end

--- The names these reports used to have, mapped to the ones they have now.
---
--- Kept because a rename that breaks a mapping someone already made is a worse
--- outcome than a name that reads badly. They resolve at the call site, so
--- `require("lsp.lspdoctor").deep(0)` and `:LspDoctor deep` both keep working;
--- they are simply not offered in completion, so nobody learns them anew.
--- The reports, in the order one reaches for them when something is wrong.
---@type string[]
M.MODES = { "startup", "resolve", "buffer", "capabilities", "probe", "all" }

---@type table<string, string>
M.LEGACY_MODES = {
  health = "startup",
  debug = "resolve",
  quick = "buffer",
  deep = "capabilities",
}

for legacy, current in pairs(M.LEGACY_MODES) do
  M[legacy] = function(bufnr, use_scratch)
    return M[current](bufnr, use_scratch)
  end
end

---Run the four observing reports combined.
---
---`probe` is deliberately not among them: it is the one report that acts on
---the session instead of reading it, and `:LspDoctor` with no argument should
---stay instant and harmless.
---@param bufnr integer|nil
---@param use_scratch boolean|nil
---@return table combined
function M.all(bufnr, use_scratch)
  bufnr = bufnr or 0

  local all_lines = {
    "# LSP Doctor - Complete Report",
    "Generated: " .. os.date("%Y-%m-%d %H:%M:%S"),
    "",
  }

  -- Health check
  local health_lines, health_results = health.check(bufnr)
  table.insert(all_lines, "## Startup")
  table.insert(all_lines, "")
  vim.list_extend(all_lines, health_lines)
  table.insert(all_lines, "")

  -- Debug info
  local debug_lines, debug_info = debug.info(bufnr)
  table.insert(all_lines, "## Resolve")
  table.insert(all_lines, "")
  vim.list_extend(all_lines, debug_lines)
  table.insert(all_lines, "")

  -- Buffer and capabilities
  local inspect_lines, inspect_report = inspect.capabilities(bufnr)
  table.insert(all_lines, "## Buffer and capabilities")
  table.insert(all_lines, "")
  vim.list_extend(all_lines, inspect_lines)

  render_output(all_lines, use_scratch or false)

  return {
    startup = health_results,
    resolve = debug_info,
    capabilities = inspect_report,
  }
end

---Enable :LspDoctor user command. `path = {}` is the verb's root route (no
---literal subcommand word, matching the flat `:LspDoctor [mode]` grammar);
---the composer's own enum validation replaces the hand-written "Unknown
---mode" warning.
---@return nil
--- Argument type for a report name.
---
--- It exists because an `enum` is both the accepted set *and* the offered set,
--- and here those have to differ: the four current names are what should be
--- discoverable, the four legacy ones have to keep working without being
--- taught to anyone new. The composer rejects an off-enum value before `run`
--- is ever reached, so "accepted but not offered" is not something an enum can
--- express -- verified, not assumed.
---
--- Same mechanism `lsp.bindings.usrcmds` uses for `LSP_SERVER`, and registered
--- under a name only this plugin uses, because `argtypes.register` is a shared
--- registry.
--- Registered from two places: here, and `lsp.bindings.usrcmds`, which needs
--- the type to exist when it composes `:Lsp doctor` -- and the bindings layer
--- is set up before the bootstrap reaches this module. Registering twice is
--- harmless (same spec, last one wins); not registering before the compose
--- would make the composer refuse the whole `:Lsp` verb.
---@return nil
function M.register_mode_argtype()
  argtypes.register("LSP_DOCTOR_MODE", {
    validate = function(raw)
      local canonical = M.LEGACY_MODES[raw] or raw
      if canonical == "all" or type(M[canonical]) == "function" then
        return true, canonical, nil
      end
      return false, nil, ("unknown report %q -- try %s"):format(raw, table.concat(M.MODES, ", "))
    end,
    complete = function(arg_lead)
      return argtypes.prefix(M.MODES, arg_lead)
    end,
  })
end

function M.enable_usercmd()
  M.register_mode_argtype()
  composer.verb("LspDoctor", {
    bang = true,
    desc = "[LSP Doctor] Comprehensive LSP diagnostics (add ! for scratch buffer)",
    routes = {
      {
        path = {},
        args = {
          {
            name = "mode",
            type = "LSP_DOCTOR_MODE",
            optional = true,
          },
        },
        run = function(ctx)
          local mode = M.LEGACY_MODES[ctx.args.mode] or ctx.args.mode or "all"
          local use_scratch = ctx.bang
          local run = M[mode]
          if type(run) == "function" then
            run(0, use_scratch)
          end
        end,
      },
    },
  })
end

return M
