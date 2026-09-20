# rootresolver: lua_ls vs marksman

The two are functionally similar — both expose a **polymorphic root resolver**
that takes either a buffer (`bufnr`) or a filename (`fname`). Since the
unification described at the bottom of this file, both are
`lib.nvim.fs.polymorphic_rootresolver` under a different configuration, so the
argument handling, the fallbacks and the callback contract are now *the same
code* and no longer a point of comparison. What still differs is the root
*algorithm* each one configures, and what else the surrounding module carries.

Side by side:

| Aspect | Marksman (`rootresolver.lua`) | LuaLS (`rootresolver.lua`) |
| --- | --- | --- |
| **Polymorphism** | Shared: `bufnr` or `fname`, plus an optional `cb`. Note this is the *resolver module*; the `root_dir` registered in `init.lua` wraps it and is buffer-only — see [README.md](README.md). | Shared, identically. |
| **Fallbacks** | Shared: an empty `fname` becomes `uv.cwd()`/`vim.fn.getcwd()`, then `vim.fs.dirname(vim.fs.normalize(fname))`, and an unresolved root falls back to that start directory. | Shared, identically. |
| **Root detection** | The shared marker search: `vim.fs.root(dir, markers)` over `.marksman.toml`, `.git`, `mkdocs.yml`. | Its own `resolve` hook: `stdpath("config")` **first**, then the `<leader>lsp` root-scope switch (`cwd`/`path` bypass the rest), then the VCS root (`.git`, `.hg`, `.svn`), then Lua markers (`.luarc.json`, `.neoconf.json`, `selene.toml`, `stylua.toml`). |
| **Marker configuration** | Configured through `lsp.servers.marksman.config`'s `root_dir_fallbacks`, so it is easy to extend. | Markers are hard-coded in the resolver: less configurable, more specific to Lua projects. |
| **`stdpath("config")`** | `include_stdpath_config = false`: a Markdown file under the Neovim config belongs to whatever repository it sits in. | `include_stdpath_config = false` too, but only because the hook does that check itself, and does it first rather than as a correction afterwards. |
| **Callback support** | Shared: optional, synchronous, pcall-guarded. | Shared, identically. |
| **Diagnostics and extras** | The surrounding module carries a diagnostics filter, a code-action filter and a hints toggle — in `diagnostics_handler.lua`, `code_action_handler.lua` and `hints.lua`. | No diagnostics; a root resolver and nothing else. |
| **Flexibility** | Generic, for any Markdown project. | Project-specific, for working out a Lua workspace. |
| **Structure and separation** | Split, not one file: `init.lua` (LSP setup), `rootresolver.lua`, `config.lua`, `diagnostics_handler.lua`, `code_action_handler.lua`, `hints.lua`. There is no `marksman.lua`. | A pure utility module (`rootresolver.lua`), with the LSP setup kept separate in `init.lua`. |

## Conclusion

* **Marksman**: simpler, generic, primarily for the Markdown LSP. Root
  detection is limited to a few markers, but they are cleanly configurable via
  `cfg`, which suits general projects. Comes with the diagnostics extras.
* **LuaLS**: very project-specific and robust against the various shapes a Lua
  project takes (config directory, the root-scope switch, VCS plus tool
  markers). Less configurable, stricter in return. Both now split the utility
  (`rootresolver.lua`) from the LSP setup (`init.lua`); marksman did not when
  this was written.

Put shortly: **Marksman solves the problem coarsely, simply and generically**,
while **LuaLS goes at it strictly, robustly and project-specifically**.

The two could be unified — a generic `polymorphic_root_resolver` module
abstracting markers, fallbacks and asynchrony, configured per project or per
language server. That has since happened: `lib.nvim.fs.polymorphic_rootresolver`
is exactly that module, and both callers route through it.
