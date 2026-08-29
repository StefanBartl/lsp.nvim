---@module 'scripts.gen_map'
--- CLI entry point for lsp.nvim's module map.
---
---   nvim --headless -l scripts/gen_map.lua                    # regenerate
---   nvim --headless -l scripts/gen_map.lua --check            # verify, write nothing
---   nvim --headless -l scripts/gen_map.lua --check --lenient  # fail on staleness only
---   nvim --headless -l scripts/gen_map.lua --full             # + LuaLS enrichment
---
--- Everything above the options table is copied verbatim from
--- documentation.nvim's `scripts/gen_map.lua`; see its docs/REUSE.md.

local root = vim.uv.cwd():gsub("\\", "/"):gsub("/+$", "")
vim.opt.runtimepath:prepend(root)

--- Put a dependency on the runtimepath, if it is not already reachable.
---
--- A headless `nvim -l` run starts with no plugin manager, so nothing beyond
--- `root` is on the rtp — `documentation` and `lib.nvim` both have to be found
--- by hand. Three candidates, in descending order of explicitness: an
--- environment variable (what CI sets), a `.deps/` checkout (what CI clones
--- into), and a sibling checkout (what a local development tree looks like).
---@param modname string A module the dependency provides, used as the probe.
---@param dirname string Repository directory name.
local function ensure(modname, dirname)
  if pcall(require, modname) then
    return
  end
  local candidates = {}
  local env_dir = vim.env[dirname:upper():gsub("[.-]", "_") .. "_DIR"]
  if env_dir and env_dir ~= "" then
    candidates[#candidates + 1] = env_dir
  end
  candidates[#candidates + 1] = root .. "/.deps/" .. dirname
  candidates[#candidates + 1] = vim.fs.dirname(root) .. "/" .. dirname
  for _, dir in ipairs(candidates) do
    if vim.fn.isdirectory(dir) == 1 then
      vim.opt.runtimepath:prepend(dir)
      if pcall(require, modname) then
        return
      end
    end
  end
  io.stderr:write(("gen_map: %s not found (probed require('%s')).\n"):format(dirname, modname))
  io.stderr:write(
    ("  Set %s_DIR, clone it to .deps/%s, or check it out beside this repo.\n"):format(
      dirname:upper():gsub("[.-]", "_"),
      dirname
    )
  )
  os.exit(1)
end

ensure("lib.nvim.fs.read", "lib.nvim")
ensure("documentation.core.cli", "documentation.nvim")

local opts = require("documentation.config").build(root, {
  source = "lua/lsp",
  title = "lsp.nvim",
  out_dir = "docs/map",
  repo_url = "https://github.com/StefanBartl/lsp.nvim",
  branch = "main",

  -- The layer rule the whole umbrella design rests on:
  -- the core must not reach into the integrations. `core/attach.lua` never
  -- requires `lazydev` itself; the adapter does. Without a check this is only
  -- a sentence in the roadmap, and the first `pcall(require, "trouble")` in a
  -- core module quietly ends the separation.
  --
  -- Declared now, before there is core code to violate it — the rule is
  -- cheapest to hold when nothing has broken it yet.
  layers = {
    {
      from = "lsp.core",
      to = "lsp.integrations",
      why = "the core runs on vim.lsp only; third-party plugins are reached through adapters",
    },
    {
      from = "lsp.core",
      to = "lsp.pack",
      why = "the LazySpec export is read by the plugin manager, never by the plugin itself",
    },
  },
})

local code = require("documentation.core.cli").run(opts, _G.arg or {})
vim.cmd("cq " .. code)
