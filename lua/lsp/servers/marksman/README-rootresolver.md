# rootresolver: lua_ls vs marksman

The two are functionally similar — both implement a **polymorphic `root_dir`
resolver** that takes either a buffer (`bufnr`) or a filename (`fname`). They
differ clearly in design, flexibility and how far they go.

Side by side:

| Aspect | Marksman | LuaLS (`rootresolver.lua`) |
| --- | --- | --- |
| **Polymorphism** | Yes: accepts `bufnr` or `fname`, plus an optional `cb`. | Yes, likewise `bufnr` or `fname` with an optional callback. |
| **Fallbacks** | `fname` empty or no buffer available: falls back to `_cwd()`, the working directory. | Uses `vim.fs.dirname(vim.fs.normalize(fname))`, then `cwd()`, then `vim.fn.getcwd()`. |
| **Root detection** | Only `vim.fs.root(dir, M.cfg.root_dir_fallbacks)` — checks markers such as `.git`, `.marksman.toml`, `mkdocs.yml`. | Stricter: the VCS root (`.git`, `.hg`, `.svn`) first, then Lua-specific markers (`.luarc.json`, `selene.toml`, …), then `stdpath("config")` if needed. |
| **Marker configuration** | Configured through `M.cfg.root_dir_fallbacks`, so it is easy to extend. | Markers are hard-coded in the resolver: less configurable, more specific to Lua projects. |
| **Callback support** | Fully supported, for the asynchronous LSP pipeline. | Yes, optional, synchronous and pcall-guarded. |
| **Diagnostics and extras** | Carries a dedicated diagnostics-handler setup for filtering Markdown errors. | No diagnostics; a root resolver and nothing else. |
| **Flexibility** | Generic, for any Markdown project. | Project-specific, for working out a Lua workspace. |
| **Structure and separation** | Everything in one module (`marksman.lua`): LSP setup, root detection and diagnostics together. | A pure utility module (`rootresolver.lua`), with the LSP setup kept separate in `init.lua`. |

**Conclusion:**

* **Marksman**: simpler, generic, primarily for the Markdown LSP. Root
  detection is limited to a few markers, but they are cleanly configurable via
  `cfg`, which suits general projects. Comes with the diagnostics extras.
* **LuaLS**: very project-specific and robust against the various shapes a Lua
  project takes (VCS plus tool markers). Less configurable, stricter in return.
  Splitting the utility (`rootresolver.lua`) from the LSP setup (`init.lua`)
  makes it the cleaner one to reuse.

Put shortly: **Marksman solves the problem coarsely, simply and generically**,
while **LuaLS goes at it strictly, robustly and project-specifically**.

The two could be unified — a generic `polymorphic_root_resolver` module
abstracting markers, fallbacks and asynchrony, configured per project or per
language server. That has since happened: `lib.nvim.fs.polymorphic_rootresolver`
is exactly that module, and both callers route through it.
