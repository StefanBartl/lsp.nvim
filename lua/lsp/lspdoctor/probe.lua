---@module 'lsp.lspdoctor.probe'
---@brief `:LspDoctor probe` -- do diagnostics actually arrive?
---@description
--- The other four reports observe. This one provokes: it builds a buffer whose
--- content is guaranteed to be wrong for this filetype, hands it to the
--- clients already attached here, and waits to see whether anything comes
--- back.
---
--- It exists because "no errors" and "the diagnostics pipeline is dead" look
--- identical on screen -- a clean file and a mute server are both empty -- and
--- every state-reporting check says the same thing about both: the server is
--- running, it advertises the capability, the buffer has zero diagnostics. The
--- only way to tell them apart is to guarantee there is something to report
--- and see whether it is reported.
---
--- ## What it does to your session
---
--- * Creates one unlisted buffer named after a file that does **not** exist,
---   in the directory of the current buffer, so `root_dir` resolves the way it
---   does for real work. Nothing is written to disk, at any point.
--- * Attaches the clients that are already on the current buffer. It does not
---   start servers: the question is whether *these* clients deliver, and
---   starting one would answer a different question slowly.
--- * Deletes the buffer again when it is done, which sends `didClose`. The
---   probe's own diagnostics go with it.
---
--- ## Why it blocks
---
--- `vim.wait` rather than a callback, so the report keeps the shape every
--- other report has -- `(bufnr, use_scratch) -> lines, result` -- and so
--- `:LspDoctor probe` prints when it is finished rather than printing an empty
--- report and filling it in later. The wait is bounded by `probe_timeout`, and
--- a timeout is the interesting answer here, not a failure mode.
---
---@see lsp.lspdoctor.health

local M = {}

local api = vim.api
local lsp = vim.lsp
local diag = vim.diagnostic
local uv = vim.uv or vim.loop

---@type table
local Opts = {}

---@param opts table
---@return nil
function M.setup(opts)
  Opts = opts or {}
end

-- The snippets ----------------------------------------------------------------

--- Content that no server may consider correct, per filetype.
---
--- Every entry is a *syntax* error rather than a type or lint error, because
--- syntax is the one thing every language server checks before it does
--- anything else. A wrong type needs the project to resolve; an unclosed brace
--- does not, so a probe built on syntax stays honest in a directory the server
--- has not indexed yet.
---
--- `ext` is not decoration: for most servers the file extension, not the
--- Neovim filetype, decides whether the document is theirs at all.
---@type table<string, { ext: string, lines: string[] }>
M.SNIPPETS = {
  c = { ext = "c", lines = { "int main( { return 0; }" } },
  cpp = { ext = "cpp", lines = { "int main( { return 0; }" } },
  cs = { ext = "cs", lines = { "class Probe { void M( { } }" } },
  css = { ext = "css", lines = { "a { color: }" } },
  go = { ext = "go", lines = { "package main", "", "func main() {", "\tx :=" } },
  java = { ext = "java", lines = { "class Probe { void m( { } }" } },
  javascript = { ext = "js", lines = { "const x =" } },
  javascriptreact = { ext = "jsx", lines = { "const x =" } },
  json = { ext = "json", lines = { '{ "a": }' } },
  jsonc = { ext = "jsonc", lines = { '{ "a": }' } },
  lua = { ext = "lua", lines = { "local x =" } },
  python = { ext = "py", lines = { "def f(:" } },
  rust = { ext = "rs", lines = { "fn main() { let x = ; }" } },
  sh = { ext = "sh", lines = { 'if [ -z "$x" ]; then' } },
  bash = { ext = "sh", lines = { 'if [ -z "$x" ]; then' } },
  toml = { ext = "toml", lines = { "a =" } },
  typescript = { ext = "ts", lines = { "const x =" } },
  typescriptreact = { ext = "tsx", lines = { "const x =" } },
  yaml = { ext = "yaml", lines = { "a: [1," } },
  zig = { ext = "zig", lines = { "pub fn main() void { const x = ; }" } },
}

--- The filetypes a probe exists for, sorted.
---@return string[]
function M.filetypes()
  local names = {}
  for ft in pairs(M.SNIPPETS) do
    names[#names + 1] = ft
  end
  table.sort(names)
  return names
end

-- The probe buffer -------------------------------------------------------------

---@internal
--- A path in `dir` that neither a buffer nor the filesystem is using.
---
--- Both have to be free. A name that collides with a live buffer makes
--- `nvim_buf_set_name` fail; a name that collides with a file on disk would
--- make the server read that file's content for a document we never wrote,
--- and the probe would be diagnosing something else entirely.
---@param dir string
---@param ext string
---@return string
local function free_path(dir, ext)
  for i = 0, 16 do
    local suffix = (i == 0) and "" or ("_" .. i)
    local path = vim.fs.joinpath(dir, ("lspdoctor_probe%s.%s"):format(suffix, ext))
    if vim.fn.bufexists(path) == 0 and uv.fs_stat(path) == nil then
      return path
    end
  end
  -- Sixteen taken names means something is very wrong, but a timestamped name
  -- is still better than giving up on the report.
  return vim.fs.joinpath(dir, ("lspdoctor_probe_%d.%s"):format(os.time(), ext))
end

---@internal
--- The directory a probe for `bufnr` belongs in.
---
--- The current buffer's directory, so the server resolves the same `root_dir`
--- it uses for real work. A probe in a temp directory would be outside the
--- project for every server that has a notion of one, and "gopls ignored a
--- file that is not in your module" is not the answer this report is asking
--- for.
---@param bufnr integer
---@return string
local function probe_dir(bufnr)
  local name = api.nvim_buf_get_name(bufnr)
  if name ~= "" then
    local dir = vim.fn.fnamemodify(name, ":h")
    if dir ~= "" and vim.fn.isdirectory(dir) == 1 then
      return dir
    end
  end
  return vim.fn.getcwd()
end

---@internal
--- Build the probe buffer, filled and named but not yet attached.
---@param bufnr integer
---@param filetype string
---@param snippet { ext: string, lines: string[] }
---@return integer|nil probe_buf, string path_or_error
local function make_probe_buffer(bufnr, filetype, snippet)
  -- `scratch = false`: the buffer needs `buftype = ""`, because a `nofile`
  -- buffer is not a document any language server will accept.
  local probe_buf = api.nvim_create_buf(false, false)
  if probe_buf == 0 then
    return nil, "could not create a buffer"
  end

  local path = free_path(probe_dir(bufnr), snippet.ext)
  local named = pcall(api.nvim_buf_set_name, probe_buf, path)
  if not named then
    pcall(api.nvim_buf_delete, probe_buf, { force = true })
    return nil, ("could not name a buffer %s"):format(path)
  end

  -- Content before filetype, and filetype before attach: the client sends
  -- `didOpen` with whatever the buffer holds at that moment, and a `didOpen`
  -- carrying an empty document is a probe that provokes nothing.
  api.nvim_buf_set_lines(probe_buf, 0, -1, false, snippet.lines)
  api.nvim_set_option_value("filetype", filetype, { buf = probe_buf })
  api.nvim_set_option_value("swapfile", false, { buf = probe_buf })

  return probe_buf, path
end

-- Waiting ----------------------------------------------------------------------

---@internal
--- Every diagnostic on `probe_buf` that came from `client_id`.
---
--- Both namespaces, because a server either pushes
--- (`textDocument/publishDiagnostics`) or is pulled from
--- (`textDocument/diagnostic`), and Neovim keeps the two apart. Asking for
--- only one would report a working pull-diagnostics server as mute.
---@param probe_buf integer
---@param client_id integer
---@return table[] diagnostics
local function diagnostics_of(probe_buf, client_id)
  local items = {}
  for _, is_pull in ipairs({ false, true }) do
    local ok, ns = pcall(lsp.diagnostic.get_namespace, client_id, is_pull)
    if ok and ns then
      vim.list_extend(items, diag.get(probe_buf, { namespace = ns }) or {})
    end
  end
  return items
end

---@internal
--- The spelled-out name of a severity.
---
--- Through the list half of `vim.diagnostic.severity`, not by searching its
--- keys: the table maps `ERROR`, `E` and `1` onto each other, so a search over
--- `pairs` returns whichever spelling comes up first and prints `(E)` about as
--- often as `(ERROR)`.
---@param severity integer|nil
---@return string
local function severity_name(severity)
  return (type(severity) == "number" and diag.severity[severity]) or "?"
end

-- Report -----------------------------------------------------------------------

--- Provoke an error and report whether it came back.
---@param bufnr integer
---@return string[] lines, table report
function M.run(bufnr)
  bufnr = (type(bufnr) == "number" and bufnr ~= 0) and bufnr or api.nvim_get_current_buf()

  local timeout = Opts.probe_timeout or 5000
  local filetype = api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype or ""
  ---@type table
  local report =
    { mode = "probe", ok = false, filetype = filetype, timeout = timeout, clients = {} }
  local lines = { "### Probe", "" }

  local snippet = M.SNIPPETS[filetype]
  if snippet == nil then
    report.reason = "no snippet"
    lines[#lines + 1] = ("No probe snippet for filetype `%s`."):format(
      filetype == "" and "(none)" or filetype
    )
    lines[#lines + 1] = ""
    lines[#lines + 1] = "There are snippets for: " .. table.concat(M.filetypes(), ", ") .. "."
    lines[#lines + 1] = ""
    lines[#lines + 1] = "A probe needs content this filetype's server is certain to reject."
      .. " Guessing one would risk a report that says the pipeline is dead when"
      .. " the file was simply acceptable."
    return lines, report
  end

  local clients = lsp.get_clients({ bufnr = bufnr }) or {}
  if #clients == 0 then
    report.reason = "no clients"
    lines[#lines + 1] = "No LSP client is attached to this buffer, so there is nothing to probe."
    lines[#lines + 1] = ""
    lines[#lines + 1] = "`:LspDoctor startup` says why, and `:LspDoctor resolve`"
      .. " says where the filetype → server chain drops it."
    return lines, report
  end

  -- The clock starts before the buffer does. Setting its filetype already
  -- attaches a server and sends `didOpen`, so a clock started at the `vim.wait`
  -- would leave that part of the roundtrip out and could report a whole
  -- roundtrip as "1ms". What the number should mean is how long the probe took
  -- from nothing to an answer.
  local started = uv.hrtime()
  local probe_buf, path = make_probe_buffer(bufnr, filetype, snippet)
  if probe_buf == nil then
    report.reason = "no probe buffer"
    lines[#lines + 1] = "Could not build the probe buffer: " .. path
    return lines, report
  end

  report.path = path
  lines[#lines + 1] = ("Filetype `%s`, probing through `%s` (never written to disk)."):format(
    filetype,
    vim.fn.fnamemodify(path, ":t")
  )
  lines[#lines + 1] = ""
  lines[#lines + 1] = "```" .. filetype
  vim.list_extend(lines, snippet.lines)
  lines[#lines + 1] = "```"
  lines[#lines + 1] = ""

  ---@type table[]
  local targets = {}
  for _, client in ipairs(clients) do
    local attached = lsp.buf_attach_client(probe_buf, client.id)
    targets[#targets + 1] = {
      name = client.name or ("client#" .. tostring(client.id)),
      id = client.id,
      attached = attached and true or false,
    }
  end

  local pending = 0
  for _, target in ipairs(targets) do
    if target.attached then
      pending = pending + 1
    end
  end

  if pending > 0 then
    vim.wait(timeout, function()
      for _, target in ipairs(targets) do
        if target.attached and target.elapsed_ms == nil then
          local items = diagnostics_of(probe_buf, target.id)
          if #items > 0 then
            target.items = items
            target.elapsed_ms = math.floor((uv.hrtime() - started) / 1e6)
            pending = pending - 1
          end
        end
      end
      return pending == 0
    end, 25)
  end

  -- Before the report is rendered: a buffer that outlives the probe would keep
  -- its diagnostics in every global list, and they are diagnostics of a file
  -- that does not exist.
  pcall(api.nvim_buf_delete, probe_buf, { force = true })

  local answered = 0
  for _, target in ipairs(targets) do
    lines[#lines + 1] = ("**%s**"):format(target.name)
    if not target.attached then
      lines[#lines + 1] = "  Attach: ❌ the client refused the probe buffer"
      lines[#lines + 1] = "  💡 Nothing was asked of this server, so this is not a verdict on it."
    elseif target.items then
      answered = answered + 1
      local first = target.items[1]
      lines[#lines + 1] = ("  Diagnostics: ✅ %d after %dms"):format(
        #target.items,
        target.elapsed_ms
      )
      lines[#lines + 1] = ("  First: `%s` (%s)"):format(
        (first.message or ""):gsub("%s+", " "),
        severity_name(first.severity)
      )
    else
      lines[#lines + 1] = ("  Diagnostics: ❌ none within %dms"):format(timeout)
      lines[#lines + 1] = "  💡 The server is attached and was sent a file it cannot parse,"
        .. " and said nothing. Check `:LspLog`."
      lines[#lines + 1] = "  💡 A server that refuses files outside its project (gopls without"
        .. " a module, tsserver without a tsconfig) looks the same from here."
        .. " Open a real broken file to tell the two apart."
    end
    table.insert(report.clients, {
      name = target.name,
      id = target.id,
      attached = target.attached,
      count = target.items and #target.items or 0,
      elapsed_ms = target.elapsed_ms,
    })
    lines[#lines + 1] = ""
  end

  report.ok = answered > 0 and answered == #targets
  local summary = ("Summary: %d/%d client(s) delivered diagnostics within %dms"):format(
    answered,
    #targets,
    timeout
  )
  table.insert(lines, 1, "")
  table.insert(lines, 1, summary)
  table.insert(lines, 1, string.rep("─", 50))
  report.summary = summary

  return lines, report
end

return M
