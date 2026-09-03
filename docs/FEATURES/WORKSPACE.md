# Root resolution and workspace folders

Two mechanisms under one word, because from where you sit both answer "what
does this server consider my project".

The **root scope** is a global switch between the working directory, the git
root and the file's own path. It decides *how* a root is found, and it reaches
the servers whose `root_dir` is a function -- `lua_ls` and `marksman` here.
lua_ls additionally treats the Neovim config directory as a root of its own,
which is what its workspace library needs.

**Workspace folders** are LSP's own multi-root mechanism: a running client
holds a list of them and accepts `workspace/didChangeWorkspaceFolders` to grow
or shrink it. That reaches *every* server that says it supports the
notification, including the `root_markers` ones the scope switch cannot touch,
and it takes effect without a restart. `:Lsp root add` offers the projects
around the current buffer -- upward through its parents, then one level sideways
through container directories like `packages/`, which is where a monorepo's
sibling package lives and where an upward walk never looks.

Only clients that declare both `workspaceFolders.supported` and
`changeNotifications` are sent anything; the rest are listed as skipped, with
the reason, rather than notified into the void.

- **Module:** `core/root_scope.lua`, `core/workspace_folders.lua`,
  `core/workspace_picker.lua`, `servers/*/rootresolver.lua`
- **Commands:** `:Lsp root [pick|show|add|remove|list]`
- **Keymaps:** `<leader>lsp` (scope), `<leader>lsw` (add a workspace folder)
- **Config:** `workspace.markers`, `workspace.containers`
