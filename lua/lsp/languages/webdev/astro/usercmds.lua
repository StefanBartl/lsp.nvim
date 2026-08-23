---@module 'lsp.languages.webdev.astro.usercmds'
--- Astro user commands: `:AstroDevStart`/`Stop`/`Build`/`Preview` (a terminal
--- running the astro CLI), plus `:AstroNewComponent`/`NewPage` scaffolding
--- and `:AstroListComponents`/`FindUsage`.

local notify = require("lib.nvim.notify").create("[lsp.languages.webdev.astro.commands]")
local usercmd = require("lib.nvim.usercmd")

local M = {}

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
    local res = vim.system({ "astro", "build" }, { text = true }):wait()
    notify.info(res.stdout or res.stderr or "")
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

      vim.fn.writefile(template, path)
      vim.cmd("edit " .. path)
    end

    if opts.args ~= "" then
      create(opts.args)
    else
      require("lib.nvim.ui.kit").input({ title = "Component name: ", on_submit = create })
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

      vim.fn.writefile(template, path)
      vim.cmd("edit " .. path)
    end

    if opts.args ~= "" then
      create(opts.args)
    else
      require("lib.nvim.ui.kit").input({
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
