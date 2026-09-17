--- The end-to-end gate: does `lspdoctor/probe.lua` catch diagnostics coming
--- back from a *real* language server?
---
--- `lspdoctor_spec.lua` covers the same module against fakes -- namespaces,
--- counts, the silence case, cleanup. Those cases pin the report's behaviour
--- and none of them proves the chain. A fake `vim.diagnostic.get` answers
--- whether or not `didOpen` was ever sent, whether or not a server would
--- accept the buffer, whether or not `buf_attach_client` still works the way
--- it did. Every link of the chain the probe exists to verify is stubbed out
--- in exactly the spec that tests the probe.
---
--- So this file does it for real: start a server, hand it a file it cannot
--- parse, and require an answer.
---
--- ## The skip, and why it is loud
---
--- Not every machine has a language server installed. The case therefore
--- skips -- but a gate that quietly skips itself and still counts as green is
--- worse than no gate, because it reports confidence it never earned. And
--- plenary's `pending` is exactly that shape: it prints `Pending` and the run
--- still tallies the case under `Success`. So the skip:
---
--- * names every server it looked for and what was missing about each,
--- * goes to stderr as well as into plenary's `PENDING` line, so it is visible
---   in a CI log that nobody scrolls through,
--- * **fails instead of skipping under `CI`**, because the workflow installs
---   a server for this case. There, "no server found" is not a machine that
---   happens to lack one, it is a broken workflow -- and it has to be red, or
---   the tally's green is about a gate that never ran,
--- * and applies *only* to "no server here". A server that is present,
---   starts, initializes and then says nothing about a file with a syntax
---   error is a failure, which is the whole point: that is the state this
---   report was written to catch.
---
--- ## Why these three servers
---
--- Each was verified to deliver diagnostics through `probe.run` before being
--- listed, rather than assumed to. Ordered by what they cost: `lua_ls`
--- answered in ~0.8s, `ts_ls` in ~1.1s, `gopls` in ~15s from cold because it
--- loads a module first. The first available one is used; the rest are not
--- tried, since one proven roundtrip answers the question.
---
--- `jsonls` was tried and deliberately left out. It starts, initializes,
--- attaches -- and publishes nothing for `{ "a": }` unless the client answers
--- its `workspace/configuration` request. A candidate that needs the test to
--- configure validation into existence is not evidence that the chain works.
---
---@see lsp.lspdoctor.probe

describe("lsp.lspdoctor.probe (live)", function()
  -- Generous, because a cold `gopls` measured 15s here and a loaded CI runner
  -- is slower still; finite, because a hanging test is worse than a failing
  -- one -- it has no output at all and takes the whole suite with it.
  local INIT_TIMEOUT_MS = 30000
  local PROBE_TIMEOUT_MS = 30000

  --- The servers this gate will run against, cheapest first.
  ---
  --- `needs` is for companions the server cannot work without: `gopls` starts
  --- and initializes with no Go toolchain on PATH and then fails to load the
  --- module, which would read here as "server present, diagnostics missing" --
  --- a failure about the wrong thing. Listing `go` turns that into a skip that
  --- names it.
  ---
  --- `root` files are written before the seed buffer is opened, because
  --- `root_dir` is resolved at start time and a `gopls` without `go.mod` is
  --- outside any module.
  ---@type table[]
  local CANDIDATES = {
    {
      name = "lua_ls",
      bin = "lua-language-server",
      args = {},
      filetype = "lua",
      seed = { file = "probe_seed.lua", lines = { "return {}" } },
      root = {},
    },
    {
      name = "ts_ls",
      bin = "typescript-language-server",
      args = { "--stdio" },
      filetype = "typescript",
      seed = { file = "probe_seed.ts", lines = { "export const probe = 1" } },
      root = {},
    },
    {
      name = "gopls",
      bin = "gopls",
      args = {},
      needs = { "go" },
      filetype = "go",
      seed = { file = "probe_seed.go", lines = { "package main", "", "func main() {}" } },
      root = { ["go.mod"] = { "module lspdoctorprobe", "", "go 1.21" } },
    },
  }

  --- Where a binary is, in a form `uv.spawn` can actually start.
  ---
  --- Not plain `exepath`: on Windows, npm installs both a `foo` shell shim and
  --- a `foo.cmd`, `exepath("foo")` returns the extension-less one, and
  --- spawning it fails with "not installed, missing from PATH, or not
  --- executable" about a server that is installed and on PATH. So the
  --- extensions are tried first there.
  ---
  --- Mason's `bin/` is searched too. It is on PATH in a real session because
  --- mason.nvim puts it there, and it is not here, because nothing in the test
  --- environment loads mason -- a server the user installed through Mason would
  --- otherwise count as absent.
  ---@param bin string
  ---@return string|nil path
  local function resolve(bin)
    local names = { bin }
    if vim.fn.has("win32") == 1 then
      names = { bin .. ".cmd", bin .. ".exe", bin .. ".bat", bin }
    end

    for _, name in ipairs(names) do
      local path = vim.fn.exepath(name)
      if path ~= "" then
        return path
      end
    end

    local mason_bin = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin")
    for _, name in ipairs(names) do
      local path = vim.fs.joinpath(mason_bin, name)
      if vim.fn.executable(path) == 1 then
        return path
      end
    end

    return nil
  end

  --- The first usable candidate, or the reason there is none.
  ---@return table|nil candidate, string[]|nil cmd, string|nil missing
  local function pick()
    local misses = {}
    for _, candidate in ipairs(CANDIDATES) do
      local path = resolve(candidate.bin)
      if path == nil then
        misses[#misses + 1] = ("%s (`%s` not found)"):format(candidate.name, candidate.bin)
      else
        local lacks = nil
        for _, companion in ipairs(candidate.needs or {}) do
          if resolve(companion) == nil then
            lacks = companion
            break
          end
        end
        if lacks == nil then
          local cmd = { path }
          vim.list_extend(cmd, candidate.args)
          return candidate, cmd, nil
        end
        misses[#misses + 1] = ("%s (`%s` found, but `%s` is not)"):format(
          candidate.name,
          candidate.bin,
          lacks
        )
      end
    end
    return nil, nil, table.concat(misses, ", ")
  end

  ---@type integer|nil
  local client_id
  ---@type string|nil
  local dir

  after_each(function()
    if client_id then
      local client = vim.lsp.get_client_by_id(client_id)
      if client then
        client:stop(true)
      end
      client_id = nil
    end
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) ~= "" then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    if dir then
      pcall(vim.fn.delete, dir, "rf")
      dir = nil
    end
  end)

  it("catches a real server's diagnostics on deliberately broken content", function()
    local candidate, cmd, missing = pick()
    if candidate == nil then
      local message = (
        "no language server for the live probe -- this gate did NOT run."
        .. " Looked for: %s. Install any one of them to exercise it."
      ):format(missing)
      -- Both channels on purpose: plenary's PENDING line names the case,
      -- stderr survives a CI log that only errors get read out of.
      io.stderr:write("\n[probe_live] SKIPPED: " .. message .. "\n")
      local ci = vim.env.CI
      if ci ~= nil and ci ~= "" and ci ~= "false" then
        assert.is_true(false, "under CI a server is installed for this case, so: " .. message)
      end
      pending(message)
      return
    end

    -- A real directory, not a scratch buffer: `root_dir` has to resolve to
    -- something, and the probe builds its own buffer next to the current one.
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    for file, lines in pairs(candidate.root) do
      vim.fn.writefile(lines, vim.fs.joinpath(dir, file))
    end

    -- The seed file is *valid*. Its job is to give the server a document to
    -- attach to; the broken content is the probe's to supply, and seeding it
    -- here would mean testing this file instead of `probe.SNIPPETS`.
    local seed = vim.fs.joinpath(dir, candidate.seed.file)
    vim.fn.writefile(candidate.seed.lines, seed)
    vim.cmd.edit(vim.fn.fnameescape(seed))
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_option_value("filetype", candidate.filetype, { buf = bufnr })

    client_id = vim.lsp.start({
      name = candidate.name,
      cmd = cmd,
      root_dir = dir,
    }, { bufnr = bufnr })
    assert.is_truthy(client_id, ("%s could not be started from %s"):format(candidate.name, cmd[1]))

    local initialized = vim.wait(INIT_TIMEOUT_MS, function()
      local client = client_id and vim.lsp.get_client_by_id(client_id)
      return client ~= nil and client.initialized == true
    end, 50)
    assert.is_true(
      initialized,
      ("%s did not finish initializing within %dms"):format(candidate.name, INIT_TIMEOUT_MS)
    )

    package.loaded["lsp.lspdoctor.probe"] = nil
    local probe = require("lsp.lspdoctor.probe")
    probe.setup({ probe_timeout = PROBE_TIMEOUT_MS })

    local lines, report = probe.run(bufnr)
    local rendered = table.concat(lines, "\n")

    -- Asserted before `ok`, because these three say *where* it broke and `ok`
    -- only says that it did.
    assert.is_nil(
      report.reason,
      ("the probe did not reach %s: %s\n%s"):format(candidate.name, report.reason, rendered)
    )
    assert.are.equal(1, #report.clients, "expected exactly the started client\n" .. rendered)
    assert.is_true(
      report.clients[1].attached,
      ("%s refused the probe buffer\n%s"):format(candidate.name, rendered)
    )

    -- The finding this whole file exists for. A green assert here means the
    -- chain holds end to end: buffer -> didOpen -> server -> publish/pull ->
    -- namespace -> `vim.diagnostic` -> report.
    assert.is_true(
      report.ok,
      (
        "%s is running and attached but delivered no diagnostics for content it"
        .. " cannot parse, within %dms. That is a broken diagnostics pipeline,"
        .. " not an absence of errors.\n%s"
      ):format(candidate.name, PROBE_TIMEOUT_MS, rendered)
    )
    assert.is_true(report.clients[1].count > 0, rendered)
    assert.is_truthy(report.clients[1].elapsed_ms, rendered)

    -- Proven against a fake in `lspdoctor_spec.lua`; proven against a server
    -- that really opened the document here, which is where a stray write or a
    -- surviving buffer would actually happen.
    assert.is_nil((vim.uv or vim.loop).fs_stat(report.path), "the probe wrote to disk")
    assert.are.equal(0, vim.fn.bufexists(report.path), "the probe left its buffer behind")
  end)
end)
