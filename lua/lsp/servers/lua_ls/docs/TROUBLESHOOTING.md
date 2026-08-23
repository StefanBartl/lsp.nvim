# LSP `lua_ls`-Troubleshooting

## Falls Typen nicht gefunden werden weiterhin besteht, stellee sicher dass

- Alle `@types/*.lua` Dateien mit `return {}` enden
- Der @types Ordner in `lua/lsp/@types/` liegt
- `find_type_dirs.lua` diesen Ordner findet

---
