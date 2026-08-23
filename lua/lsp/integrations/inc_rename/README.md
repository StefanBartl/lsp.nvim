# config.inc_rename

Incremental LSP rename with Noice cmdline UI and automatic save of edited
buffers. `<leader>rn` starts a workspace-aware rename pre-filled with
`<cword>`; on `<CR>` the LSP applies a `WorkspaceEdit`, then a post-hook
writes all touched buffers.
