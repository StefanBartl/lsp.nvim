---@module 'lsp.config.PRESETS'
---@brief Named option profiles that sit between `DEFAULTS` and the user's own
--- options.
---@description
--- A preset answers one question -- *how much of this plugin should run on this
--- machine* -- with one word instead of twenty fields. `config/init.lua` merges
--- the selected table over a copy of `DEFAULTS` and then merges the user's
--- options over that, so anything named explicitly in `setup()` still wins.
---
--- `default` is deliberately empty rather than a copy of `DEFAULTS`. The
--- defaults are the profile; duplicating them here would create a second place
--- to change them and a first opportunity for the two to disagree.
---
--- Two things a preset never touches, whatever its name says:
---
--- * **`mason.ensure_install`** -- installing software is a side effect outside
---   the editor. A preset is a performance dial, not consent to download.
--- * **`formatter.on_save`** -- it writes to files. "Turn everything on" must
---   not silently start rewriting buffers on save.
---
--- Both stay opt-in under every preset, which is why `full` is safe to pick
--- without reading this file first.
---
---@see lsp.config
---@see lsp.config.DEFAULTS

---@type table<LspNvim.Preset, table>
local PRESETS = {
  -- The documented defaults, unchanged.
  default = {},

  -- Everything whose cost is paid per keystroke, per attach or per redraw,
  -- turned down. Aimed at a machine where `ts_ls` on a large repo is already
  -- the budget: what goes is the *continuous* work, not the on-demand work --
  -- `gd`, hover and rename behave exactly as they do under `default`.
  lean = {
    diagnostics = {
      -- The two continuous costs of a diagnostics push: rendering inline text
      -- for every line, and doing it several times per keystroke pause. Signs,
      -- the float and the quickfix routes are untouched, so nothing becomes
      -- invisible -- it stops being redrawn while you type.
      virtual_text = false,
      debounce_ms = 400,
    },
    inlay_hints = { enable = false },
    -- One `textDocument/codeAction` round trip per cursor position. Cheap per
    -- request and continuous by nature, which is exactly the class of cost
    -- this preset turns off.
    lightbulb = { enable = false },
    -- Left ON. It costs nothing while nothing crashes, and a weak machine is
    -- where a server gets OOM-killed in the first place -- exactly where
    -- noticing by hand is most expensive.
    attach = {
      -- The single most expensive default: it walks the workspace on attach.
      -- Its own `max_files` gate already refuses the biggest cases, but on a
      -- weak machine the measurement itself is the cost worth skipping.
      use_workspace_diagnostics = false,
    },
    tools = {
      eslint_prettier = { enable = false },
      -- Fires a `textDocument/signatureHelp` round trip while typing inside an
      -- argument list -- the one tool whose cost is literally per keystroke.
      lsp_signature = { enable = false },
      ts_type_lookup = { enable = false },
      deprecated_help = { enable = false },
    },
    completion = { personal_names = { enable = false } },
    keymaps = { preset = "minimal" },
    -- ~25 command registrations at startup that duplicate `:Lsp` routes.
    usrcmds = { legacy_aliases = false },
    menu = { enable = false },
  },

  -- Every feature the plugin has, on. The inverse trade: more feedback,
  -- sooner, at the cost of more work per keystroke.
  full = {
    diagnostics = {
      update_in_insert = true,
      debounce_ms = 50,
    },
    inlay_hints = { enable = true },
    -- Unfiltered here, unlike the default allowlist: this preset's trade is
    -- "more feedback, sooner", and a refactor you did not know was on offer is
    -- feedback.
    lightbulb = { enable = true, kinds = {} },
    attach = {
      use_workspace_diagnostics = true,
      use_lazydev = true,
    },
    tools = {
      eslint_prettier = { enable = true },
      lsp_signature = { enable = true },
      ts_type_lookup = { enable = true },
      deprecated_help = { enable = true },
    },
    completion = { personal_names = { enable = true } },
    keymaps = { preset = "default" },
    usrcmds = { legacy_aliases = true },
    which_key = { enable = true },
    menu = { enable = true },
  },
}

return PRESETS
