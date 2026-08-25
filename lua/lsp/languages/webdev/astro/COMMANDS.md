# Custom Astro Commands

## keymaps (Astro)

| Mode | Key combination | Description                                                          |
| ---- | --------------- | -------------------------------------------------------------------- |
| n    | gC              | Opens Telescope to search for Astro components in src/components     |
| n    | gL              | Opens Telescope to search for Astro layouts in src/layouts           |
| n    | gP              | Opens Telescope to search for Astro pages in src/pages               |
| n    | <leader>as      | Jumps to the next <script> block                                     |
| n    | <leader>ay      | Jumps to the next <style> block                                      |
| n    | <leader>at      | Jumps to the template area (after the frontmatter)                   |
| n    | <leader>af      | Jumps to the start of the frontmatter                                |
| n    | <leader>an      | Cycles to the next Astro section (script/style/frontmatter)          |
| n    | <leader>ai      | Jumps to the next import statement                                   |
| n    | <leader>aI      | Inserts an import statement for an Astro component                   |
| v    | <leader>ax      | Extracts the visual selection into a new Astro component             |
| n    | <leader>ap      | Opens the current Astro page in the browser (dev server)             |
| n    | <leader>aF      | Formats the current Astro file                                       |

---

## autocmds (AstroQoL)

| Event        | Pattern | Description                                                  |
| ------------ | ------- | ------------------------------------------------------------ |
| BufWritePre  | *.astro | Formats Astro files before saving                            |
| BufWritePre  | *.astro | Runs the LSP code action for organising imports              |
| FileType     | astro   | Sets buffer-local options (indent, tabs, commentstring)      |
| FileType     | astro   | Defines syntax highlighting for the Astro frontmatter        |
| VimLeavePre  | *.astro | Terminates running astro dev processes when leaving Neovim   |
| BufWritePost | *.astro | Checks used components for missing import statements         |

---

## user commands

| Command             | Arguments | Description                                       |
| ------------------- | --------- | ------------------------------------------------- |
| AstroDevStart       | –         | Starts the Astro dev server in a terminal split   |
| AstroDevStop        | –         | Stops the running Astro dev server                |
| AstroBuild          | –         | Builds the Astro project                          |
| AstroPreview        | –         | Starts the preview of the production build        |
| AstroNewComponent   | [name]    | Creates a new Astro component                     |
| AstroNewPage        | [name]    | Creates a new Astro page                          |
| AstroListComponents | –         | Lists all Astro components via Telescope          |
| AstroFindUsage      | –         | Searches for usages of the current component      |
| AstroCheckStructure | –         | Checks the project structure for missing folders  |

---

## augroup

| Name     | Description                                                  |
| -------- | ------------------------------------------------------------ |
| AstroQoL | Groups all Astro-related autocommands for the QoL features   |

---

## implicit dependencies / prerequisites

| Component       | Purpose                                  |
| --------------- | ---------------------------------------- |
| telescope.nvim  | File and usage search                    |
| conform.nvim    | Formatter integration (fallback to LSP)  |
| Astro LSP       | Code actions, formatting                 |
| astro CLI       | Dev server, build, preview               |
| pkill           | Process termination (Linux/macOS)        |
| xdg-open / open | Browser preview (Linux/macOS)            |

---

## notes on the structure

* all keymaps are buffer-local and active only for Astro files
* no global side effects outside the Astro context
* commands are idempotent and explicitly user-triggered
* autocmds are cleanly encapsulated in their own augroup

If wanted, this can also yield:

* generated README documentation
* an automatically produced help file (:h astro-qol)
* or a machine-readable overview (e.g. JSON / a Lua table)
