---@module 'lsp.servers.lua_ls.find_type_dirs'
--- Enhanced type directory and file discovery for lua_ls
--- Finds both:
---   1. Directories whose name is `types`/`@types`, starts with `@types`, or
---      ends in `types` -- so `mytypes` and `@typescript` match too. Measured
---      against a fixture: `prototypes`, `mytypes` and `@typescript` are all
---      returned, `TYPES` is not (the name test is case-sensitive even on
---      Windows, unlike the ignore test below it).
---   2. Individual files named "@types.lua" or "types.lua" outside those directories
---
--- The walk is breadth-first and bounded by `max_results`; see the queue
--- comment below for what each of those cost when it was neither.

local notify = require("lib.nvim.notify").create("[lsp.servers.lua_ls.find_type_dirs]")
local sys_env = require("lib.nvim.system.env")

local uv = vim.loop or vim.uv
local norm = vim.fs.normalize

--- Discover type directories AND standalone type files under root.
--- @param root string Root directory to scan
--- @param opts { max_results?: integer, max_depth?: integer, include_files?: boolean }|nil
--- @return string[] Array of discovered paths (directories and files)
return function(root, opts)
  opts = opts or {}
  local MAX_RESULTS = opts.max_results or 200
  local MAX_DEPTH = opts.max_depth or 15
  local INCLUDE_FILES = opts.include_files ~= false -- default true

  -- Safe loading of ignore module
  local ignore_set = {}
  local ok, ignore = pcall(require, "lsp.servers.lua_ls.ignore")
  if ok and type(ignore.as_set) == "function" then
    ignore_set = ignore.as_set()
  end

  local matches = {}

  -- A queue with a moving head, not `table.remove(stack)`. Two reasons, both
  -- measured:
  --
  -- * `table.remove` pops the *last* pushed child, so the walk ran
  --   depth-first while the README calls it "BFS scanning".
  --   On a tree holding `aaa/types` at depth 1 and `zzz/a/b/c/types` at
  --   depth 4, `max_results = 1` returned the depth-4 directory and dropped
  --   the shallow one. Order only became visible once the cap below actually
  --   held, and under a cap it decides which directories make the budget --
  --   a vendored subtree four levels down must not spend it before
  --   `<root>/lua/types` is even looked at.
  -- * `table.remove(queue, 1)` would be the other way to get FIFO, but it
  --   shifts the whole array on every pop.
  local queue = { { path = norm(root), depth = 0 } }
  local head = 1
  local seen = {}

  while head <= #queue and #matches < MAX_RESULTS do
    local node = queue[head]
    head = head + 1

    -- Skip already processed paths
    if seen[node.path] then
      goto continue
    end
    seen[node.path] = true

    if node.depth <= MAX_DEPTH then
      local it = uv.fs_scandir(node.path)

      if it then
        while true do
          local name, kind = uv.fs_scandir_next(it)

          if not name then
            break
          end

          -- Skip hidden files/directories except .config
          if name:sub(1, 1) == "." and name ~= ".config" then
            goto inner_continue
          end

          local sep = sys_env.get().pathsep
          local child = norm(node.path .. sep .. name)

          if kind == "directory" then
            local key = sys_env.get().is_windows and name:lower() or name

            -- Skip ignored directories
            if ignore_set[key] then
              goto inner_continue
            end

            -- Check if this is a type directory
            local is_types = false
            if name == "types" or name == "@types" then
              is_types = true
            elseif name:match("^@types") or name:match("types$") then
              is_types = true
            end

            if is_types then
              -- Verify it actually contains .lua files
              local has_lua = false
              local check_it = uv.fs_scandir(child)
              if check_it then
                while true do
                  local file_name, file_kind = uv.fs_scandir_next(check_it)
                  if not file_name then
                    break
                  end

                  if file_kind == "file" and file_name:match("%.lua$") then
                    has_lua = true
                    break
                  elseif file_kind == "directory" then
                    -- Check one level deeper for lua files
                    local deep_check = uv.fs_scandir(child .. sep .. file_name)
                    if deep_check then
                      while true do
                        local deep_name, deep_kind = uv.fs_scandir_next(deep_check)
                        if not deep_name then
                          break
                        end
                        if deep_kind == "file" and deep_name:match("%.lua$") then
                          has_lua = true
                          break
                        end
                      end
                    end
                    if has_lua then
                      break
                    end
                  end
                end
              end

              -- Only add if contains actual type definitions
              if has_lua then
                matches[#matches + 1] = child
                -- The cap has to be re-checked *here*, not only in the outer
                -- loop. Every match a single directory contributes lands in
                -- one pass of this inner loop, so testing `#matches` once per
                -- popped node bounds nothing: a directory holding 500
                -- siblings that each end in "types" returned 500 paths for
                -- `max_results = 10` (measured, 34ms) -- 50x the budget the
                -- profile asked for, handed straight to lua_ls as
                -- `workspace.library`.
                if #matches >= MAX_RESULTS then
                  break
                end
              end
            end

            -- Add to the queue for further exploration
            queue[#queue + 1] = { path = child, depth = node.depth + 1 }
          elseif kind == "file" and INCLUDE_FILES then
            -- Check for standalone type files
            if name == "@types.lua" or name == "types.lua" then
              matches[#matches + 1] = child
              if #matches >= MAX_RESULTS then
                break
              end
            end
          end

          ::inner_continue::
        end
      end
    end

    ::continue::
  end

  -- DEBUG: Log found paths if environment variable is set
  if vim.env.DEBUG_LUA_LS and #matches > 0 then
    notify.info(string.format("find_type_dirs: Found %d paths", #matches))
  end

  return matches
end
