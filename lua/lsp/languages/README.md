# lsp.languages

Entry point: `M.enable_all()` calls each app/documentation/scripting/
systems/webdev language module's own `enable()`, pcall-guarded so one
missing module never stops the rest.
