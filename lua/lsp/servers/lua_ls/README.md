# Lua Language Server (lua_ls) setup for Neovim

These Lua modules configure the Lua Language Server (lua_ls) for Neovim with intelligent root detection, precise workspace library management and optimised performance.

## 📋 Overview

The setup consists of several interconnected modules that provide a robust and performant lua_ls integration:

```
lsp/servers/lua_ls/
├── init.lua              # main module: LSP server configuration
├── rootresolver.lua      # project root detection
├── library_profiles.lua  # the library before_init installs, and the scan profiles
├── build_library.lua     # workspace library construction (debug path only)
├── find_type_dirs.lua    # scanner for type directories
├── ignore.lua            # central ignore configuration
├── error_handler.lua     # guards malformed textDocument requests
├── reload.lua            # :LuaLsReloadLibrary/InspectLibrary/SetProfile, root recomputation
├── debug.lua             # debugging utilities
└── docs/TROUBLESHOOTING.md
```

## 🎯 Main features

### 1. **Intelligent root detection**
The system detects the project boundaries automatically from several criteria:

- **VCS markers**: `.git`, `.hg`, `.svn` (highest priority)
- **Lua configuration files**: `.luarc.json`, `.neoconf.json`, `selene.toml`, `stylua.toml`
- **Neovim config directory**: special handling for `stdpath("config")`
- **Fallback**: the current directory, for single-file support

### 2. **Precise library management**
The workspace libraries are built dynamically per project root:

#### **Included libraries:**
- **Third-party definitions** (`${3rd}/...`):
  - `${3rd}/luv/library` - type definitions for vim.uv/vim.loop
  - `${3rd}/busted/library` - type definitions for the Busted test framework
  - `${3rd}/luassert/library` - `assert.are.equal` and friends. Busted without
    luassert is half a test environment, and a `.luarc.json` cannot supply it:
    naming `workspace.library` there *replaces* this list instead of adding to
    it

- **Neovim runtime**: all Neovim runtime paths for `vim.*` API detection

- **Project type directories**: automatic detection of `types/` and `@types/` folders

- **LuaRocks**: support for globally and locally installed rocks

- **Local dependencies**: `lua_modules/`, `deps/`, `vendor/`

### 3. **Optimised performance**
The system is optimised for performance:

- **Intelligent ignore lists**: skips `node_modules`, `.git`, `build` etc.
- **Configurable limits** (the values `init.lua` actually sends):
  - `maxPreload = 2000` - maximum number of preloaded files
  - `preloadFileSize = 500` - maximum file size (KB)
- **BFS scanning**: breadth-first search, with `max_depth` and `max_results`
  supplied per call by the caller (`build_library` uses 15/200). The scan is
  bounded in *results*, not in directories visited: measured at 315ms over the
  machine's plugin tree for 25 results, which is why it is not on the startup
  path -- see below.

### 4. **Git integration**
- Respects `.gitignore` files (`useGitIgnore = true`)
- Skips git directories automatically

## 📦 The modules in detail

### `init.lua` - main module

The heart of the configuration. Registers the lua_ls server with:

```lua
require("lsp.servers.lua_ls").setup({
  capabilities = capabilities,
  on_attach = on_attach,
  on_init = on_init,
}, {
  enable = true  -- enable automatically
})
```

**Important features:**
- Uses the native `vim.lsp.config()` API (Neovim 0.11+; `setup` is a no-op
  where `type(vim.lsp.config) ~= "table"`)
- Library configuration via the `before_init` hook -- **not** `on_new_config`,
  which is an lspconfig concept that `vim.lsp.config` never calls
- LuaJIT runtime for Neovim optimisation
- Inlay hints enabled
- Semantic tokens disabled (TreeSitter is preferred)

### `rootresolver.lua` - root detection

A polymorphic resolver function that works with both buffer numbers and file names:

```lua
local root = require("lsp.servers.lua_ls.rootresolver")
local project_root = root(bufnr)  -- or: root(filename)
```

The argument handling — buffer number or filename, the unnamed-buffer
fallback, the optional callback the `vim.lsp` `root_dir` contract allows —
comes from `lib.nvim.fs.polymorphic_rootresolver`. Only the algorithm below is
local, supplied through that module's `resolve` hook.

**Algorithm:**
1. Check whether we are inside `stdpath("config")` → use the config dir.
   **First**, before everything else, not as a correction afterwards
2. Consult the root-scope switch (`<leader>lsp`, `lsp.core.root_scope`):
   `"cwd"` returns the working directory and `"path"` returns the start
   directory, both bypassing steps 3–5. `"git"` (the default) continues
3. Search upward for a VCS root (`.git`, `.hg`, `.svn`)
4. Search upward for Lua markers (`.luarc.json`, `.neoconf.json`,
   `selene.toml`, `stylua.toml`)
5. Fall back to the start directory

Measured on `lua/lsp/init.lua` in this repo: scope `git` → the repo root,
scope `cwd` → the working directory, scope `path` → `…/lua/lsp`.

### `build_library.lua` - library construction

Builds the workspace libraries per project root:

```lua
local library = require("lsp.servers.lua_ls.build_library")(root)
-- Returns: { [path] = true, [path2] = true, ... }
```

**Library sources:**
- `${3rd}/luv/library` - luv types
- `${3rd}/busted/library` - Busted types
- `${3rd}/luassert/library` - luassert types
- project type directories **and standalone type files** via the scanner
  (`types.lua` / `@types.lua` count too)
- Neovim runtime paths, minus the project root itself
- LuaRocks, global & local
- local dependencies (`lua_modules`, etc.)
- local dev plugin `lua/` directories, guarded by `fs_stat`

Measured on this repo: 22 entries, of which 3 are `${3rd}` placeholders the
server expands itself, 2 are standalone `@types.lua` files and 17 are
directories. **This is not what a running server receives** — see
[The before_init hook](#the-before_init-hook).

### `find_type_dirs.lua` - type scanner

Searches the project for type directories:

```lua
local scanner = require("lsp.servers.lua_ls.find_type_dirs")
local type_dirs = scanner(root, {
  max_results = 100,
  max_depth = 10
})
```

**Features:**
- Breadth-first search (BFS) algorithm, so a tight `max_results` is spent on
  the shallowest matches
- Finds `types/` and `@types/` directories, plus any directory whose name ends
  in `types` or starts with `@types` (`mytypes`, `@typescript`). The name test
  is case-sensitive even on Windows, so `TYPES` does not match
- A directory only counts if it actually holds a `.lua` file, checked one level
  deep
- Also finds **standalone files** named `types.lua` or `@types.lua`, unless
  `include_files = false`. Measured on this repo with `{ max_results = 100,
  max_depth = 10 }`: 9 paths, 7 directories and 2 files
- Respects the ignore lists
- `max_results` bounds the **result list**, not the walk: the cost tracks the
  number of directories below the root, which is why lowering it does not make
  the scan cheap (see the figure under *Optimised performance*)

### `ignore.lua` - central ignore configuration

Centralised ignore lists for consistent handling:

```lua
local ignore = require("lsp.servers.lua_ls.ignore")

-- Three export formats:
local names = ignore.names()              -- ["node_modules", ...]
local set = ignore.as_set()               -- {node_modules=true, ...}
local patterns = ignore.as_luals_patterns() -- ["**/node_modules", ...]
```

**Ignored directories (examples):**
- `node_modules`, `bower_components`
- `.git`, `.svn`, `.hg`
- `build`, `dist`, `target`, `out`
- `.vscode`, `.idea`
- `__pycache__`, `.pytest_cache`

### `debug.lua` - debugging utilities

Helper functions for troubleshooting:

```lua
local debug = require("lsp.servers.lua_ls.debug")

-- Root for the current buffer
local root = debug.root_for_buf(bufnr)

-- Library paths for a root: a *sorted array of strings*, not build_library's
-- `{ [path] = true }` map
local libs = debug.debug_library(root)

-- Print debug info
debug.print_debug_info(bufnr)
```

`root_for_buf` delegates to `rootresolver` rather than carrying its own copy of
the algorithm, so it honours the `stdpath("config")`-first rule and the
`<leader>lsp` root-scope switch and cannot disagree with the root the server
actually resolved.

**Example output** (abridged; every path is printed):
```
[lsp.servers.lua_ls.debug] === LuaLS Debug Info ===
[lsp.servers.lua_ls.debug] Root: E:/repos/lsp.nvim
[lsp.servers.lua_ls.debug]
Type Directories (17):
[lsp.servers.lua_ls.debug]   C:\Program Files\Neovim\share\nvim\runtime
[lsp.servers.lua_ls.debug]   E:/repos/lsp.nvim/lua/lsp/@types
[lsp.servers.lua_ls.debug]   …
[lsp.servers.lua_ls.debug]
Type Files (2):
[lsp.servers.lua_ls.debug]   E:/repos/lsp.nvim/lua/lsp/diagnostics/@types.lua
[lsp.servers.lua_ls.debug]   E:/repos/lsp.nvim/lua/lsp/lspdoctor/@types.lua
[lsp.servers.lua_ls.debug]
Not on disk -- server-expanded or stale (3):
[lsp.servers.lua_ls.debug]   ${3rd}/busted/library
[lsp.servers.lua_ls.debug]   ${3rd}/luassert/library
[lsp.servers.lua_ls.debug]   ${3rd}/luv/library
```

The third bucket is the point: an entry `fs_stat` cannot see used to be dropped
with no trace, and printing "17 directories, 2 files" for a 22-entry library is
how a missing `${3rd}` entry stays invisible.

## 🔧 Installation & setup

### 1. Place the files

```
~/.config/nvim/lua/lsp/servers/lua_ls/
├── init.lua
├── rootresolver.lua
├── build_library.lua
├── find_type_dirs.lua
├── ignore.lua
└── debug.lua
```

### 2. Dependencies

Make sure these helper modules exist. They all live under `lib.nvim.*`; the
`lib.fs.*` spelling this section used to carry is from an older layout and
resolves to nothing:
- `lib.nvim.fs.polymorphic_rootresolver`
- `lib.nvim.fs.is_subpath`
- `lib.nvim.fs.ignore.list`
- `lib.nvim.notify`
- `lib.nvim.system.env`
- `lib.nvim.bindings.usercmd` and `lib.nvim.bindings.autocmd` (for `reload.lua`)

`lib.nvim.fs.find_upward_dir` used to be listed here; nothing under
`lsp/servers/lua_ls/` requires it.

### 3. LSP setup

In your `init.lua` or LSP configuration:

```lua
-- LSP capabilities and handlers
local capabilities = require('cmp_nvim_lsp').default_capabilities()
local on_attach = function(client, bufnr)
  -- your on_attach logic
end

-- Lua Language Server setup
require("lsp.servers.lua_ls").setup({
  capabilities = capabilities,
  on_attach = on_attach,
}, {
  enable = true
})
```

## 🐛 Debugging

### Problem: the server does not recognise the vim.* APIs

```lua
:lua require("lsp.servers.lua_ls.debug").print_debug_info()
```

Check whether:
- the root was detected correctly
- the Neovim runtime paths are contained in the library

### Problem: types not found

```lua
:lua vim.print(require("lsp.servers.lua_ls.find_type_dirs")(vim.fn.getcwd()))
```

Check whether:
- the type directories exist
- the ignore list does not hide them

### Problem: performance issues

Reduce the limits in `init.lua`:
```lua
workspace = {
  maxPreload = 2000,      -- preload fewer files
  preloadFileSize = 300,  -- smaller files
}
```

## 🎨 Customisation

### Adding further ${3rd} libraries

For a **running server**, in `library_profiles.build_runtime_library()` — that
is the list `before_init` installs:
```lua
library[#library + 1] = "${3rd}/luasocket/library"
```

Adding one in `build_library.lua` instead only changes what `debug` /
`:LuaLsInspectLibrary` report. That list is not on the startup path.

### Extending the ignore list

In `lib.nvim.fs.ignore.list` (which exposes `basenames`; this module derives
`names()`, `as_set()` and `as_luals_patterns()` from that array — 31 basenames,
62 patterns):
```lua
return {
  "node_modules",
  "custom_build_dir",  -- your custom directory
  -- ...
}
```

### Adjusting root detection

In `rootresolver.lua`:
```lua
-- Add further markers:
local lua_markers = vim.fs.find(
  { ".luarc.json", ".neoconf.json", "my_custom_marker.toml" },
  { path = dir, upward = true }
)
```

## 📊 Architecture diagram

Two paths, and the split between them is the thing to see: **the startup path
does not scan**.

```
┌─────────────────────────────────────────┐
│         init.lua (Main Setup)           │
│  ┌────────────────────────────────────┐ │
│  │ vim.lsp.config("lua_ls", {         │ │
│  │   root_dir = rootresolver,         │ │
│  │   settings = { ... },              │ │
│  │   before_init = ...                │ │
│  │ })                                 │ │
│  └────────────────────────────────────┘ │
└──────────────┬──────────────────────────┘
               │
               ├──────────────────────┐
               │                      │
               ▼                      ▼
   ┌────────────────────┐  ┌──────────────────────────┐
   │   rootresolver()   │  │      before_init         │
   │                    │  │        Hook              │
   │ • stdpath first    │  └────────────┬─────────────┘
   │ • root-scope switch│               │
   │ • VCS markers      │               ▼
   │ • Lua configs      │  ┌──────────────────────────────┐
   │  (via lib.nvim     │  │ library_profiles             │
   │   polymorphic_     │  │   .build_runtime_library()   │
   │   rootresolver)    │  │                              │
   └────────────────────┘  │ • ${3rd} luv/busted/luassert │
                           │ • $VIMRUNTIME/lua            │
                           │ 4 entries, ~0.01 ms, no I/O  │
                           └──────────────────────────────┘

              ── the scan is NOT on the path above ──

   debug.print_debug_info() / :LuaLsInspectLibrary
               │
               ▼
   ┌──────────────────┐
   │ build_library()  │
   │                  │
   │ • ${3rd} libs    │
   │ • Runtime paths  │
   │ • Type dirs ──┐  │
   │ • LuaRocks    │  │
   │ • local deps  │  │
   └───────────────┼──┘
                   │
                   ▼
   ┌──────────────────────┐
   │  find_type_dirs()    │
   │                      │
   │  • BFS scan          │
   │  • Ignore check ───┐ │
   │  • Collect types   │ │
   └────────────────────┼─┘
                        │
                        ▼
             ┌─────────────────┐
             │    ignore()     │
             │                 │
             │ • Shared list   │
             │ • as_set()      │
             │ • as_patterns() │
             └─────────────────┘
```

`ignore()` reaches the server by a third route as well: `as_luals_patterns()`
is what `settings.Lua.workspace.ignoreDir` is built from, in `init.lua`.

## 🔍 Important concepts

### Per-root library configuration

Every project root gets its own library configuration. This prevents:
- ❌ cross-contamination between projects
- ❌ wrong type inference from other projects
- ❌ performance degradation from overly large workspaces

### The ${3rd} placeholder system

lua_ls ships with built-in type definitions for popular libraries. The `${3rd}` prefix is resolved by the server at runtime:

```lua
library["${3rd}/luv/library"] = true
-- Resolves to: /path/to/lua-language-server/meta/3rd/luv/library
```

### The before_init hook

`before_init` runs once per client, just before the `initialize` request goes
out, and is where `Lua.workspace.library` is installed. It is the native
`vim.lsp` equivalent of lspconfig's `on_new_config`; the earlier version of
this file registered `on_new_config` instead, and `vim.lsp.config` never called
it, so no server received a library at all.

What it installs is `library_profiles.build_runtime_library()` -- the `${3rd}`
placeholders plus `$VIMRUNTIME/lua`, measured at 0.010ms -- and deliberately
not the full `build_library` scan. `find_type_dirs` only searches *below* the
project root, so what it finds is inside the workspace and gets indexed anyway.

Note that `LUA_LS_PROFILE` therefore has no effect on a running server;
the profiles in `library_profiles` bound the scan, and the scan is only reached
through `debug` / `build_library`.

## 📚 Further resources

- [lua_ls documentation](https://luals.github.io/)
- [Neovim LSP guide](https://neovim.io/doc/user/lsp.html)
- [lua_ls settings](https://luals.github.io/wiki/settings/)

## 🤝 Contributing

For problems or improvement suggestions:
1. Collect debugging info: `:lua require("lsp.servers.lua_ls.debug").print_debug_info()`
2. Create an issue with the debug output
3. Describe the relevant project structure

## 📝 Licence

This setup is part of your Neovim configuration and can be adapted freely.

---

**Note:** this documentation describes the system as a whole. For implementation details, see the inline comments in the respective modules.
