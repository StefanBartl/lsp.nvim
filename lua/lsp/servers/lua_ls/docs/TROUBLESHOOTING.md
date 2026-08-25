# LSP `lua_ls` troubleshooting

## If types still are not found, make sure that

- every `@types/*.lua` file ends with `return {}`
- the @types folder lives in `lua/lsp/@types/`
- `find_type_dirs.lua` finds that folder

---
