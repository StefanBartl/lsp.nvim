---@module 'lsp.integrations.mason.ensure_install.defaults.formatter'
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
  -- ["rustfmt"] -- not a Mason package and never has been: rustfmt ships as a
  -- rustup component, so `registry.get_package("rustfmt")` raises and every
  -- run of `ensure_install` reported it under "unknown: rustfmt (not in
  -- registry)". Checked against the installed registry index
  -- (2026-07-16-tangy-mantle, 584 packages): the only rust entries are
  -- `rust-analyzer`, `rust_hdl` and `rustywind`. A name that can never
  -- install is worse than an absent one -- it is a line of the summary that
  -- asks to be acted on and cannot be.
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
