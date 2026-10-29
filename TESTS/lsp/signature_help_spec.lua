--- Covers the Insert-mode signature help (`lsp.tools.lsp_signature.help`, bound
--- to `<M-s>`): the border it asks for, and the "No signature help" float that
--- stands in for the core message a notification renderer may swallow.

describe("lsp.tools.lsp_signature.help", function()
  local api = vim.api
  local help = require("lsp.tools.lsp_signature.help")

  local saved = {}

  before_each(function()
    saved.get_clients = vim.lsp.get_clients
    saved.buf_request_all = vim.lsp.buf_request_all
    saved.signature_help = vim.lsp.buf.signature_help
    saved.orig_buf = api.nvim_get_current_buf()
    local buf = api.nvim_create_buf(false, true)
    saved.buf = buf
    api.nvim_set_current_buf(buf)
    api.nvim_buf_set_lines(buf, 0, -1, false, { "foo(" })
    api.nvim_win_set_cursor(0, { 1, 3 })
  end)

  after_each(function()
    help.close_notice()
    pcall(api.nvim_set_current_buf, saved.orig_buf)
    pcall(api.nvim_buf_delete, saved.buf, { force = true })
    vim.lsp.get_clients = saved.get_clients
    vim.lsp.buf_request_all = saved.buf_request_all
    vim.lsp.buf.signature_help = saved.signature_help
  end)

  --- The one float on screen that is not an ordinary window, if any.
  ---@return integer|nil
  local function float()
    for _, w in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_config(w).relative ~= "" then
        return w
      end
    end
    return nil
  end

  ---@param results table[]
  local function stub_server(results)
    vim.lsp.get_clients = function()
      return { { id = 1, offset_encoding = "utf-16" } }
    end
    vim.lsp.buf_request_all = function(_, _, _, cb)
      cb(results)
    end
    vim.lsp.buf.signature_help = function(cfg)
      saved.native_cfg = cfg
    end
    saved.native_cfg = nil
  end

  describe("resolve_border", function()
    it("defaults to rounded, the border hover.nvim uses", function()
      assert.are.equal("rounded", help.resolve_border())
    end)

    it("takes a native name, a hand-written list and falls back on nonsense", function()
      assert.are.equal("single", help.resolve_border("single"))
      local list = { "a", "b", "c", "d", "e", "f", "g", "h" }
      assert.are.same(list, help.resolve_border(list))
      assert.are.equal("rounded", help.resolve_border("no-such-style"))
      assert.are.equal("rounded", help.resolve_border(42))
    end)
  end)

  describe("without a signature", function()
    it("shows a small framed float saying so when no client can answer", function()
      vim.lsp.get_clients = function()
        return {}
      end
      help.show()

      local win = float()
      assert.is_not_nil(win, "no feedback float opened")
      local text = api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, -1, false)
      assert.are.same({ "No signature help" }, text)
      local cfg = api.nvim_win_get_config(win)
      assert.is_false(cfg.focusable)
      assert.are.equal("\xe2\x95\xad", cfg.border[1], "rounded top-left corner")
    end)

    it("shows it when the server answers with nothing", function()
      stub_server({ [1] = { result = nil } })
      help.show()
      assert.is_not_nil(float())
      assert.are.equal("rounded", saved.native_cfg.border)
      assert.is_true(saved.native_cfg.silent, "the core message stays off")
    end)

    it("closes on the next cursor move", function()
      stub_server({})
      help.show()
      assert.is_not_nil(float())
      vim.wait(50, function()
        return false
      end) -- let the autocmd arm
      api.nvim_exec_autocmds("CursorMoved", {})
      assert.is_nil(float())
    end)

    it("closes by itself after the timeout", function()
      stub_server({})
      help.show({ timeout = 30 })
      assert.is_not_nil(float())
      vim.wait(1000, function()
        return float() == nil
      end, 10)
      assert.is_nil(float())
    end)

    it("is not shown when the cursor moved while the server thought", function()
      stub_server({})
      vim.lsp.buf_request_all = function(_, _, _, cb)
        api.nvim_win_set_cursor(0, { 1, 0 })
        cb({})
      end
      help.show()
      assert.is_nil(float())
    end)
  end)

  describe("with a signature", function()
    it("opens no feedback float and hands the border to the core call", function()
      stub_server({ [1] = { result = { signatures = { { label = "foo(a)" } } } } })
      help.show({ border = "double" })
      assert.is_nil(float())
      assert.are.equal("double", saved.native_cfg.border)
    end)
  end)

  describe("wiring", function()
    it("the signature_help key goes through lsp.nvim, not the bare core call", function()
      local spec = require("lsp.config.KEYMAPS").entries.signature_help
      assert.are_not.equal(saved.signature_help, spec.rhs)
      stub_server({ [1] = { result = { signatures = { { label = "foo(a)" } } } } })
      spec.rhs()
      assert.are.equal("rounded", saved.native_cfg.border)
    end)

    it("the border is a documented, defaulted option", function()
      assert.are.equal("rounded", require("lsp.config.DEFAULTS").tools.lsp_signature.border)
    end)
  end)
end)
