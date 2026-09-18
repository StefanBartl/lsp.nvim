---@module 'lsp.languages.app.dart'
--- Dart QoL: 2-space indent on FileType, plus `<leader>fr` to launch
--- `flutter run` in a terminal split.

local M = {}

local api = vim.api
local Autocmd = require("lib.nvim.bindings.autocmd")
local map = require("lib.nvim.bindings.keymap")
local notify = require("lib.nvim.notify").create("[lsp.languages.app.dart]")

--- The terminal buffer `<leader>fr` opened, or nil once it has none.
---@type integer|nil
local run_bufnr = nil

---@internal
--- The Dart project root for `bufnr`, to run `flutter run` from.
---
--- `jobstart()`'s own docs are explicit about the default that makes this
--- necessary: "cwd: (string, default=|current-directory|)" -- Neovim's
--- *global* cwd, not the directory of whichever buffer triggered the
--- keybinding. Nothing here keeps those two in sync (no `autochdir`, no
--- per-window cwd), so a `.dart` file opened from anywhere else -- a file
--- picker, a monorepo checked out above several Flutter apps, an `nvim`
--- launched from `$HOME` -- would run `flutter run` in the wrong directory:
--- best case "Error: No pubspec.yaml file found", worst case a *different*
--- Flutter project that happens to have one, launched by name alone.
---
--- Same markers `dartls.lua` roots the language server on, so "which project"
--- answers the same way for the server and for this command.
---@param bufnr integer
---@return string
local function project_root(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return vim.fn.getcwd()
  end
  return vim.fs.root(bufnr, { "pubspec.yaml", ".git" }) or vim.fs.dirname(name)
end

---@internal
--- Launch `flutter run`, or focus the one already running.
---
--- `vim.cmd("!flutter run --hot-reload")` was both wrong and dangerous:
--- `--hot-reload` is not a real `flutter run` flag -- measured, `flutter run
--- --hot-reload` answers "Could not find an option named '--hot-reload'." and
--- exits immediately, so the keybinding never once did what its own `desc`
--- claimed. Fixing only the flag would not have been enough: `:!` is
--- synchronous, and `flutter run` is not a command that finishes -- it is an
--- interactive dev server that stays up until the app is stopped, so the
--- corrected command would have frozen the whole editor for as long as the
--- app runs, which is the opposite of "hot reload".
---
--- `--hot` is on by default, so nothing needs to ask for it. A real terminal
--- buffer (not a captured job) is what an interactive dev server needs --
--- `flutter run`'s own hot-reload confirmations, build errors and the `r`/`R`/
--- `q` keys it listens for on stdin all depend on it being one.
---@return nil
local function run_or_focus()
  if run_bufnr and api.nvim_buf_is_valid(run_bufnr) then
    for _, win in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_buf(win) == run_bufnr then
        api.nvim_set_current_win(win)
        return
      end
    end
    vim.cmd("botright split")
    api.nvim_win_set_buf(0, run_bufnr)
    return
  end

  -- Resolved from the buffer the press came *from*, before any of the
  -- window/buffer juggling below changes what "current buffer" means.
  local root = project_root(api.nvim_get_current_buf())

  notify.info("Flutter: starting `flutter run` in " .. root)
  vim.cmd("botright split")
  vim.cmd("enew")
  local this_bufnr = api.nvim_get_current_buf()
  run_bufnr = this_bufnr
  vim.fn.jobstart("flutter run", {
    term = true,
    cwd = root,
    on_exit = function()
      -- `on_exit` runs whenever the job ends, regardless of which buffer or
      -- window has focus at that moment -- checking "the current buffer"
      -- would clear the wrong run (or the right run from the wrong check)
      -- depending on where the cursor happens to be. Compared against the
      -- buffer *this* job was started in, captured above, so a second
      -- `<leader>fr` while the first is still up -- which replaces
      -- `run_bufnr` with a new terminal -- does not have the first job's
      -- later exit clear the replacement out from under a still-running
      -- process.
      if run_bufnr == this_bufnr then
        run_bufnr = nil
      end
    end,
  })
end

---@return nil
function M.enable()
  local grp = api.nvim_create_augroup("LangDart", { clear = true })

  Autocmd.create("FileType", function(ev)
    local bufnr = ev.buf

    vim.bo[bufnr].shiftwidth = 2
    vim.bo[bufnr].tabstop = 2
    vim.bo[bufnr].expandtab = true

    map("n", "<leader>fr", run_or_focus, { buffer = bufnr, desc = "Flutter: run (or focus)" })
  end, {
    group = grp,
    pattern = { "dart" },
  })
end

--- Exposed for the spec suite.
---@private
M._run_or_focus = run_or_focus

---@type Lsp.Languages.ConfiguredLangs.Dart.Module
return M
