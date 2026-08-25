# Lua Language Server (lua_ls) setup for Neovim

These Lua modules configure the Lua Language Server (lua_ls) for Neovim with intelligent root detection, precise workspace library management and optimised performance.

## 📋 Overview

The setup consists of several interconnected modules that provide a robust and performant lua_ls integration:

```
lsp/servers/lua_ls/
├── init.lua              # main module: LSP server configuration
├── rootresolver.lua      # project root detection
├── build_library.lua     # workspace library construction
├── find_type_dirs.lua    # scanner for type directories
├── ignore.lua            # central ignore configuration
└── debug.lua             # debugging utilities
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

- **Neovim runtime**: all Neovim runtime paths for `vim.*` API detection

- **Project type directories**: automatic detection of `types/` and `@types/` folders

- **LuaRocks**: support for globally and locally installed rocks

- **Local dependencies**: `lua_modules/`, `deps/`, `vendor/`

### 3. **Optimised performance**
The system is optimised for performance:

- **Intelligent ignore lists**: skips `node_modules`, `.git`, `build` etc.
- **Configurable limits**:
  - `maxPreload = 3000` - maximum number of preloaded files
  - `preloadFileSize = 500` - maximum file size (KB)
- **BFS scanning**: breadth-first search with a configurable depth (`max_depth = 12`)

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
- Uses the native `vim.lsp.config()` API (Neovim 0.10+)
- Dynamic library configuration via the `on_new_config` hook
- LuaJIT runtime for Neovim optimisation
- Inlay hints enabled
- Semantic tokens disabled (TreeSitter is preferred)

### `rootresolver.lua` - root detection

A polymorphic resolver function that works with both buffer numbers and file names:

```lua
local root = require("lsp.servers.lua_ls.rootresolver")
local project_root = root(bufnr)  -- or: root(filename)
```

**Algorithm:**
1. Check whether we are inside `stdpath("config")` → use the config dir
2. Search upward for a VCS root (`.git`, etc.)
3. Search upward for Lua markers (`.luarc.json`, etc.)
4. Fall back to the start directory

### `build_library.lua` - library construction

Builds the workspace libraries per project root:

```lua
local library = require("lsp.servers.lua_ls.build_library")(root)
-- Returns: { [path] = true, [path2] = true, ... }
```

**Library sources:**
- `${3rd}/luv/library` - luv types
- `${3rd}/busted/library` - Busted types
- project type directories via the scanner
- LuaRocks, global & local
- local dependencies (`lua_modules`, etc.)

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
- Breadth-first search (BFS) algorithm
- Finds `types/` and `@types/` directories
- Respects the ignore lists
- Configurable limits for performance

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

-- Library paths for a root
local libs = debug.debug_library(root)

-- Print debug info
debug.print_debug_info(bufnr)
```

**Example output:**
```
LuaLS Debug Info:
Root: /home/user/projects/my-plugin
Library paths: /home/user/.config/nvim, /home/user/projects/my-plugin/types, ...
```

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

Make sure these helper modules exist:
- `lib.fs.is_subpath`
- `lib.fs.find_upward_dir`
- `lib.fs.ignore.list`

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

In `build_library.lua`:
```lua
library["${3rd}/luasocket/library"] = true
library["${3rd}/lfs/library"] = true
```

### Extending the ignore list

In `lib.fs.ignore.list`:
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

```
┌─────────────────────────────────────────┐
│         init.lua (Main Setup)           │
│  ┌────────────────────────────────────┐ │
│  │ vim.lsp.config("lua_ls", {         │ │
│  │   root_dir = rootresolver(),       │ │
│  │   settings = { ... },              │ │
│  │   on_new_config = ...              │ │
│  │ })                                 │ │
│  └────────────────────────────────────┘ │
└──────────────┬──────────────────────────┘
               │
               ├─────────────────────┐
               │                     │
               ▼                     ▼
    ┌──────────────────┐  ┌──────────────────┐
    │  rootresolver()  │  │  on_new_config   │
    │                  │  │      Hook        │
    │ • VCS markers    │  └────────┬─────────┘
    │ • Lua configs    │           │
    │ • stdpath check  │           ▼
    └──────────────────┘  ┌──────────────────┐
                          │ build_library()  │
                          │                  │
                          │ • ${3rd} libs    │
                          │ • Runtime paths  │
                          │ • Type dirs ──┐  │
                          │ • LuaRocks    │  │
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

### The dynamic on_new_config hook

The `on_new_config` hook is called on every root switch. That makes possible:
- ✅ root-specific libraries
- ✅ dynamic adaptation to the project structure
- ✅ no global state pollution

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
