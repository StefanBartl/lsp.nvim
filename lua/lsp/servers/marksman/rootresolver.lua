---@module 'lsp.servers.marksman.rootresolver'
-- Polymorphic root_dir resolver for Marksman LSP.

local cfg = require("lsp.servers.marksman.config")
local _cwd = require("lib.nvim.cross.fs._cwd")
local fs = vim.fs

--- @return fun(arg:(string|integer), cb?:fun(root:string)):string
return function()
  ---@param arg string|integer                 -- filename or bufnr
  ---@param cb fun(root:string)|nil            -- optional async callback
  ---@return string                            -- resolved root
  return function(arg, cb)
    -- Normalize to absolute file name
    ---@type string
    local fname
    if type(arg) == "number" then
      -- New API passes a buffer number
      fname = vim.api.nvim_buf_get_name(arg) or ""
    else
      -- Legacy API passes a filename path
      fname = tostring(arg or "")
    end
    if fname == "" then
      -- Fall back to CWD if no name is available (e.g., new unsaved buffer)
      fname = _cwd()
    end

    -- Compute directory component safely
    local dir = fs.dirname(fname)
    if not dir or dir == "" then
      dir = _cwd()
    end

    -- Resolve project root using markers; fall back to the containing dir
    ---@type string
    local root = fs.root(dir, cfg.root_dir_fallbacks) or dir

    -- Support async contract of the new vim.lsp pipeline
    if cb ~= nil then
      cb(root)
    end
    return root
  end
end
