# md_words.nvim (`markdown_words.lua`)

A tailor-made **nvim-cmp** source module for Neovim that provides **project-wide** word completions for Markdown and MDX files.

While language servers such as `marksman` are excellent at cross-project link and heading completions, they often lack the ability to suggest ordinary words from *other* files in the project. This module closes that gap by scanning the project directory in the background, tokenising it and offering the result as a fluid completion source.

---

## Table of content

- [md_words.nvim (`markdown_words.lua`)](#md_wordsnvim-markdown_wordslua)
  - [Features](#features)
  - [Installation & integration](#installation--integration)
    - [1. Place the file](#1-place-the-file)
    - [2. Wire it into the Markdown setup](#2-wire-it-into-the-markdown-setup)
  - [Configuration](#configuration)
  - [User commands](#user-commands)
  - [How it works in the background](#how-it-works-in-the-background)

---

## Features

* **Project-wide scan:** analyses all `.md` and `.mdx` files below the project root asynchronously.
* **Asynchronous & non-blocking:** uses `libuv` (`vim.uv`) in the background. Large directories never block Neovim's UI.
* **Intelligent cache:** the scan runs exactly once (lazily) when the first Markdown file is opened and caches the result for the rest of the session.
* **Directory awareness:** if you change directory in the editor (`DirChanged`), the cache rebuilds itself automatically in the background after 3 seconds (debounced).
* **Safeguards:** automatically ignores typical folders (such as `.git`, `node_modules`, `dist`, `target`) and skips files that are too large.

---

## Installation & integration

### 1. Place the file

Save the module's code in your Neovim configuration folder under:
`lua/lsp/languages/documentation/markdown_words.lua`

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

> 💡 **Note on the behaviour:** once you set the root path explicitly with `:MdSetRoot /path`, the automatic rebuild on a directory change (`DirChanged`) is blocked, so that your work is not overwritten.

---

## How it works in the background

1. **Trigger:** as soon as a buffer with the filetype `markdown` or `mdx` is opened, the module wakes up.
2. **Scan:** it recursively collects all relevant files, strips them of Markdown syntax characters (such as `*`, `#`, `_`) and extracts pure text tokens.
3. **Injection:** the words are sorted stably and handed to `nvim-cmp` as the source `md_words` with a low priority (`priority = 100`), so that they do not overlay ordinary LSP suggestions (such as links).
