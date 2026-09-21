---@module 'lsp.health'
---@brief `:checkhealth lsp`.
---@description
--- Reports the environment, what `setup()` actually did, the servers, and the
--- ecosystem around the plugin. It reads `require("lsp").status()` rather than
--- reaching into the modules, so the health output and `:Lsp status` cannot
--- disagree.
---
--- Roadmap section 11 makes this a thin second interface onto `lspdoctor`'s
--- core. That is what the last section is: `:LspDoctor startup` answers "is this
--- buffer's LSP healthy", this answers "is the plugin healthy" and points at
--- the other for the per-buffer detail. Neither reimplements the other.
---
--- Severity follows dependency hardness: something the plugin cannot work
--- without is an error, something it uses when present is information.
---
---@see lsp.init
---@see lsp.config
---@see lsp.lspdoctor

local health = vim.health

local M = {}

---@internal
---@param modname string
---@return boolean
local function has(modname)
  return (pcall(require, modname))
end

---@internal
--- Whether a module loads, and when it does not, whether that is because it is
--- absent or because it is present and raised on the way up.
---
--- `pcall(require, …)` cannot tell those two apart, and this report used to
--- call both "not installed". Measured against a plugin whose `init.lua` is a
--- bare `error(…)`: `pcall(require, …)` returns false, exactly as for a name
--- that is nowhere on the runtimepath, while `vim.loader.find` returns one path
--- against zero. The distinction is the whole advice line -- "install it" is an
--- hour wasted on something that is already installed.
---@param modname string
---@return "ok"|"broken"|"missing"
local function module_state(modname)
  if pcall(require, modname) then
    return "ok"
  end
  local found_ok, found = pcall(vim.loader.find, modname)
  if found_ok and type(found) == "table" and #found > 0 then
    return "broken"
  end
  return "missing"
end

---@internal
--- Run one section, turning its failure into a line in the report instead of
--- the end of the report.
---
--- Measured with one integration adapter whose `report()` throws: `check()`
--- emitted 18 lines and stopped, `:checkhealth lsp` printed "Failed to run
--- healthcheck" under `Ecosystem`, and the Diagnostics and Per-buffer sections
--- never ran at all. A health check that dies on the first broken module is
--- useless in precisely the case it exists for. Same blast-radius rule as
--- `lsp.init`'s `step()`, for the same reason.
---@param label string
---@param fn fun(): nil
---@return nil
local function section(label, fn)
  health.start(label)
  local ok, err = pcall(fn)
  if not ok then
    health.error(("this section failed: %s"):format(tostring(err)), {
      "The sections after it still ran -- read on.",
      "This is a bug in lsp.nvim or in a module it reports on, not in your config.",
    })
  end
end

---@internal
--- Neovim version and the one dependency the plugin cannot run without.
---@return nil
local function check_environment()
  if vim.fn.has("nvim-0.11") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.11+ required, found " .. tostring(vim.version()), {
      "Upgrade Neovim to 0.11+",
    })
  end

  local lib = module_state("lib.nvim.bindings.keymap")
  if lib == "ok" then
    health.ok("lib.nvim available")
  elseif lib == "broken" then
    health.error("lib.nvim is on the runtimepath but failed to load", {
      "It is installed -- reinstalling is not the fix. Something in it raised "
        .. "while loading, so every `:Lsp` route and keymap built on it is gone.",
      'Run `:lua require("lib.nvim.bindings.keymap")` to see the error itself.',
    })
  else
    health.error("lib.nvim missing", {
      "lsp.nvim depends on it hard: the `:Lsp` command is built on "
        .. "lib.nvim.bindings.usercmd.composer and will not register without it.",
      'Install it: dependencies = { "StefanBartl/lib.nvim" }',
    })
  end
end

---@internal
--- What setup() did, and anything it had to work around.
---@return nil
local function check_plugin()
  local status = require("lsp").status()

  if not status.initialized then
    health.warn("setup() has not run", {
      'Call require("lsp").setup() -- or use `opts = {}` in your plugin spec.',
    })
    return
  end
  health.ok("setup() has run")

  -- Before the warnings, because the warnings name these layers: reading
  -- "(from .nvim-lsp.json)" is only useful once you know a project file was
  -- found at all, and *which*.
  local layers = status.layers or { preset = "default" }
  if layers.preset == "default" then
    health.info("preset: default")
  else
    health.info(("preset: %q (config/PRESETS.lua)"):format(layers.preset))
  end
  if layers.project ~= nil then
    health.info(("project override: %s"):format(layers.project))
    health.info(
      "  merged over your setup() options; allowed keys: servers, "
        .. "diagnostics, formatter, inlay_hints, lightbulb, attach, "
        .. "workspace, tools, languages"
    )
  end

  for _, warning in ipairs(status.warnings) do
    health.warn(warning)
  end
  if #status.warnings == 0 then
    health.ok("no warnings during setup")
  end

  local cfg = status.config
  if cfg == nil then
    return
  end

  if not cfg.keymaps.enable then
    health.info("keymaps: disabled (keymaps.enable = false)")
  elseif #status.keymaps == 0 then
    health.info(
      ("keymaps: preset %q is empty -- no keys bound (the catalogue fills up in "):format(
        cfg.keymaps.preset
      ) .. "migration phase 3)"
    )
  else
    health.ok(("keymaps: %d bound from preset %q"):format(#status.keymaps, cfg.keymaps.preset))

    -- `requires` is recorded at bind time, not enforced (see
    -- lsp.bindings.keymaps for why). This is where it pays off: a key that is
    -- bound but whose plugin is missing fails only when pressed, which is the
    -- worst moment to find out.
    ---@type table<string, "ok"|"broken"|"missing">
    local seen = {}
    ---@param modname string
    ---@return "ok"|"broken"|"missing"
    local function state_of(modname)
      if seen[modname] == nil then
        seen[modname] = module_state(modname)
      end
      return seen[modname]
    end

    ---@type table<string, string[]>
    local missing = {}
    for _, spec in ipairs(status.keymaps) do
      if spec.requires ~= nil and state_of(spec.requires) ~= "ok" then
        missing[spec.requires] = missing[spec.requires] or {}
        table.insert(missing[spec.requires], spec.lhs)
      end
    end

    -- Sorted, not `pairs`: LuaJIT seeds its string hashes per process, so the
    -- order these came out in changed from run to run. Measured over three
    -- headless runs of the default preset, which is missing exactly two
    -- plugins: "trouble, fzf-lua", then "fzf-lua, trouble", then "trouble,
    -- fzf-lua". A report whose lines move is a report you cannot diff against
    -- the one you pasted into an issue yesterday.
    ---@type string[]
    local plugins = vim.tbl_keys(missing)
    table.sort(plugins)

    for _, plugin in ipairs(plugins) do
      local lhs_list = missing[plugin]
      table.sort(lhs_list)
      if state_of(plugin) == "broken" then
        health.warn(
          ("%d keymap(s) bound for %s, which is installed but failed to load: %s"):format(
            #lhs_list,
            plugin,
            table.concat(lhs_list, ", ")
          ),
          {
            ("Do not reinstall %s -- it is there. Run `:lua require(%q)` for the error."):format(
              plugin,
              plugin
            ),
          }
        )
      else
        health.warn(
          ("%d keymap(s) bound for %s, which is not installed: %s"):format(
            #lhs_list,
            plugin,
            table.concat(lhs_list, ", ")
          ),
          { ("Install %s, or switch them off via keymaps.map."):format(plugin) }
        )
      end
    end
  end

  if not cfg.usrcmds.enable then
    health.info("`:Lsp`: disabled (usrcmds.enable = false)")
  elseif status.usrcmd then
    health.ok("`:Lsp` registered")
  else
    health.error("`:Lsp` failed to register", {
      "The composer refused the route spec, or lib.nvim is missing.",
    })
  end

  health.info(
    ("formatter: on_save = %s, timeout %dms"):format(
      tostring(cfg.formatter.on_save),
      cfg.formatter.timeout_ms
    )
  )
  health.info(
    ("winbar breadcrumb: %s, %s"):format(
      cfg.winbar.enable and "on" or "off",
      cfg.winbar.chips and "chips" or "flat"
    )
  )

  -- The picker `lsa` opens is decided by whether fzf-lua is there, so the
  -- answer is worth printing rather than leaving to be inferred.
  local picker = cfg.code_actions.picker
  if picker == "native" then
    health.info('code actions: native list (code_actions.picker = "native")')
  elseif module_state("fzf-lua") == "ok" then
    health.ok("code actions: fzf-lua picker with a diff preview")
  elseif picker == "fzf-lua" then
    health.warn('code_actions.picker is "fzf-lua" but fzf-lua is not installed', {
      '`lsa` falls back to the native list. Install fzf-lua, or set the picker to "auto".',
    })
  else
    health.info("code actions: native list (fzf-lua is not installed)")
  end
end

---@internal
--- Whether the catalogue's keys still belong to it *right now* -- the
--- question `keymaps_spec.lua`'s "no two entries claim the same lhs" case
--- cannot ask, because that spec only ever sees the catalogue in isolation;
--- nothing else is loaded when it runs. This is the runtime half: did you, or
--- another plugin, bind the same key the catalogue did?
---
--- `lib.nvim.bindings.keymap.conflicts()` already exists for exactly this --
--- its own docstring says so ("Meant for `:checkhealth`") -- and it walks
--- every plugin registered through the same registry plus every direct
--- `keymap.set()` call it recorded, so a collision shows up regardless of
--- which side bound last. Filtered here to conflicts naming `"LSP"`, the
--- plugin name `bindings/keymaps.lua` registers the catalogue under, so this
--- reports on the catalogue specifically rather than on every plugin in the
--- session.
---
--- What it cannot see: a plugin that calls `vim.keymap.set`/
--- `vim.api.nvim_set_keymap` directly and never touches lib.nvim leaves no
--- record for `conflicts()` to find. That gap is inherent to reading the
--- registry rather than re-scanning the live keymap table, and is said here
--- rather than left for the report to imply a completeness it does not have.
---@return nil
local function check_keymap_collisions()
  local ok, keymap = pcall(require, "lib.nvim.bindings.keymap")
  if not ok then
    -- Already reported as missing under "Environment" -- nothing to add here.
    return
  end

  -- Two spellings claim this plugin's keymaps, not one: the catalogue
  -- registers under "LSP" (keymap.register("LSP", ...)), but lib.nvim's
  -- plugin_of() derives a plugin name for any DIRECT (non-register) call --
  -- e.g. rebind_buffer_local()'s defensive gr* re-bind, or the direct
  -- map()/keymap.set() calls under languages/, lspdoctor/, tools/ -- from
  -- the source file's own path, which is the lowercase "lsp" (lua/lsp/...).
  -- A case-sensitive match against "LSP" alone missed every collision
  -- involving one of those direct calls, silently.
  ---@type Lib.Keymap.Conflict[]
  local ours = {}
  for _, c in ipairs(keymap.conflicts()) do
    for _, claimant in ipairs(c.claimants) do
      if claimant.plugin:lower() == "lsp" then
        ours[#ours + 1] = c
        break
      end
    end
  end

  if #ours == 0 then
    health.ok("no keymap collisions -- every catalogue key is claimed once per mode")
    return
  end

  for _, c in ipairs(ours) do
    ---@type string[]
    local who = {}
    for _, claimant in ipairs(c.claimants) do
      who[#who + 1] = claimant.direct and (claimant.src or claimant.plugin)
        or (claimant.plugin .. "." .. claimant.name)
    end
    health.warn(
      ("%s %q claimed by more than one registration: %s"):format(
        c.mode,
        c.lhs,
        table.concat(who, ", ")
      ),
      {
        "One binding wins silently and the other never fires.",
        "Rebind the catalogue entry via keymaps.map, or change the other side.",
      }
    )
  end
end

--- Servers whose cost scales steeply with the number of attached buffers.
---
--- The list is deliberately short and named rather than derived: "heavy" is a
--- property of a specific implementation, not something readable off a client
--- record. These four keep a whole-project model in memory and re-check it per
--- buffer, so twenty attached buffers is a different machine than two. Every
--- other server is cheap enough that a count is not worth a warning.
---@type table<string, true>
local HEAVY_SERVERS = {
  ts_ls = true,
  tsserver = true,
  pyright = true,
  jdtls = true,
  omnisharp = true,
}

--- How many buffers a heavy server has to hold before the count is worth
--- saying out loud. Below this it is a normal working set.
---@type integer
local HEAVY_BUFFER_THRESHOLD = 20

--- How many names a single health line prints before it summarizes the rest.
---@type integer
local LIST_LIMIT = 12

---@internal
--- Render a list of names, capped, so one line cannot swallow the report.
---@param names string[]
---@return string
local function listed(names)
  if #names <= LIST_LIMIT then
    return table.concat(names, ", ")
  end
  return table.concat(vim.list_slice(names, 1, LIST_LIMIT), ", ")
    .. (", +%d more"):format(#names - LIST_LIMIT)
end

---@internal
--- The buffer the user was looking at when they ran `:checkhealth`.
---
--- Deliberately not `nvim_get_current_buf()`. Neovim creates the `health://`
--- buffer and makes it current *before* it runs a single check (see
--- `vim/health.lua`), so during a check the current buffer is always the
--- report itself -- and its filetype is not set to `checkhealth` until
--- afterwards, so that is not a usable test either. The buffer the user came
--- from is the alternate one.
---
--- Returns nil rather than a guess when there is no real file buffer to point
--- at: "attached here: 0" would read as a problem, and it would be an artefact
--- of how the report was opened.
---
--- The alternate buffer only survives the *first* `:checkhealth` of a session.
--- Measured over three runs in one headless session with one file open:
--- pass 1 got `bufnr("#") == 1` and reported "attached to real.lua: 1 of 1
--- running client(s) -- lua_ls"; passes 2 and 3 got `bufnr("#") == -1` -- each
--- run wipes the previous `health://` buffer and leaves the window without an
--- alternate -- and reported "unknown -- no file buffer to report on", with the
--- file still loaded and the client still attached to it. So a second opinion
--- falls back to the last used listed file buffer, and says that it did: with
--- two files opened a second apart `lastused` ties, and a tie broken by buffer
--- number is a guess, however deterministic.
---@return integer|nil bufnr
---@return boolean exact # false when `bufnr` is the fallback, not the caller's buffer.
local function source_buffer()
  ---@param bufnr integer
  ---@return boolean
  local function is_file_buffer(bufnr)
    return bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == ""
  end

  local current = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(current) ~= "health://" then
    -- Called as a plain function rather than through `:checkhealth`; then the
    -- current buffer really is the caller's.
    return current, true
  end

  local alternate = vim.fn.bufnr("#")
  if is_file_buffer(alternate) then
    return alternate, true
  end

  ---@type integer|nil
  local best = nil
  ---@type integer
  local best_used = -1
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if
      info.name ~= ""
      and is_file_buffer(info.bufnr)
      and (
        best == nil
        or info.lastused > best_used
        or (info.lastused == best_used and info.bufnr > best)
      )
    then
      best, best_used = info.bufnr, info.lastused
    end
  end
  if best == nil then
    return nil, false
  end
  return best, false
end

---@internal
--- LSP servers Mason has installed, whether or not `setup()` configured them.
---
--- Mason's package names are not lspconfig's server names
--- (`lua-language-server` against `lua_ls`), and the mapping between them
--- lives in mason-lspconfig, which this plugin deliberately does not depend on
--- (see `lsp.integrations.mason`). So this reports Mason's names and says so,
--- rather than guessing a translation -- a wrong "installed but not set up"
--- list would be worse than no list.
---@return string[]|nil names # nil when the answer is unavailable, not when it is empty.
---@return string|nil unavailable # Why, when `names` is nil.
local function mason_lsp_packages()
  local ok, registry = pcall(require, "mason-registry")
  if not ok then
    return nil, "mason.nvim is not installed"
  end

  local ok_list, packages = pcall(registry.get_installed_packages)
  if not (ok_list and type(packages) == "table") then
    return nil, "mason-registry did not answer"
  end

  ---@type string[]
  local names = {}
  local categorized = 0
  for _, pkg in ipairs(packages) do
    local categories = (pkg.spec or {}).categories or {}
    if #categories > 0 then
      categorized = categorized + 1
    end
    if vim.tbl_contains(categories, "LSP") then
      names[#names + 1] = pkg.name
    end
  end

  -- A package's categories are hydrated from the registry index, which is only
  -- loaded once `mason.setup()` has run. Without it every package looks
  -- uncategorized, and reporting "0 LSP servers installed" next to 70 present
  -- packages would be a plain lie.
  if #packages > 0 and categorized == 0 then
    return nil, ("mason has %d package(s) but its registry is not loaded yet"):format(#packages)
  end

  table.sort(names)
  return names, nil
end

---@internal
--- Installed versus configured versus set up versus attached -- here, and in
--- total. The gaps between those four are what one wants to see when a server
--- "does not work", and the last two are also the cost picture: an installed
--- server that is attached to nothing costs nothing. What costs is a heavy
--- server held open over many buffers.
---@return nil
local function check_servers()
  local status = require("lsp").status()
  local configured = status.config and status.config.servers or {}

  if not status.initialized then
    health.info("setup() has not run; nothing configured")
    return
  end

  local installed, unavailable = mason_lsp_packages()
  if installed == nil then
    health.info(("installed (mason): unknown -- %s"):format(unavailable))
  elseif #installed == 0 then
    health.info("installed (mason): no LSP package")
  else
    health.info(
      ("installed (mason): %d LSP package(s) -- %s"):format(#installed, listed(installed))
    )
    if #installed > #configured then
      -- Not a warning, and the caveat is in the message rather than beside it:
      -- `vim.health.info` takes no advice lines, only warn and error do, so a
      -- second argument here would be silently dropped. An installed server
      -- that nothing sets up is idle on disk, not a problem -- this line exists
      -- so the number above is not mistaken for something running.
      health.info(
        ("%d more package(s) installed than configured -- they sit on disk, not running. "):format(
          #installed - #configured
        )
          .. "(Mason names packages differently from lspconfig -- `lua-language-server` "
          .. "vs. `lua_ls` -- so the two lists do not line up name for name.)"
      )
    end
  end

  health.info(("configured: %d (%s)"):format(#configured, table.concat(configured, ", ")))

  if #status.servers == 0 then
    health.error("no server was set up", {
      "Every configured name failed to resolve to an `lsp.servers.<name>` module,",
      "or its setup() threw. The reasons are in the warnings above.",
    })
  elseif #status.servers < #configured then
    ---@type table<string, true>
    local ok_set = {}
    for _, name in ipairs(status.servers) do
      ok_set[name] = true
    end
    ---@type string[]
    local missing = {}
    for _, name in ipairs(configured) do
      if not ok_set[name] then
        missing[#missing + 1] = name
      end
    end
    health.warn(
      ("set up %d of %d; missing: %s"):format(
        #status.servers,
        #configured,
        table.concat(missing, ", ")
      ),
      { "See the setup warnings above for why each name failed to resolve" }
    )
  else
    health.ok(("set up: %d"):format(#status.servers))
  end

  local clients = vim.lsp.get_clients()
  if #clients == 0 then
    health.info("no client attached to any buffer (expected until a matching file is opened)")
    return
  end

  local source, exact = source_buffer()
  if source == nil then
    health.info("attached to this buffer: unknown -- no file buffer to report on")
  else
    ---@type string[]
    local here = {}
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = source })) do
      here[#here + 1] = client.name
    end
    table.sort(here)

    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(source), ":t")
    if name == "" then
      name = "buffer " .. source
    end
    if not exact then
      name = name .. " (last used file buffer)"
    end
    if #here == 0 then
      health.info(("attached to %s: none of the %d running client(s)"):format(name, #clients))
    else
      health.ok(
        ("attached to %s: %d of %d running client(s) -- %s"):format(
          name,
          #here,
          #clients,
          table.concat(here, ", ")
        )
      )
    end
  end

  for _, client in ipairs(clients) do
    local buffers = vim.tbl_keys(client.attached_buffers or {})
    local line = ("%s (id %d): %d buffer(s), root %s"):format(
      client.name,
      client.id,
      #buffers,
      client.root_dir or "-"
    )

    -- The only case worth a warning. A count alone is not one: five buffers on
    -- ts_ls is a working set, forty is a machine getting slower for a reason
    -- nothing on screen explains.
    if HEAVY_SERVERS[client.name] and #buffers >= HEAVY_BUFFER_THRESHOLD then
      local lines = 0
      for _, bufnr in ipairs(buffers) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
          lines = lines + vim.api.nvim_buf_line_count(bufnr)
        end
      end
      health.warn(line, {
        ("%s keeps a whole-project model in memory and re-checks it per buffer; "):format(
          client.name
        ) .. ("it is holding %d buffer(s), %d line(s) in total."):format(#buffers, lines),
        "Close what you are not working in, or `:Lsp stop "
          .. client.name
          .. "` where you do "
          .. "not need it. Nothing is broken -- this is the cost, stated.",
      })
    else
      health.ok(line)
    end
  end
end

---@internal
--- The plugins around the umbrella, straight from the adapter registry.
---
--- This used to be a hardcoded list here, which meant the set of plugins the
--- umbrella cares about was written down twice -- and two lists drift. There is
--- one adapter per plugin now, and each answers for itself.
---@return nil
local function check_ecosystem()
  local rows = require("lsp.integrations").report()
  if #rows == 0 then
    health.warn("no integration adapter loaded", { "Reinstall lsp.nvim" })
    return
  end

  for _, row in ipairs(rows) do
    local line = ("%s -- %s"):format(row.plugin, row.note)
    if row.available then
      health.ok(line)
    elseif row.hard then
      health.error(line .. " [missing]")
    else
      health.info(line .. " [not installed]")
    end
  end
end

---@internal
--- Who contributed to `vim.diagnostic.config()`.
---
--- The surface has no notion of an owner -- every caller merges into the same
--- table and the last one wins per key, silently. lsp.nvim owns the call
--- (`lsp.core.diagnostics`), so this is the one place that can answer "where
--- did this icon come from".
---@return nil
local function check_diagnostics()
  local ok_mod, diag = pcall(require, "lsp.core.diagnostics")
  if not ok_mod then
    health.error("lsp.core.diagnostics did not load", { "Reinstall lsp.nvim" })
    return
  end

  if diag.applied() == nil then
    health.warn("vim.diagnostic.config() has not been applied", {
      "lsp.setup() has not run, or it failed before the diagnostic step",
    })
  else
    health.ok("vim.diagnostic.config() applied once, from lsp.core.diagnostics")
  end

  for _, src in ipairs(diag.sources()) do
    local keys = vim.tbl_keys(src.spec)
    table.sort(keys)
    health.info(("%s -- %s"):format(src.name, table.concat(keys, ", ")))
  end

  -- Anything still calling the API directly is invisible from here; naming
  -- the symptom is the most this report can honestly do about it.
  health.info(
    "A plugin that calls vim.diagnostic.config() itself is not listed above "
      .. "and will silently override these per key. Have it call "
      .. "lsp.core.diagnostics.contribute(name, spec) instead."
  )
end

---@internal
--- Point at the per-buffer diagnosis rather than repeating it.
---@return nil
local function check_doctor()
  if has("lsp.lspdoctor") then
    -- Read from `MODES`, not spelled out here. This line used to name five
    -- modes and omit `probe` -- the one a user would not guess, and the only
    -- one that answers "are diagnostics actually arriving". It was the single
    -- place in the plugin that wrote the list by hand; `bindings/usrcmds.lua`
    -- and `lspdoctor/init.lua` both pass `MODES` to the command composer, which
    -- is why their completion stayed right while this went stale.
    --
    -- Checked rather than assumed to be a list: a module can answer a field
    -- read with something other than data. The suite's `inert()` stub returns a
    -- function for *every* key, so `MODES` came back callable and
    -- `table.concat` raised -- taking the whole section down and, with it, the
    -- advisory line below that a neighbouring case asserts. When the list
    -- cannot be read, say less rather than inventing one.
    local ok_modes, doctor = pcall(require, "lsp.lspdoctor")
    local modes = ok_modes and type(doctor) == "table" and doctor.MODES or nil
    if type(modes) == "table" and vim.islist(modes) and #modes > 0 then
      health.ok(("`:LspDoctor %s` available"):format(table.concat(modes, "|")))
    else
      health.ok("`:LspDoctor` available")
    end
    health.info("This report covers the plugin; :LspDoctor covers the current buffer.")
  else
    health.warn("lsp.lspdoctor did not load", { "Reinstall lsp.nvim" })
  end
end

--- Entry point for `:checkhealth lsp`.
---@return nil
function M.check()
  section("Environment", check_environment)
  section("lsp.nvim", check_plugin)
  section("Keymap collisions", check_keymap_collisions)
  section("Servers", check_servers)
  section("Ecosystem", check_ecosystem)
  section("Diagnostics", check_diagnostics)
  section("Per-buffer diagnosis", check_doctor)
end

return M
