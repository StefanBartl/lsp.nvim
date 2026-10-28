# lsp.tools.deprecated_help

Modularized deprecated-API warning helper; `setup({ keymap = "<leader>lh" })`
wires up a keymap that surfaces the deprecation notice.

`display` decides how the help of the symbol is shown:

- `"hover"` (default): the symbol's help entry in a float, focus stays in the code
- `"help"`: `:help <symbol>` in a help window

```lua
require("lsp.tools.deprecated_help").setup({ keymap = "<leader>lh", display = "help" })
```

Through lsp.nvim's config: `tools.deprecated_help = { enable = true, display = "hover" }`.
