# Configuration layers

Four sources, lowest to highest: `DEFAULTS`, the `preset` profile, your
`setup()` options, and a `.nvim-lsp.json` found by walking up from the working
directory. `preset = "lean"` turns down the work paid per keystroke and per
attach without touching on-demand actions; the project file switches a server
off in one checkout without touching the global config. Every warning names the
layer the offending value came from, and `:Lsp status` / `:checkhealth lsp`
name the profile and the project file that were used.

The project file is JSON, not Lua, and accepts only the keys the repository
knows the answer to — cloning a repository must not be enough to run its code
or to move your keys.

- **Modules:** `config/init.lua`, `config/PRESETS.lua`, `config/project.lua`
- **Config:** `preset`, `project.enable`, `project.file`

The precedence argument in full, the allowlist, and the reasoning behind each
individual option are in [configuration.md](../configuration.md).
