-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "lsp",
  -- Where the specs live (relative to this directory).
  roots = { "TESTS/lsp", "TESTS" },
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own
  -- TESTS/harness.lua, "script" = a self-running script in its own process.
  dialect = {
    ["*"] = "auto",
    ["TESTS/smoke.lua"] = "script",
  },
  -- Lua patterns a file name must match to be a spec (the old runner started these files by name).
  spec_pattern = { "_spec%.lua$", "^TESTS/smoke%.lua$" },
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim", "ui.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next).
  isolated = "file",
  -- "c" = child started from a -c command (v:vim_did_enter is 0, <cword> works),
  -- "l" = `nvim -l`.
  host = "c",
  -- Two cases assert nothing (capabilities_spec.lua:32 "does not cry wolf when no engine contributed",
  -- diagnostics_severity_spec.lua:16 "treats nil and empty as 'all severities'"); the old runner passed them.
  -- Remove this line once they assert something.
  assertions = "warn",
  -- servers_languages_spec.lua "stops collecting at max_files" writes 600 files and waits for the
  -- word-cache scan (vim.wait up to 30 s); on the Windows CI runner that exceeds the default 10 s.
  timeouts = { case_ms = 30000 },
  -- Safety nets (docs/GUARDS.md of testing.nvim). The suite passes fs, scheduled_error, prompt,
  -- deprecation and process_net cleanly, so they are errors; only the state guard keeps findings.
  guards = {
    fs = "error",
    scheduled_error = "error",
    prompt = "error",
    deprecation = "error",
    -- Real processes are started on purpose (see guard_allow.spawn); anything else is an error.
    process_net = "error",
    -- warn, not off: the package.preload, env and lua_globals leaks the guard found are fixed. The
    -- ~1550 remaining warnings are plugin setup() state (autocmds, user commands, keymaps, buffers,
    -- windows, highlight groups, vim.g._lsp_enabled_* of vim.lsp.enable()) that the specs create by
    -- design; `isolated = "file"` contains it per spec file. A per-category switch is not available
    -- in .testing.lua (only a mode string per guard), so that noise cannot be filtered out here.
    state = "warn",
  },
  guard_allow = {
    spawn = {
      -- probe_live_spec.lua starts whichever real language server is installed (lua_ls locally; CI
      -- installs ts_ls) on deliberately broken content; `npm root -g` locates the global typescript.
      "lua-language-server",
      "typescript-language-server",
      "gopls",
      "npm",
      -- usercmds_impl_spec.lua registers fake servers with cmd = { "true" }: a no-op executable that
      -- vim.lsp.start() launches so that :Lsp start/restart/info have a running client to count.
      "true",
    },
  },
  -- The runner counts which commands, keymaps and autocommands the specs exercise (docs/SURFACE.md of testing.nvim);
  -- `scripts/test.sh surface` compares that with surface.baseline.json (a regression gate, not a percentage).
  surface = { track = true },
  -- Findings the minimal conformance editor cannot avoid (docs/CONFORMANCE.md of testing.nvim); reviewed 2026-10-14.
  conformance = {
    -- gated: a failed check makes `scripts/test.sh conformance` exit 1
    gate = true,
    waivers = {
      {
        check = "K1",
        file = "lua/lsp/init.lua",
        reason = "the only autocmds are Neovim's own: loading vim.lsp (which lsp, lsp.languages.app.java and lsp.servers.webdev.emmet_ls all touch) creates its exit handler and the diagnostic status autocmd; lsp.nvim registers none at require time",
        expires = "2027-04-14",
      },
      {
        check = "K1",
        file = "lua/lsp/tools/ts_type_lookup/noice_integration.lua",
        reason = "entry module of the optional Noice integration: its only job is to install the BufWinEnter keymap hook and :TypeDefAttachNoiceKeys; it is required from ts_type_lookup.setup() and nowhere else",
        expires = "2027-04-14",
      },
      {
        check = "K5",
        level = "warn",
        text = ":AstroNew",
        reason = "the argument is a new file name chosen by the user (free text), nothing to complete",
        expires = "2027-04-14",
      },
      {
        check = "K5",
        level = "warn",
        text = ":TypeDef",
        reason = "the argument is a symbol name or workspace-symbol query typed by the user (free text, defaults to <cword>); there is no closed set to complete",
        expires = "2027-04-14",
      },
      {
        check = "K6",
        level = "warn",
        text = "which is not installed",
        reason = "trouble.nvim and fzf-lua are optional integrations that the minimal conformance editor does not have; the health check reports the keymaps that stay unbound without them, which is correct",
        expires = "2027-04-14",
      },
      {
        check = "K6",
        level = "warn",
        text = "Unknown filetype 'ksh'",
        reason = "bashls lists the filetype 'ksh' on purpose (its globPattern covers .ksh/.mksh); Neovim's known-filetype table of this version has no 'ksh', which only makes vim.lsp health hint at it",
        expires = "2027-04-14",
      },
      {
        check = "K12",
        level = "warn",
        text = "LSP.picker_",
        reason = "the lsc/lsf pickers (incoming calls, finder) are cursor-context UIs over fzf-lua/quickfix with no useful :command form; the :Lsp commands do not duplicate them",
        expires = "2027-04-14",
      },
      {
        check = "K12",
        level = "warn",
        text = "LSP.trouble_outline",
        reason = "opens Trouble's symbols sidebar (a toggle, requires trouble.nvim); the toggle is the whole action and Trouble has its own :Trouble symbols command",
        expires = "2027-04-14",
      },
      {
        check = "K6",
        level = "error",
        text = "conform.nvim",
        reason = "conform.nvim is an external plugin the health check requires; the minimal conformance editor has no third-party plugins",
        expires = "2027-04-14",
      },
    },
  },
}
