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
--- Neovim version and the one dependency the plugin cannot run without.
---@return nil
local function check_environment()
  health.start("Environment")

  if vim.fn.has("nvim-0.11") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.11+ required, found " .. tostring(vim.version()))
  end

  if has("lib.nvim.bindings.keymap") then
    health.ok("lib.nvim available")
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
  health.start("lsp.nvim")

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
    health.info(("project override: %s"):format(layers.project), {
      "Merged over your setup() options. Allowed keys: servers, diagnostics, "
        .. "formatter, inlay_hints, lightbulb, attach, workspace, tools, languages.",
    })
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
    ---@type table<string, string[]>
    local missing = {}
    for _, spec in ipairs(status.keymaps) do
      if spec.requires ~= nil and not has(spec.requires) then
        missing[spec.requires] = missing[spec.requires] or {}
        table.insert(missing[spec.requires], spec.lhs)
      end
    end
    for plugin, lhs_list in pairs(missing) do
      table.sort(lhs_list)
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
---@return integer|nil bufnr
local function source_buffer()
  local current = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(current) ~= "health://" then
    -- Called as a plain function rather than through `:checkhealth`; then the
    -- current buffer really is the caller's.
    return current
  end

  local alternate = vim.fn.bufnr("#")
  if alternate <= 0 or not vim.api.nvim_buf_is_loaded(alternate) then
    return nil
  end
  if vim.bo[alternate].buftype ~= "" then
    return nil
  end
  return alternate
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
  health.start("Servers")

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
      )
    )
  else
    health.ok(("set up: %d"):format(#status.servers))
  end

  local clients = vim.lsp.get_clients()
  if #clients == 0 then
    health.info("no client attached to any buffer (expected until a matching file is opened)")
    return
  end

  local source = source_buffer()
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
  health.start("Ecosystem")

  local rows = require("lsp.integrations").report()
  if #rows == 0 then
    health.warn("no integration adapter loaded")
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
--- Point at the per-buffer diagnosis rather than repeating it.
---@return nil
local function check_doctor()
  health.start("Per-buffer diagnosis")

  if has("lsp.lspdoctor") then
    health.ok("`:LspDoctor startup|resolve|buffer|capabilities|all` available")
    health.info("This report covers the plugin; :LspDoctor covers the current buffer.")
  else
    health.warn("lsp.lspdoctor did not load")
  end
end

--- Entry point for `:checkhealth lsp`.
---@return nil
function M.check()
  check_environment()
  check_plugin()
  check_servers()
  check_ecosystem()
  check_doctor()
end

return M
