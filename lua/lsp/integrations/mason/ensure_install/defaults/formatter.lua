---@module 'config.mason.ensure_install.defaults.formatter'
-- =====================================================================================
-- Tool set (defaults): true = ensure install, false = ignore
-- =====================================================================================

---@type Cfg.Mason.EnsureMap
return {
  ["luaformatter"] = true,
  ["yamlfix"] = true,
  ["yamlfmt"] = true,
  ["xmlformatter"] = true,
  ["sqlfmt"] = true,
  ["rustfmt"] = true,
  -- ["php-cs-fixer"] = true,
  --["pgformatter"] = false,
  --["ormolu"] = false,
  --["phpcbf"] = false,
  --["nginx-config-formatter"] = true,
  ["markdownlint-cli2"] = true,
  -- ["gotests"] = true,
  -- ["golines"] = true,
  --["goimports"] = true,
  -- ["goimports-reviser"] = true,
  -- ["gofumpt"] = true,
  ["cmakelang"] = true,
  ["ast-grep"] = true,
  ["asmfmt"] = true,
  ["prettier"] = true,
  ["sql-formatter"] = true,
  ["markdown-toc"] = true,
  ["markdownlint"] = true,
  ["mdformat"] = true,

  -- Web Development
  --  ["biome"] = true,
  --["rustywind"] = true, -- Tailwind class sorter
  --  ["htmlbeautifier"] = false,

  -- Mobile formatters
  --  ["google-java-format"] = true,
  -- ["ktlint"] = true,
}
