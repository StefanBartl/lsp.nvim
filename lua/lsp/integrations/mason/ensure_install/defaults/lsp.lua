---@module 'config.mason.ensure_install.defaults.lsp'
-- =====================================================================================
-- Tool set (defaults): true = ensure install, false = ignore
-- =====================================================================================

---@type Cfg.Mason.EnsureMap
return {
  --  ["copilot-language-server"] = true,
  -- ["java-language-server"] = false,
  ["csharp-language-server"] = false,
  -- ["zls"] = true,
  ["yaml-language-server"] = true,
  ["vim-language-server"] = true,
  ["ts_query_ls"] = true,
  ["sqlls"] = true,
  -- ["systemd-language-server"] = true,
  --["pbls"] = true,
  --["python-lsp-server"] = true,
  --["powershell-editor-services"] = true,
  --["perlnavigator"] = false,
  --["phpactor"] = true,
  ["omnisharp"] = true,
  --["nginx-language-server"] = true,
  ["markdown-oxide"] = true,
  --["m68k-lsp-server"] = true,
  ["lua-language-server"] = true,
  ["jsonld-lsp"] = true,
  -- ["graphql-language-service-cli"] = true,
  --["hoon-language-server"] = true,
  --  ["gopls"] = true,
  -- ["golangci-lint-langserver"] = true,
  ["asm-lsp"] = true,
  --["docker-compose-language-service"] = true,
  --["dockerfile-language-server"] = true,
  --["docker-language-server"] = true,
  ["sqls"] = true,
  ["cmake-language-server"] = true,
  ["ast-grep"] = true,
  ["bash-language-server"] = true,
  ["eslint-lsp"] = true,
  ["json-lsp"] = true,
  ["marksman"] = true,

  -- Web Development
  ["html-lsp"] = true,
  ["typescript-language-server"] = true,
  -- ["astro-ls"] = true,
  --  ["astro-language-server"] = true,
  ["tailwindcss-language-server"] = true,
  ["css-lsp"] = true,
  ["htmx-lsp"] = true,
  -- ["wasm-language-tools"] = true, -- oft manuell installiert
  -- ["unocss-language-server"] = true,
  ["vtsls"] = true, -- besserer TS/JS Server
  --["biome"] = true, -- schneller Formatter/Linter
  ["vue-language-server"] = true,
  ["svelte-language-server"] = true,
  --["svlangserver"] = true,

  -- Mobile development
  --  ["jdtls"] = true,
  -- ["kotlin-language-server"] = true,
  --["dart-language-server"] = true,
}
