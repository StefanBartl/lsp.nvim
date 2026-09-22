---@module 'lsp.core.call_hierarchy'
---@brief `lsc`/`lsC` (incoming/outgoing calls) for Lua, where lua_ls has none.
---@description
--- lua_ls answers neither `prepareCallHierarchy` nor `callHierarchy/*` --
--- LuaLS/lua-language-server#2832 is still open. `StefanBartl/documentation.nvim`
--- can, with `opts.callhierarchy = true`: a second, narrow in-process client
--- backed by its own module-map scan, attached alongside lua_ls rather than
--- instead of it.
---
--- **On demand, not at startup.** The first `lsc`/`lsC` in a Lua buffer no
--- attached client already answers `prepareCallHierarchy` for: `pcall(require,
--- "documentation")`, forced through `lazy.nvim` if it is a lazy plugin not yet
--- loaded; a clear sentence instead of "No results" if it is not there at all.
--- If it is, `install({ root = …, callhierarchy = true })` for the buffer's own
--- root (`lsp.servers.lua_ls.rootresolver` -- the same root lua_ls itself would
--- use, so this never disagrees with it about project boundaries), then the
--- normal picker. The scan is real work -- ~2s measured on this repository --
--- and happens once per project, not once per keypress: a client already
--- attached to the buffer skips straight to the picker.
---
--- **A buffer already open when `install()` runs does not get the client for
--- free.** documentation.nvim attaches on `BufReadPost`/`BufNewFile`, which
--- already fired for a buffer that was open before this function called
--- `install()`. Re-firing those two events for just this buffer (`nvim_exec_
--- autocmds`) is the documented attach signal, not a private hook -- the same
--- thing a manual `:e` would have triggered.
---
--- **Switching projects needs no bookkeeping here.** documentation.nvim's own
--- registry keys a handle by root and is fine holding several at once; this
--- module never uninstalls one, it just asks "is a client already attached to
--- *this* buffer" before deciding whether to install anything.
---
---@see lsp.bindings.actions
---@see lsp.servers.lua_ls.rootresolver

local M = {}

---@internal
---@return table
local function notify()
  return require("lib.nvim.notify").create("[lsp.nvim]")
end

---@internal
---@return table|nil
local function fzf_lua()
  local ok, mod = pcall(require, "fzf-lua")
  return ok and mod or nil
end

---@internal
--- `require("documentation")`, forcing a lazy `cmd`-triggered plugin spec to
--- load first if a bare `require` does not find it -- `lazy.nvim` only adds a
--- lazy plugin's `lua/` tree to the runtimepath once one of its declared
--- triggers has fired, and pressing `lsc` is not one of them.
---@return table|nil
local function documentation()
  local ok, doc = pcall(require, "documentation")
  if ok then
    return doc
  end
  local ok_lazy, lazy = pcall(require, "lazy")
  if ok_lazy and type(lazy.load) == "function" then
    pcall(lazy.load, { plugins = { "documentation.nvim" } })
  end
  ok, doc = pcall(require, "documentation")
  return ok and doc or nil
end

---@internal
---@param bufnr integer
---@return boolean answers
local function has_call_hierarchy_client(bufnr)
  return #vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/prepareCallHierarchy" }) > 0
end

---@internal
--- Install (or reuse) documentation.nvim's call-hierarchy client for this
--- buffer's own root, and attach it to this buffer specifically.
---@param bufnr integer
---@return boolean attached
local function ensure_lua_call_hierarchy(bufnr)
  local doc = documentation()
  if doc == nil then
    notify().info("call hierarchy for Lua needs documentation.nvim, with opts.callhierarchy = true")
    return false
  end

  local root = require("lsp.servers.lua_ls.rootresolver")(bufnr)
  notify().info(
    ("scanning %s for call hierarchy (documentation.nvim, once per project)"):format(root)
  )
  local ok = pcall(doc.install, { root = root, callhierarchy = true })
  if not ok then
    notify().warn(
      ("documentation.nvim could not install a call-hierarchy handle for %s"):format(root)
    )
    return false
  end

  vim.api.nvim_exec_autocmds({ "BufReadPost", "BufNewFile" }, { buffer = bufnr })
  return has_call_hierarchy_client(bufnr)
end

---@internal
---@param direction "in"|"out"
---@return nil
local function open_picker(direction)
  local fzf = fzf_lua()
  if fzf then
    fzf[direction == "in" and "lsp_incoming_calls" or "lsp_outgoing_calls"]()
    return
  end
  if direction == "in" then
    vim.lsp.buf.incoming_calls()
  else
    vim.lsp.buf.outgoing_calls()
  end
end

---@internal
---@param direction "in"|"out"
---@return nil
local function call_hierarchy(direction)
  local bufnr = vim.api.nvim_get_current_buf()
  if not has_call_hierarchy_client(bufnr) then
    if vim.bo[bufnr].filetype ~= "lua" then
      notify().info("no attached server offers a call hierarchy")
      return
    end
    if not ensure_lua_call_hierarchy(bufnr) then
      return
    end
  end
  open_picker(direction)
end

--- Who calls the function under the cursor.
---@return nil
function M.incoming()
  call_hierarchy("in")
end

--- What the function under the cursor calls.
---@return nil
function M.outgoing()
  call_hierarchy("out")
end

return M
