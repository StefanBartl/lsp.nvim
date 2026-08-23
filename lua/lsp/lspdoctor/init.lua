---@module 'lsp.lspdoctor'
---@brief Comprehensive LSP diagnostics and health checking system
---@description
--- LSP Doctor provides multiple diagnostic modes for inspecting LSP state:
--- - health: Server health checks (running, configured, errors)
--- - debug: Configuration and registration debugging
--- - quick: Quick overview of current LSP state
--- - deep: Detailed LSP capabilities and configuration
--- - all: Combined output of all modes
---
--- Commands:
---   :LspDoctor          -> all modes combined
---   :LspDoctor health   -> server health check
---   :LspDoctor debug    -> debug configuration issues
---   :LspDoctor quick    -> quick LSP overview
---   :LspDoctor deep     -> detailed LSP inspection
---   :LspDoctor! [mode]  -> open in scratch buffer instead of printing
---
--- Keymaps in scratch buffer:
---   q     -> close buffer
---   y     -> yank entire buffer to clipboard
---   gw    -> write to timestamped file in cache
---   <CR>  -> jump to section under cursor (if applicable)

require("lsp.lspdoctor.@types")

local notify = require("lib.nvim.notify").create("[lspdoctor]")
local map = require("lib.nvim.map")
local composer = require("lib.nvim.usercmd.composer")

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

-- Utils -----------------------------------------------------------------------

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
end

---Run health check
---@param bufnr integer|nil
---@param use_scratch boolean|nil
---@return table results
function M.health(bufnr, use_scratch)
  bufnr = bufnr or 0
  local lines, results = health.check(bufnr)
  render_output(lines, use_scratch or false)
  return results
end

---Run debug info
---@param bufnr integer|nil
---@param use_scratch boolean|nil
---@return table info
function M.debug(bufnr, use_scratch)
  bufnr = bufnr or 0
  local lines, info = debug.info(bufnr)
  render_output(lines, use_scratch or false)
  return info
end

---Run quick inspection
---@param bufnr integer|nil
---@param use_scratch boolean|nil
---@return table report
function M.quick(bufnr, use_scratch)
  bufnr = bufnr or 0
  local lines, report = inspect.quick(bufnr)
  render_output(lines, use_scratch or false)
  return report
end

---Run deep inspection
---@param bufnr integer|nil
---@param use_scratch boolean|nil
---@return table report
function M.deep(bufnr, use_scratch)
  bufnr = bufnr or 0
  local lines, report = inspect.deep(bufnr)
  render_output(lines, use_scratch or false)
  return report
end

---Run all checks combined
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
  table.insert(all_lines, "## Health Check")
  table.insert(all_lines, "")
  vim.list_extend(all_lines, health_lines)
  table.insert(all_lines, "")

  -- Debug info
  local debug_lines, debug_info = debug.info(bufnr)
  table.insert(all_lines, "## Debug Info")
  table.insert(all_lines, "")
  vim.list_extend(all_lines, debug_lines)
  table.insert(all_lines, "")

  -- Deep inspection
  local inspect_lines, inspect_report = inspect.deep(bufnr)
  table.insert(all_lines, "## Detailed Inspection")
  table.insert(all_lines, "")
  vim.list_extend(all_lines, inspect_lines)

  render_output(all_lines, use_scratch or false)

  return {
    health = health_results,
    debug = debug_info,
    inspect = inspect_report,
  }
end

---Enable :LspDoctor user command. `path = {}` is the verb's root route (no
---literal subcommand word, matching the flat `:LspDoctor [mode]` grammar);
---the composer's own enum validation replaces the hand-written "Unknown
---mode" warning.
---@return nil
function M.enable_usercmd()
  composer.verb("LspDoctor", {
    bang = true,
    desc = "[LSP Doctor] Comprehensive LSP diagnostics (add ! for scratch buffer)",
    routes = {
      {
        path = {},
        args = {
          {
            name = "mode",
            type = "STRING",
            enum = { "health", "debug", "quick", "deep", "all" },
            optional = true,
          },
        },
        run = function(ctx)
          local mode = ctx.args.mode or "all"
          local use_scratch = ctx.bang
          if mode == "all" then
            M.all(0, use_scratch)
          elseif mode == "health" then
            M.health(0, use_scratch)
          elseif mode == "debug" then
            M.debug(0, use_scratch)
          elseif mode == "quick" then
            M.quick(0, use_scratch)
          elseif mode == "deep" then
            M.deep(0, use_scratch)
          end
        end,
      },
    },
  })
end

return M
