---@module 'lsp.integrations.blink'
---@brief blink.cmp completion capabilities.
---@description
--- The alternative completion engine. Contributes after nvim-cmp so that a
--- setup running both ends up with blink's view of the protocol -- which is
--- the order the original single capabilities function used.
---
--- Silent when absent, unlike the nvim-cmp adapter: blink is the alternative,
--- not the default, so its absence is not evidence of anything. Roadmap
--- section 15 leaves the choice between the two open; when it is made,
--- `completion.engine` belongs here.
---
--- **Why `capabilities()` does not `require("blink.cmp")`.** Capabilities are
--- built during `setup()`, i.e. during Neovim's startup, and under a lazy
--- plugin manager a `require` *is* the load trigger: asking blink for its
--- capability table pulled the whole engine -- config validation, keymaps,
--- fuzzy-binary check -- into every startup (measured: 42-90ms), for a table
--- that is a compile-time constant. `CAPS` below mirrors
--- `blink.cmp.sources.lib.get_lsp_capabilities()`; the real blink is still
--- preferred whenever it happens to be loaded already, and
--- `TESTS/lsp/integrations_spec.lua` fails if the two ever disagree.
---
---@see lsp.integrations
---@see lsp.integrations.cmp

local M = {}

---@type string
M.plugin = "blink.cmp"

---@type boolean
M.hard = false

---@type string
M.note = "completion capabilities (alternative to nvim-cmp)"

--- blink.cmp's own client capabilities, mirrored verbatim from
--- `blink.cmp.sources.lib.get_lsp_capabilities()` (blink 1.x).
---
--- A copy rather than a `require` for the startup-cost reason in the module
--- doc; it stays honest because the spec suite compares it against the real
--- thing whenever blink is installed. If that test fails, blink changed its
--- table -- update this one, do not weaken the test.
---@type lsp.ClientCapabilities
local CAPS = {
  textDocument = {
    completion = {
      completionItem = {
        snippetSupport = true,
        commitCharactersSupport = false,
        documentationFormat = { "markdown", "plaintext" },
        deprecatedSupport = true,
        preselectSupport = false,
        tagSupport = { valueSet = { 1 } },
        insertReplaceSupport = true,
        resolveSupport = {
          properties = {
            "documentation",
            "detail",
            "additionalTextEdits",
            "command",
            "data",
          },
        },
        insertTextModeSupport = {
          valueSet = { 1 },
        },
        labelDetailsSupport = true,
      },
      completionList = {
        itemDefaults = {
          "commitCharacters",
          "editRange",
          "insertTextFormat",
          "insertTextMode",
          "data",
        },
      },
      contextSupport = true,
      insertTextMode = 1,
    },
  },
}

---@internal
--- blink, but only if it is already loaded. Never a `require` -- see the module
--- doc.
---@return table|nil
local function blink_if_loaded()
  local mod = package.loaded["blink.cmp"]
  if type(mod) == "table" and type(mod.get_lsp_capabilities) == "function" then
    return mod
  end
  return nil
end

--- Is blink.cmp installed?
---
--- This one does `require`, and may therefore load the plugin. That is fine
--- here and only here: `available()` is read by `:checkhealth lsp`, which the
--- user asked for, never by the startup path.
---@return boolean
function M.available()
  local ok, mod = pcall(require, "blink.cmp")
  return ok and type(mod) == "table" and type(mod.get_lsp_capabilities) == "function"
end

--- Merge blink.cmp's capabilities in.
---
--- Same shape as blink's own `get_lsp_capabilities(override)`: the incoming
--- `caps` is passed as the override, so a contributor that ran earlier keeps
--- whatever it already decided and blink only fills the gaps.
---@param caps table
---@return table|nil caps
---@return LspCaps.Warning[]|nil warnings
function M.capabilities(caps)
  local mod = blink_if_loaded()
  if mod ~= nil then
    return vim.tbl_deep_extend("force", caps, mod.get_lsp_capabilities(caps)), nil
  end
  return vim.tbl_deep_extend("force", caps, vim.tbl_deep_extend("force", {}, CAPS, caps)), nil
end

--- The mirrored table, for the drift test.
---@private
M._CAPS = CAPS

return M
