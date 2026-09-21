--- The adapters themselves, rather than the registry that calls them.
---
--- `integrations_spec.lua` pins the contract the registry enforces -- a broken
--- adapter is recorded, never propagated. The cases here are about what an
--- adapter does while it is *working*: what it hands back, whose tables it
--- touches on the way, and whether the opt-outs and fallbacks it documents are
--- the ones it actually has.
---
--- Every case was reproduced against the adapter before it was fixed; the
--- comment above each one carries the measurement rather than a description.

describe("lsp.integrations.blink", function()
  local saved

  before_each(function()
    saved = package.loaded["blink.cmp"]
    package.loaded["blink.cmp"] = nil
    package.loaded["lsp.integrations.blink"] = nil
  end)

  after_each(function()
    package.loaded["blink.cmp"] = saved
    package.loaded["lsp.integrations.blink"] = nil
  end)

  --- Every table reachable from `root`, by identity, mapped to its path.
  ---@param root table
  ---@param label string
  ---@return table<table, string>
  local function nodes(root, label)
    ---@type table<table, string>
    local out = {}
    local function walk(t, path)
      if out[t] then
        return
      end
      out[t] = path
      for k, v in pairs(t) do
        if type(v) == "table" then
          walk(v, path .. "." .. tostring(k))
        end
      end
    end
    walk(root, label)
    return out
  end

  --- Paths in `subject` that are the very same table as something in `owned`.
  ---@param subject table
  ---@param owned table<table, string>
  ---@return string[]
  local function shared_with(subject, owned)
    ---@type string[]
    local hits = {}
    for node, path in pairs(nodes(subject, "result")) do
      if owned[node] then
        hits[#hits + 1] = path .. " is " .. owned[node]
      end
    end
    table.sort(hits)
    return hits
  end

  -- `vim.tbl_deep_extend` assigns a subtable by *reference* whenever the
  -- destination has no key of that name, so merging the mirrored `CAPS`
  -- constant straight in handed the result nodes of the constant itself.
  --
  -- Measured on the real path, not just on `capabilities({})`:
  -- `core.capabilities.get()` over `integrations.capability_contributors()`
  -- returned a table whose
  -- `textDocument.completion.completionItem.insertTextModeSupport` -- and that
  -- table's own `valueSet` -- were `blink._CAPS`'s. One write into the
  -- capabilities anywhere downstream changed the constant for the rest of the
  -- session, and `_CAPS` is what the drift test in `integrations_spec.lua`
  -- compares against the real blink, so the damage would have been invisible
  -- in exactly the place built to notice it.
  it("hands back capabilities that share no table with its mirrored constant", function()
    local blink = require("lsp.integrations.blink")
    local owned = nodes(blink._CAPS, "_CAPS")

    assert.are.same({}, shared_with(blink.capabilities({}), owned))
    assert.are.same(
      {},
      shared_with(blink.capabilities(vim.lsp.protocol.make_client_capabilities()), owned)
    )

    local merged =
      require("lsp.core.capabilities").get(require("lsp.integrations").capability_contributors())
    assert.are.same({}, shared_with(merged, owned))
  end)

  -- And the constant really is unreachable, not merely copied one level down.
  it("cannot have its mirrored constant rewritten through the merged table", function()
    local blink = require("lsp.integrations.blink")
    local before = blink._CAPS.textDocument.completion.completionItem.snippetSupport

    local caps = blink.capabilities({})
    caps.textDocument.completion.completionItem.snippetSupport = not before
    caps.textDocument.completion.completionItem.insertTextModeSupport.valueSet = { 99 }

    assert.are.equal(
      before,
      blink._CAPS.textDocument.completion.completionItem.snippetSupport,
      "writing into the merged capabilities rewrote the module constant"
    )
    assert.are.same(
      { 1 },
      blink._CAPS.textDocument.completion.completionItem.insertTextModeSupport.valueSet
    )
  end)

  -- The mirror exists so that capabilities never have to load blink. An
  -- installed-but-broken blink is the case it is worth the most in, and it was
  -- the one case that could not reach it: `blink_if_loaded()` accepted any
  -- module carrying a `get_lsp_capabilities` function and called it
  -- unguarded. Measured with a `get_lsp_capabilities` that raises: the
  -- contributor threw, `core.capabilities.get()` recorded "capability
  -- contributor failed" and moved on, and the session ran with no blink
  -- completion capabilities at all -- finding B1's silent fallback, reached
  -- from the other side.
  it("falls back to the mirror when a loaded blink raises", function()
    package.loaded["blink.cmp"] = {
      get_lsp_capabilities = function()
        error("blink is half-installed")
      end,
    }

    local caps, warnings = require("lsp.integrations.blink").capabilities({})

    assert.are.equal("table", type(caps))
    assert.is_not_nil(
      caps.textDocument.completion.completionItem.insertTextModeSupport,
      "the contribution was lost instead of coming from the mirror"
    )
    assert.is_true(#(warnings or {}) > 0, "the broken plugin was not recorded")
  end)

  it("falls back to the mirror when a loaded blink answers with nil", function()
    package.loaded["blink.cmp"] = {
      get_lsp_capabilities = function()
        return nil
      end,
    }

    local caps, warnings = require("lsp.integrations.blink").capabilities({})

    assert.are.equal("table", type(caps))
    assert.is_not_nil(caps.textDocument.completion.completionItem.insertTextModeSupport)
    assert.is_true(#(warnings or {}) > 0)
  end)

  -- The fallback must not have become the only path: a blink that works still
  -- wins, silently.
  it("still prefers a loaded blink that works", function()
    package.loaded["blink.cmp"] = {
      get_lsp_capabilities = function()
        return { textDocument = { completion = { from_real_blink = true } } }
      end,
    }

    local caps, warnings = require("lsp.integrations.blink").capabilities({})

    assert.is_true(caps.textDocument.completion.from_real_blink)
    assert.are.equal(0, #(warnings or {}))
  end)
end)

describe("lsp.integrations.nvchad", function()
  local saved

  before_each(function()
    saved = package.loaded["nvchad.configs.lspconfig"]
    package.loaded["lsp.integrations.nvchad"] = nil
  end)

  after_each(function()
    package.loaded["nvchad.configs.lspconfig"] = saved
    package.loaded["lsp.integrations.nvchad"] = nil
  end)

  -- Same reference-assignment trap as blink's, pointed at a module this plugin
  -- does not own. Measured: after one write into the capabilities this adapter
  -- returned, `nvchad.configs.lspconfig.capabilities` carried the new value
  -- too -- a bridge that edits the thing it bridges to.
  it("does not edit NvChad's own capabilities table", function()
    package.loaded["nvchad.configs.lspconfig"] = {
      capabilities = { textDocument = { nvchad = { deep = { value = 1 } } } },
    }

    local caps = require("lsp.integrations.nvchad").capabilities({})
    caps.textDocument.nvchad.deep.value = 99

    assert.are.equal(
      1,
      package.loaded["nvchad.configs.lspconfig"].capabilities.textDocument.nvchad.deep.value
    )
  end)
end)

describe("lsp.integrations.menu", function()
  local saved

  before_each(function()
    saved = { cfg = package.loaded["lsp.config"], lsp = package.loaded["lsp"] }
    package.loaded["lsp.integrations.menu"] = nil
  end)

  after_each(function()
    package.loaded["lsp.config"] = saved.cfg
    package.loaded["lsp"] = saved.lsp
    package.loaded["lsp.integrations.menu"] = nil
  end)

  ---@param name string
  ---@return table
  local function entry(name)
    return { name = name, desc = name, lhs = "<leader>x", rhs = "<cmd>echo 1<cr>" }
  end

  ---@param menu_cfg any
  ---@param names string[]
  local function stub(menu_cfg, names)
    package.loaded["lsp.config"] = {
      get = function()
        return { menu = menu_cfg }
      end,
    }
    ---@type table[]
    local keymaps = {}
    for _, n in ipairs(names) do
      keymaps[#keymaps + 1] = entry(n)
    end
    package.loaded["lsp"] = {
      status = function()
        return { keymaps = keymaps }
      end,
    }
    package.loaded["lsp.integrations.menu"] = nil
    return require("lsp.integrations.menu")
  end

  -- The guard read `if mcfg and mcfg.enable == false`, which sends a plain
  -- `menu = false` -- the shortest way anyone writes "off" -- down the
  -- *enabled* branch, because `false and …` is false. Measured with
  -- `lsp.config.get()` answering `{ menu = false }` against the default
  -- preset: four fly-out groups came back where the opt-out asked for none.
  --
  -- `config/init.lua` normalizes `menu` to a table (and warns), so nothing
  -- in-tree reaches the guard with a boolean today. That is the config layer
  -- holding a line the guard does not, which is why this is pinned here rather
  -- than left to the normalizer: the two are in different files and only one
  -- of them says what it means.
  it("honours menu = false, not just menu.enable = false", function()
    local menu = stub(false, { "goto_definition", "rename" })
    assert.are.same({}, menu.items())
  end)

  it("still honours menu.enable = false", function()
    local menu = stub({ enable = false }, { "goto_definition", "rename" })
    assert.are.same({}, menu.items())
  end)

  it("still builds entries when the menu is enabled", function()
    local menu = stub({ enable = true }, { "goto_definition", "rename" })
    assert.is_true(#menu.items() > 0)
  end)

  -- `code_action_range` is `code_action`'s Visual-mode key: the same action on
  -- another lhs, which is what the skip list is for. Listed, the menu would
  -- offer "Code action" twice.
  it("lists the code action once, not once per key", function()
    local menu = stub({ enable = true }, { "code_action", "code_action_range" })
    local count = 0
    for _, group in ipairs(menu.items()) do
      count = count + #group.items
    end
    assert.are.equal(1, count)
  end)

  -- `group_of` derives the fly-out from the entry's name, and the module
  -- header states that as the reason there is no second hand-maintained
  -- lookup table: an entry following the convention groups correctly.
  -- Measured against the default preset, it did not -- "Navigation" came back
  -- with 15 children, five of which navigate nowhere: both inlay-hint
  -- toggles, both lightbulb toggles, and `workspace_folder_add`.
  it("does not file the toggles and the workspace action under Navigation", function()
    local menu = stub({ enable = true }, {
      "goto_definition",
      "hints_toggle",
      "hints_toggle_filetype",
      "lightbulb_toggle",
      "lightbulb_toggle_filetype",
      "workspace_folder_add",
    })

    ---@type table<string, integer>
    local sizes = {}
    for _, group in ipairs(menu.items()) do
      sizes[vim.trim(group.name)] = #group.items
    end

    assert.are.equal(1, sizes["Navigation"], "Navigation collected entries that are not one")
    assert.are.equal(4, sizes["Toggles"])
    assert.are.equal(1, sizes["Workspace"])
  end)
end)

describe("lsp.integrations.mason.ensure_install defaults", function()
  local saved

  before_each(function()
    saved = {
      registry = package.loaded["mason-registry"],
      mason = package.loaded["mason"],
      mod = package.loaded["lsp.integrations.mason.ensure_install"],
    }
  end)

  after_each(function()
    package.loaded["mason-registry"] = saved.registry
    package.loaded["mason"] = saved.mason
    package.loaded["lsp.integrations.mason.ensure_install"] = saved.mod
  end)

  -- Names checked against the installed registry index
  -- (2026-07-16-tangy-mantle, 584 packages). `rustfmt` shipped enabled in the
  -- formatter defaults and is not a Mason package at all -- it is a rustup
  -- component -- so `registry.get_package("rustfmt")` raised and every single
  -- run of `ensure_install` ended its summary with
  -- `unknown: [formatters] rustfmt (not in registry)`. A name that can never
  -- install is worse than an absent one: it is a line of the report that asks
  -- to be acted on and cannot be.
  --
  -- The list is what was *verified missing*, not a guess. Anything added to it
  -- later should be verified the same way before it goes in.
  it("asks Mason for no package the registry cannot resolve", function()
    ---@type table<string, boolean>
    local NOT_IN_REGISTRY = {
      ["rustfmt"] = true,
      ["node-debug2-adapter"] = true,
      ["systemd-language-server"] = true,
      ["astro-ls"] = true,
      ["dart-language-server"] = true,
    }

    ---@type string[]
    local asked = {}
    package.loaded["mason"] = { setup = function() end }
    package.loaded["mason-registry"] = {
      refresh = function(cb)
        if cb then
          cb()
        end
      end,
      get_package = function(name)
        asked[#asked + 1] = name
        return {
          is_installed = function()
            return true
          end,
        }
      end,
    }

    package.loaded["lsp.integrations.mason.ensure_install"] = nil
    require("lsp.integrations.mason.ensure_install").enable({})

    ---@type string[]
    local unresolvable = {}
    for _, name in ipairs(asked) do
      if NOT_IN_REGISTRY[name] then
        unresolvable[#unresolvable + 1] = name
      end
    end
    table.sort(unresolvable)

    assert.is_true(#asked > 0, "nothing was resolved at all, so the check below proves nothing")
    assert.are.same({}, unresolvable)
  end)
end)
