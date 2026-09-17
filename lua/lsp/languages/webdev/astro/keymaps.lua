---@module 'lsp.languages.webdev.astro.keymaps'
--- Astro keymaps under `<leader>a*`: component navigation/search/switch,
--- new component/import scaffolding, and organizing imports.

local notify = require("lib.nvim.notify").create("[lsp.languages.webdev.astro.keymaps]")
local map = require("lib.nvim.bindings.keymap")

local M = {}

---@return nil
function M.attach()
  local bufnr = vim.api.nvim_get_current_buf()
  if not bufnr or type(bufnr) ~= "number" then
    notify.notify("bufnr in astro keymaps attaching is not valid")
    return
  end

  -- Component-Navigation
  map("n", "gC", function()
    require("telescope.builtin").find_files({
      prompt_title = "Astro Components",
      search_dirs = { "src/components" },
      file_ignore_patterns = { "%.test%.", "%.spec%." },
    })
  end, { buffer = bufnr, desc = "Find Astro Components" })

  -- Layout-Navigation
  map("n", "gL", function()
    require("telescope.builtin").find_files({
      prompt_title = "Astro Layouts",
      search_dirs = { "src/layouts" },
    })
  end, { buffer = bufnr, desc = "Find Astro Layouts" })

  -- Page-Navigation
  map("n", "gP", function()
    require("telescope.builtin").find_files({
      prompt_title = "Astro Pages",
      search_dirs = { "src/pages" },
    })
  end, { buffer = bufnr, desc = "Find Astro Pages" })

  -- Script Block Navigation
  map("n", "<leader>as", function()
    vim.fn.search("^<script", "w")
  end, { buffer = bufnr, desc = "Jump to <script>" })

  -- Style Block Navigation
  map("n", "<leader>ay", function()
    vim.fn.search("^<style", "w")
  end, { buffer = bufnr, desc = "Jump to <style>" })

  -- Template Block Navigation
  map("n", "<leader>at", function()
    vim.fn.search("^---$", "w")
    vim.cmd("normal! j")
  end, { buffer = bufnr, desc = "Jump to template (after frontmatter)" })

  -- Frontmatter Navigation
  map("n", "<leader>af", function()
    vim.fn.cursor(1, 1)
    vim.fn.search("^---$", "c")
  end, { buffer = bufnr, desc = "Jump to frontmatter" })

  -- Toggle between Script/Template/Style
  map("n", "<leader>an", function()
    local line = vim.fn.line(".")

    -- Find next section boundary. `next_line` starts at "nothing found"
    -- rather than at the line count: seeded with `total`, a boundary that sits
    -- ON the last line failed the `next_line < total` test and the cursor
    -- wrapped to line 1 instead of moving to it. Measured on a four-line
    -- buffer whose only boundary is `<style>` on line 4 -- the mapping left
    -- the cursor on line 1.
    local patterns = { "^<script", "^<style", "^---$" }
    local next_line = 0

    for _, pat in ipairs(patterns) do
      vim.fn.cursor(line, 1)
      local found = vim.fn.search(pat, "W")
      if found > 0 and (next_line == 0 or found < next_line) then
        next_line = found
      end
    end

    if next_line > 0 then
      vim.fn.cursor(next_line, 1)
    else
      -- Nothing below the cursor: wrap to the top.
      vim.fn.cursor(1, 1)
    end
  end, { buffer = bufnr, desc = "Next Astro section" })

  -- Import statement navigation
  map("n", "<leader>ai", function()
    vim.fn.search("^import ", "w")
  end, { buffer = bufnr, desc = "Jump to next import" })

  -- Add import statement
  map("n", "<leader>aI", function()
    require("ui.kit").input({
      title = "Component name: ",
      on_submit = function(component)
        if component ~= "" then
          local import_line =
            string.format('import %s from "@/components/%s.astro";', component, component)

          -- Find frontmatter end
          vim.fn.cursor(1, 1)
          local fm_end = vim.fn.search("^---$", "W", 20)
          if fm_end > 0 then
            vim.fn.append(fm_end - 1, import_line)
          end
        end
      end,
    })
  end, { buffer = bufnr, desc = "Add component import" })

  -- Extract to Component
  map("v", "<leader>ax", function()
    -- The LIVE selection, not `'<`/`'>`. Those marks are written when Visual
    -- mode is left, and a mapping invoked from Visual mode runs while it is
    -- still active, so they still describe the *previous* selection -- or
    -- nothing at all. Measured on a fresh `Vj` over lines 4-5 of an
    -- index.astro: `line("'<")` and `line("'>")` both read 0, so `getline(0,
    -- 0)` returned an empty list, the component file was written with an empty
    -- body, `deletebufline(bufnr, 0, 0)` removed nothing, no `<Name />` was
    -- inserted -- and the user was told "Created component:" all the same.
    -- `line("v")` is the anchor end of the selection that is open right now
    -- and `line(".")` is the cursor end; either may be the upper one.
    local start_line = vim.fn.line("v")
    local end_line = vim.fn.line(".")
    if start_line > end_line then
      start_line, end_line = end_line, start_line
    end
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)

    -- The range is captured, so leave Visual mode before the prompt opens its
    -- own window over it.
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)

    require("ui.kit").input({
      title = "Component name: ",
      on_submit = function(name)
        if name == "" then
          return
        end

        -- Create new component file
        local component_path = "src/components/" .. name .. ".astro"

        -- `writefile` does not create directories: measured, this died with
        -- "E482: Can't open file src/components/X.astro for writing" in a
        -- project that has no `src/components` yet -- which is every project
        -- before its first component, and every nested `ui/Button` name.
        vim.fn.mkdir(vim.fn.fnamemodify(component_path, ":h"), "p")

        local content = { "---", "---", "" }
        vim.list_extend(content, lines)

        if not pcall(vim.fn.writefile, content, component_path) then
          notify.warn("Could not write " .. component_path)
          return
        end

        -- Replace the selection with the component usage, on `bufnr` rather
        -- than on whatever is current when the prompt resolves, and in one
        -- call so the insert cannot land against a range the delete shifted.
        vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, { "<" .. name .. " />" })

        notify.notify("Created component: " .. component_path)
      end,
    })
  end, { buffer = bufnr, desc = "Extract to component" })

  -- Preview in Browser
  map("n", "<leader>ap", function()
    local file = vim.fn.expand("%:p")
    local relative = vim.fn.fnamemodify(file, ":~:.")

    -- Convert file path to URL path
    local url_path = relative:gsub("^src/pages/", ""):gsub("%.astro$", "")
    if url_path:match("index$") then
      url_path = url_path:gsub("index$", "")
    end

    local url = "http://localhost:4321/" .. url_path
    -- vim.ui.open() picks the platform opener itself (xdg-open / open / start)
    -- and spawns it detached via vim.system(), so the UI thread is never
    -- blocked. The previous vim.fn.system({"xdg-open", url}) both blocked until
    -- the opener returned and only worked on Linux.
    local ok_open, err = pcall(vim.ui.open, url)
    if not ok_open then
      notify.warn("Could not open " .. url .. ": " .. tostring(err))
    end
  end, { buffer = bufnr, desc = "Preview in browser" })

  -- Format Astro file
  map("n", "<leader>aF", function()
    local ok, conform = pcall(require, "conform")
    if ok then
      conform.format({ bufnr = bufnr, timeout_ms = 2000 })
    else
      vim.lsp.buf.format({ bufnr = bufnr, timeout_ms = 2000 })
    end
  end, { buffer = bufnr, desc = "Format Astro file" })
end

return M
