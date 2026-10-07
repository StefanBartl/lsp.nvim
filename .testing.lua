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
}
