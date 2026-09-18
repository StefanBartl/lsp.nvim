--- Covers three user-command wiring modules that had no dedicated coverage:
--- `lsp.usercmds.formatter` (dispatch onto whichever formatter module the
--- caller hands in), `lsp.usercmds.workspace_diagnostics` (the runtime
--- toggle commands over `lsp.core.workspace_diagnostics`), and
--- `lsp.usercmds.mobile_diagnostics` (the pure environment probe behind
--- `:LspMobileDiagnostics`).
---
--- All three are thin: what is worth pinning is that each `:Lsp*` command
--- reaches exactly the collaborator function it is named for, with the
--- arguments it promises, and that the probe's branches read the
--- environment it claims to read rather than a stale snapshot.

---@param fn fun(): nil
---@return string[] # every message vim.notify saw, in order
local function messages_of(fn)
  local seen = {}
  local original = vim.notify
  vim.notify = function(msg)
    seen[#seen + 1] = tostring(msg)
  end
  local ok, err = pcall(fn)
  vim.notify = original
  assert(ok, err)
  return seen
end

describe("lsp.usercmds.formatter", function()
  ---@type table
  local calls

  --- Attach against a fresh stub formatter and return it.
  ---@return table stub
  local function attach()
    calls = { format = {}, toggle = 0, enable = 0, disable = 0 }
    -- Declared, then assigned, as two statements: a local's own scope only
    -- begins after its declaring statement ends, so `is_enabled` below would
    -- otherwise close over an undefined global `stub` instead of this table.
    local stub
    stub = {
      enabled = false,
      format = function(bufnr)
        calls.format[#calls.format + 1] = bufnr
      end,
      toggle = function()
        calls.toggle = calls.toggle + 1
      end,
      enable = function()
        calls.enable = calls.enable + 1
      end,
      disable = function()
        calls.disable = calls.disable + 1
      end,
      is_enabled = function()
        return stub.enabled
      end,
    }
    require("lsp.usercmds.formatter").attach(stub)
    return stub
  end

  after_each(function()
    package.loaded["lsp.formatter.conform"] = nil
    package.preload["lsp.formatter.conform"] = nil
  end)

  it("registers every documented subcommand", function()
    attach()
    for _, cmd in ipairs({
      "LspFormat",
      "LspFormatToggle",
      "LspFormatOn",
      "LspFormatOff",
      "LspFormatStatus",
      "LspFormatWhich",
    }) do
      assert.are.equal(2, vim.fn.exists(":" .. cmd), cmd .. " should be registered")
    end
  end)

  it(":LspFormat formats the current buffer (0), not a captured one", function()
    attach()
    vim.cmd("LspFormat")

    assert.are.same({ 0 }, calls.format)
  end)

  it(":LspFormatToggle/-On/-Off reach the matching formatter function", function()
    local stub = attach()
    vim.cmd("LspFormatToggle")
    vim.cmd("LspFormatOn")
    vim.cmd("LspFormatOff")

    assert.are.equal(1, calls.toggle)
    assert.are.equal(1, calls.enable)
    assert.are.equal(1, calls.disable)
    assert.is_not_nil(stub) -- the stub itself is unchanged by attach()
  end)

  it(":LspFormatStatus reports the formatter's own is_enabled()", function()
    local stub = attach()
    stub.enabled = true

    local seen = messages_of(function()
      vim.cmd("LspFormatStatus")
    end)

    assert.are.equal(1, #seen)
    assert.is_truthy(seen[1]:find("true", 1, true))
  end)

  it(":LspFormatWhich calls conform's which() when conform loads", function()
    attach()
    local which_calls = {}
    package.loaded["lsp.formatter.conform"] = {
      which = function(bufnr)
        which_calls[#which_calls + 1] = bufnr
      end,
    }

    vim.cmd("LspFormatWhich")

    assert.are.same({ 0 }, which_calls)
  end)

  it(":LspFormatWhich warns instead of raising when conform cannot load", function()
    attach()
    package.loaded["lsp.formatter.conform"] = nil
    package.preload["lsp.formatter.conform"] = function()
      error("conform not installed")
    end

    local seen = messages_of(function()
      vim.cmd("LspFormatWhich")
    end)

    assert.are.equal(1, #seen)
    assert.is_truthy(seen[1]:find("unavailable", 1, true))
  end)
end)

describe("lsp.usercmds.workspace_diagnostics", function()
  ---@type table
  local calls

  --- Attach `lsp.usercmds.workspace_diagnostics` against a fresh stub of
  --- `lsp.core.workspace_diagnostics`, installed in `package.loaded` before
  --- `M.attach()` runs its own (call-time, not load-time) `require`.
  ---@param overrides table|nil
  ---@return nil
  local function attach(overrides)
    calls = { toggle = 0, set = {} }
    -- Same two-statement split as the formatter stub above, and for the same
    -- reason: `enabled` closes over `wd`, which must already be the local
    -- being built here, not an undefined global of the same name.
    local wd
    wd = vim.tbl_extend("force", {
      enabled_value = false,
      toggle = function()
        calls.toggle = calls.toggle + 1
      end,
      set = function(v)
        calls.set[#calls.set + 1] = v
      end,
      enabled = function()
        return wd.enabled_value
      end,
      populate_now = function()
        return true, 2
      end,
    }, overrides or {})
    package.loaded["lsp.core.workspace_diagnostics"] = wd
    require("lsp.usercmds.workspace_diagnostics").attach()
  end

  after_each(function()
    package.loaded["lsp.core.workspace_diagnostics"] = nil
  end)

  it("registers every documented subcommand", function()
    attach()
    for _, cmd in ipairs({
      "LspWorkspaceDiagnosticsToggle",
      "LspWorkspaceDiagnosticsOn",
      "LspWorkspaceDiagnosticsOff",
      "LspWorkspaceDiagnosticsStatus",
      "LspWorkspaceDiagnosticsNow",
    }) do
      assert.are.equal(2, vim.fn.exists(":" .. cmd), cmd .. " should be registered")
    end
  end)

  it(":LspWorkspaceDiagnosticsToggle calls wd.toggle()", function()
    attach()
    vim.cmd("LspWorkspaceDiagnosticsToggle")
    assert.are.equal(1, calls.toggle)
  end)

  it(":LspWorkspaceDiagnosticsOn/-Off call wd.set() with the right boolean", function()
    attach()
    vim.cmd("LspWorkspaceDiagnosticsOn")
    vim.cmd("LspWorkspaceDiagnosticsOff")

    assert.are.same({ true, false }, calls.set)
  end)

  it(":LspWorkspaceDiagnosticsStatus reports wd.enabled()", function()
    attach({ enabled_value = true })

    local seen = messages_of(function()
      vim.cmd("LspWorkspaceDiagnosticsStatus")
    end)

    assert.are.equal(1, #seen)
    assert.is_truthy(seen[1]:find("ON", 1, true))
  end)

  it(":LspWorkspaceDiagnosticsNow reports the scheduled client count on success", function()
    attach({
      populate_now = function()
        return true, 3
      end,
    })

    local seen = messages_of(function()
      vim.cmd("LspWorkspaceDiagnosticsNow")
    end)

    assert.are.equal(1, #seen)
    assert.is_truthy(seen[1]:find("3", 1, true))
  end)

  it(":LspWorkspaceDiagnosticsNow reports the failure reason rather than a count", function()
    attach({
      populate_now = function()
        return false, "no LSP clients attached to this buffer"
      end,
    })

    local seen = messages_of(function()
      vim.cmd("LspWorkspaceDiagnosticsNow")
    end)

    assert.are.equal(1, #seen)
    assert.is_truthy(seen[1]:find("no LSP clients attached", 1, true))
  end)
end)

describe("lsp.usercmds.mobile_diagnostics", function()
  local mobile = require("lsp.usercmds.mobile_diagnostics")

  ---@type table
  local saved

  before_each(function()
    saved = {
      executable = vim.fn.executable,
      os_uname = vim.loop.os_uname,
      java_home = vim.env.JAVA_HOME,
      flutter_root = vim.env.FLUTTER_ROOT,
    }
  end)

  after_each(function()
    vim.fn.executable = saved.executable
    vim.loop.os_uname = saved.os_uname
    vim.env.JAVA_HOME = saved.java_home
    vim.env.FLUTTER_ROOT = saved.flutter_root
  end)

  ---@param present table<string, boolean>
  local function stub_executables(present)
    vim.fn.executable = function(name)
      return present[name] and 1 or 0
    end
  end

  ---@param sysname string
  local function stub_platform(sysname)
    vim.loop.os_uname = function()
      return { sysname = sysname }
    end
  end

  it("registers :LspMobileDiagnostics", function()
    mobile.attach()
    assert.are.equal(2, vim.fn.exists(":LspMobileDiagnostics"))
  end)

  it("marks every present executable and reads the real env vars", function()
    stub_executables({
      java = true,
      jdtls = true,
      ["kotlin-language-server"] = true,
      dart = true,
      flutter = true,
    })
    stub_platform("Linux")
    vim.env.JAVA_HOME = "/opt/java"
    vim.env.FLUTTER_ROOT = "/opt/flutter"

    local seen = messages_of(function()
      mobile.run()
    end)

    assert.are.equal(1, #seen)
    local report = seen[1]
    assert.is_truthy(report:find("java: \u{2713}", 1, true))
    assert.is_truthy(report:find("/opt/java", 1, true))
    assert.is_truthy(report:find("dart: \u{2713}", 1, true))
    assert.is_truthy(report:find("/opt/flutter", 1, true))
    assert.is_truthy(report:find("not macOS", 1, true))
  end)

  it("marks a missing executable and an unset env var distinctly", function()
    stub_executables({})
    stub_platform("Linux")
    vim.env.JAVA_HOME = nil
    vim.env.FLUTTER_ROOT = nil

    local seen = messages_of(function()
      mobile.run()
    end)

    local report = seen[1]
    assert.is_truthy(report:find("java: \u{2717}", 1, true))
    assert.is_truthy(report:find("JAVA_HOME: not set", 1, true))
    assert.is_truthy(report:find("FLUTTER_ROOT: not set", 1, true))
  end)

  -- An empty string is a real value some shells leave a variable set to; the
  -- probe should treat it the same as unset rather than printing a blank.
  it("treats an empty-string env var as not set", function()
    stub_executables({})
    stub_platform("Linux")
    vim.env.JAVA_HOME = ""

    local seen = messages_of(function()
      mobile.run()
    end)

    assert.is_truthy(seen[1]:find("JAVA_HOME: not set", 1, true))
  end)

  it("reports macOS and probes sourcekit-lsp only there", function()
    stub_executables({ ["sourcekit-lsp"] = true })
    stub_platform("Darwin")

    local seen = messages_of(function()
      mobile.run()
    end)

    local report = seen[1]
    assert.is_truthy(report:find("macOS \u{2713}", 1, true))
    assert.is_truthy(report:find("sourcekit%-lsp: \u{2713}"))
  end)
end)
