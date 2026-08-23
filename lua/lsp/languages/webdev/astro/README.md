# lsp.languages.webdev.astro

Astro entry point: wires this module's own usercmds and autocmds submodules
together with `lsp.servers.webdev.astro.autotag`, then attaches its keymaps
submodule and sets buffer-local Astro options (commentstring, 2-space
indent) on `FileType`.
