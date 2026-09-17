---@module 'lsp.languages.webdev.astro.usercmds'
--- Astro user commands: `:AstroDevStart`/`Stop`/`Build`/`Preview` (a terminal
--- running the astro CLI), plus `:AstroNewComponent`/`NewPage` scaffolding
--- and `:AstroListComponents`/`FindUsage`.

local notify = require("lib.nvim.notify").create("[lsp.languages.webdev.astro.commands]")
local usercmd = require("lib.nvim.bindings.usercmd")

local M = {}

---@internal
--- Write `template` to `path`, creating the directories above it, and open it.
---
--- `vim.fn.writefile` creates no directories. Measured in a project without a
--- `src/` tree, which is every project before its first component:
--- `:AstroNewComponent Widget` and `:AstroNewPage about` both died with
--- "E482: Can't open file src/components/Widget.astro for writing: no such
--- file or directory", swallowed into a notification by the usercmd wrapper --
--- so the command that exists to create a file created nothing. A nested name
--- (`:AstroNewComponent ui/Button`) failed the same way even with
--- `src/components` present.
---
--- The `:edit` path is escaped, too: unescaped, a name with a space made
--- Neovim open two files.
---@param path string
---@param template string[]
---@return nil
local function scaffold(path, template)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")

  if not pcall(vim.fn.writefile, template, path) then
    notify.warn("Could not write " .. path)
    return
  end

  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

---@return nil
function M.setup()
  -- Start Astro dev server
  usercmd.create("AstroDevStart", function()
    vim.cmd("terminal astro dev")
    vim.cmd("wincmd J")
    vim.cmd("resize 10")
  end, { desc = "Start Astro dev server" })

  -- Stop Astro dev server
  usercmd.create("AstroDevStop", function()
    if vim.fn.executable("pkill") ~= 1 then
      notify.warn("pkill not available on this system")
      return
    end
    vim.system({ "pkill", "-f", "astro dev" }):wait()
    notify.notify("Astro dev server stopped")
  end, { desc = "Stop Astro dev server" })

  -- Build Astro project
  usercmd.create("AstroBuild", function()
    -- Guarded like `:AstroDevStop` is. `vim.system` raises outright on a
    -- missing executable rather than returning a non-zero result: without the
    -- guard, running this where astro is not installed produced
    -- "vim/_core/system.lua:324: ENOENT: no such file or directory (cmd):
    -- 'astro'" as a notification, which reads like a bug in Neovim.
    if vim.fn.executable("astro") ~= 1 then
      notify.warn("astro not found on PATH")
      return
    end

    local res = vim.system({ "astro", "build" }, { text = true }):wait()

    -- `res.stdout or res.stderr` never reached stderr: `vim.system` returns
    -- "" (truthy in Lua), not nil, for an empty stream. A failing build
    -- therefore showed an empty INFO notification and swallowed the error
    -- message the build wrote to stderr.
    local out = res.stdout
    if out == nil or out == "" then
      out = res.stderr or ""
    end
    if res.code == 0 then
      notify.info(out)
    else
      notify.warn(("astro build exited %d\n%s"):format(res.code, out))
    end
  end, { desc = "Build Astro project" })

  -- Preview production build
  usercmd.create("AstroPreview", function()
    vim.cmd("terminal astro preview")
    vim.cmd("wincmd J")
    vim.cmd("resize 10")
  end, { desc = "Preview Astro build" })

  -- Create new component
  usercmd.create("AstroNewComponent", function(opts)
    local function create(name)
      if name == "" then
        return
      end

      local path = "src/components/" .. name .. ".astro"
      local template = {
        "---",
        "interface Props {}",
        "",
        "const {} = Astro.props;",
        "---",
        "",
        "<div>",
        "  <!-- Component content -->",
        "</div>",
      }

      scaffold(path, template)
    end

    if opts.args ~= "" then
      create(opts.args)
    else
      require("ui.kit").input({ title = "Component name: ", on_submit = create })
    end
  end, {
    nargs = "?",
    desc = "Create new Astro component",
  })

  -- Create new page
  usercmd.create("AstroNewPage", function(opts)
    local function create(name)
      if name == "" then
        return
      end

      if not name:match("%.astro$") then
        name = name .. ".astro"
      end

      local path = "src/pages/" .. name
      local template = {
        "---",
        'import Layout from "@/layouts/Layout.astro";',
        "---",
        "",
        '<Layout title="Page">',
        "  <main>",
        "    <h1>Page Content</h1>",
        "  </main>",
        "</Layout>",
      }

      scaffold(path, template)
    end

    if opts.args ~= "" then
      create(opts.args)
    else
      require("ui.kit").input({
        title = "Page name (e.g., about.astro): ",
        on_submit = create,
      })
    end
  end, {
    nargs = "?",
    desc = "Create new Astro page",
  })

  -- List all components
  usercmd.create("AstroListComponents", function()
    require("telescope.builtin").find_files({
      prompt_title = "Astro Components",
      search_dirs = { "src/components" },
      file_ignore_patterns = { "%.test%.", "%.spec%." },
    })
  end, { desc = "List all Astro components" })

  -- Find component usage
  usercmd.create("AstroFindUsage", function()
    local component = vim.fn.expand("<cword>")
    require("telescope.builtin").live_grep({
      prompt_title = "Component Usage: " .. component,
      default_text = "<" .. component,
    })
  end, { desc = "Find component usage" })

  -- Check project structure
  usercmd.create("AstroCheckStructure", function()
    local required_dirs = {
      "src/components",
      "src/layouts",
      "src/pages",
      "public",
    }

    local missing = {}
    for _, dir in ipairs(required_dirs) do
      if vim.fn.isdirectory(dir) == 0 then
        table.insert(missing, dir)
      end
    end

    if #missing > 0 then
      notify.warn("Missing directories:\n" .. table.concat(missing, "\n"))
    else
      notify.info("Project structure is valid")
    end
  end, { desc = "Check Astro project structure" })
end

return M
