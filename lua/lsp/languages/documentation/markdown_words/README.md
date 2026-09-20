# md_words.nvim (`markdown_words/init.lua`)

A tailor-made completion source for Neovim that provides **project-wide** word
completions for Markdown and MDX files. It is engine-neutral: the spec goes to
`lsp.completion.register`, which hands it to whichever engine
`lsp.config.pack.completion()` says is active — **blink** by default here,
**nvim-cmp** if that is what the config runs.

While language servers such as `marksman` are excellent at cross-project link and heading completions, they often lack the ability to suggest ordinary words from *other* files in the project. This module closes that gap by scanning the project directory in the background, tokenising it and offering the result as a fluid completion source.

---

## Table of content

- [md_words.nvim (`markdown_words/init.lua`)](#md_wordsnvim-markdown_wordsinitlua)
  - [Features](#features)
  - [Installation & integration](#installation--integration)
    - [1. Place the file](#1-place-the-file)
    - [2. Wire it into the Markdown setup](#2-wire-it-into-the-markdown-setup)
  - [Configuration](#configuration)
  - [User commands](#user-commands)
  - [How it works in the background](#how-it-works-in-the-background)

---

## Features

* **Project-wide scan:** analyses all `.md` and `.mdx` files below the project root.
* **Deferred, not asynchronous:** the scan is `vim.defer_fn`'d off the current tick, but `vim.uv`'s *synchronous* `fs_scandir`/`fs_read` do the work, so it runs on the main loop and blocks the editor for its whole duration. Measured over 500 files of ~40 KB: 157 ms wall, during which a repeating 10 ms timer got **1** tick where a free loop would have given ~15. `max_files` and `max_filesize` are what keep that bounded — which is why the cap has to hold per file, not per directory.
* **Intelligent cache:** the scan runs exactly once (lazily) when the first Markdown file is opened and caches the result for the rest of the session, so the freeze is a one-off rather than something felt while typing.
* **Directory awareness:** if you change directory in the editor (`DirChanged`), the cache rebuilds itself automatically after 3 seconds (debounced) — with the same freeze.
* **Safeguards:** automatically ignores typical folders (such as `.git`, `node_modules`, `dist`, `target`) and skips files that are too large.

---

## Installation & integration

### 1. Place the file

Save the module's code in your Neovim configuration folder under:
`lua/lsp/languages/documentation/markdown_words/init.lua`

### 2. Wire it into the Markdown setup

Simply call the `.setup()` method in your existing configuration — ideally where your Markdown LSP is initialised (e.g. at the end of your `M.enable()` function in `lua/lsp/languages/documentation/markdown.lua`):

```lua
function M.enable()
  -- ... your existing code (e.g. marksman / lspconfig setup) ...

  -- enable project-wide word completions
  require("lsp.languages.documentation.markdown_words").setup()
end

```

---

## Configuration

The module works *out of the box* with sensible defaults. If needed, you can pass a table of your own options to the `setup()` function:

```lua
require("lsp.languages.documentation.markdown_words").setup({
  max_files    = 500,           -- maximum number of files to scan
  max_filesize = 204800,        -- files above 200 KB are ignored
  min_word_len = 3,             -- words must be at least 3 characters long
  max_word_len = 60,            -- words longer than 60 characters are ignored
  filetypes    = { "md", "mdx" },-- file extensions that get scanned
  debounce_ms  = 3000,          -- wait time for the auto-rebuild after ':cd'
})

```

---

## User commands

The module automatically registers three useful commands in Neovim:

| Command | Effect |
| --- | --- |
| `:MdSetRoot ~/my/project` | Sets the scan directory explicitly and forces a rebuild. |
| `:MdSetRoot` *(without a path)* | Resets the root back to the current working directory (`cwd`). |
| `:MdRebuildWords` | Invalidates the current cache and rescans the current directory immediately. |
| `:MdWordStats` | Shows statistics in the status line (current path, number of loaded words, cache state). |

> **Note on the behaviour:** once you set the root path explicitly with `:MdSetRoot /path`, the automatic rebuild on a directory change (`DirChanged`) is blocked, so that your work is not overwritten.

---

## How it works in the background

1. **Trigger:** as soon as a buffer with the filetype `markdown` or `mdx` is opened, the module wakes up.
2. **Scan:** it recursively collects all relevant files, strips them of Markdown syntax characters (such as `*`, `#`, `_`) and extracts pure text tokens.
3. **Injection:** the words are handed to `lsp.completion.register` as the source `md_words`, which passes them to the active engine. The item list itself is **not** sorted — both engines re-sort by score and `sortText` before drawing the menu, so sorting ~25000 words here would be work neither of them reads. Standing below real LSP items comes from `sortText` instead: an unpicked word is prefixed with `"~"`, the last printable ASCII character, and the engine config adds to that (`score_offset = -3` for the blink provider; `priority = 100` is what the nvim-cmp side used). The source spec carries no `priority` field of its own.
4. **Ranking:** picks are counted in `lsp.completion.usage` under the `md_words` namespace, and a picked word's `sortText` is re-stamped in place on the next request — not by rebuilding the list, which measured 31 ms per accepted word.
