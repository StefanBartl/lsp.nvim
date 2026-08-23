# Installation / integration notes

2) Initialize from your Neovim config (example for init.lua or plugin config):
  require("lps.tools.deprecated_help").setup({
     lua_ls = { keymap = "<leader>lh" }, -- optional: override mapping
   })

3) Behavior summary:
   - Existing LSP diagnostic handler is preserved; the wrapper calls it first.
   - Only diagnostics emitted by the lua_ls LSP and judged as "deprecated" by heuristics
     are processed by the lua-specific module.
   - For each matching diagnostic the plugin:
     * extracts a symbol (from range or message heuristics),
     * calls vim.notify() with an appended hint including the buffer-local keymap,
     * sets a buffer-local mapping (default "<leader>lh") which opens :help <symbol>.
   - Duplicate notifications/mappings for the same symbol in the same buffer are avoided.

4) Extending for additional behaviors:
   - Add new server-specific handlers by creating a module similar to lua_ls.lua
     and calling lsp_common.register_server_callback("server_name", cb).
   - Improve symbol extraction by expanding myplugin.catch (e.g. treesitter fallback).
   - Add alternative actions (open docs URL, jump to source, etc.) in server module.

5) Safety / non-breaking notes:
   - The original publishDiagnostics handler is always invoked; existing behavior remains intact.
   - The wrapper is idempotent; calling myplugin.init.setup() multiple times will not stack handlers.
   - Mappings are buffer-local and created only if not existing to avoid collisions.

---

