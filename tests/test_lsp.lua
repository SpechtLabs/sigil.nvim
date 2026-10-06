local MiniTest = require("mini.test")
local H = require("tests.helpers")

local child = H.new_child()
local T = H.set(child)

local policy = vim.fs.joinpath(H.workspace, "oncall", "routing.sigil")

local function attached()
  return H.wait(child, "#vim.lsp.get_clients({ bufnr = 0, name = 'sigil' }) > 0")
end

T["client_config()"] = MiniTest.new_set({
  parametrize = {
    { "the default cmd", {}, "conf.cmd", { "sigil", "lsp", "--stdio" } },
    { "path in the cmd", { path = "/opt/sigil/bin/sigil" }, "conf.cmd", { "/opt/sigil/bin/sigil", "lsp", "--stdio" } },
    {
      "cmd over path",
      { path = "/x", lsp = { cmd = { "mise", "x", "--", "sigil", "lsp" } } },
      "conf.cmd",
      { "mise", "x", "--", "sigil", "lsp" },
    },
    { "the root markers", {}, "conf.root_markers", { "sigil.yaml", ".git" } },
    { "other root markers", { lsp = { root_markers = { "policies" } } }, "conf.root_markers", { "policies" } },
    {
      "settings",
      { lsp = { settings = { sigil = { trace = "on" } } } },
      "conf.settings",
      { sigil = { trace = "on" } },
    },
    { "init_options", { lsp = { init_options = { a = 1 } } }, "conf.init_options", { a = 1 } },
    { "no enabled field", {}, "conf.enabled == nil", true },
    { "no capabilities without nvim-cmp", {}, "conf.capabilities == nil", true },
  },
})
T["client_config()"]["resolves"] = function(_, opts, expr, want)
  local got = child.lua(
    [[
    local opts, expr = ...
    local options = require("sigil.config").set(opts)
    local conf = require("sigil.lsp").client_config(options)
    return loadstring("local conf = ...; return " .. expr)(conf)
  ]],
    { opts, expr }
  )
  H.eq(got, want)
end

T["client_config() merges nvim-cmp's capabilities under the user's"] = function()
  local caps = child.lua([[
    package.preload.cmp_nvim_lsp = function()
      return { default_capabilities = function()
        return { textDocument = { completion = { completionItem = { snippetSupport = true } } }, cmp = true }
      end }
    end
    local options = require("sigil.config").set({ lsp = { capabilities = { cmp = false } } })
    return require("sigil.lsp").client_config(options).capabilities
  ]])
  H.eq(caps, { textDocument = { completion = { completionItem = { snippetSupport = true } } }, cmp = false })
end

T["setup() layers over lsp/sigil.lua"] = function()
  child.lua([[require("sigil").setup({ path = "/opt/sigil" })]])
  H.eq(child.lua_get("vim.lsp.config.sigil.filetypes"), { "sigil" })
  H.eq(child.lua_get("vim.lsp.config.sigil.cmd"), { "/opt/sigil", "lsp", "--stdio" })
end

T["a missing binary"] = MiniTest.new_set()

T["a missing binary"]["leaves the server off"] = function()
  child.lua([[require("sigil").setup()]])
  H.eq(child.lua_get("vim.lsp.is_enabled('sigil')"), false)
end

T["a missing binary"]["warns once, in the first sigil buffer"] = function()
  child.lua([[require("sigil").setup()]])
  H.eq(child.lua_get("#_G.notifications"), 0)
  child.cmd("edit " .. policy)
  child.cmd("edit " .. vim.fs.joinpath(H.workspace, "alert_routing.sigil"))
  local notes = child.lua_get("_G.notifications")
  H.eq(#notes, 1)
  H.eq(notes[1].level, child.lua_get("vim.log.levels.WARN"))
  H.eq(notes[1].msg:find("brew install --cask spechtlabs/tap/sigil", 1, true) ~= nil, true)
  H.eq(notes[1].msg:find(":checkhealth sigil", 1, true) ~= nil, true)
end

T["a missing binary"]["doesn't warn with lsp.enabled = false"] = function()
  child.lua([[require("sigil").setup({ lsp = { enabled = false } })]])
  child.cmd("edit " .. policy)
  H.eq(child.lua_get("#_G.notifications"), 0)
  H.eq(child.lua_get("vim.lsp.is_enabled('sigil')"), false)
end

T["with a server"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.boot(nil, H.fake_bin("working"))
    end,
  },
})

T["with a server"]["attaches without setup()"] = function()
  child.cmd("edit " .. policy)
  H.eq(attached(), true)
  H.eq(child.lua_get("#_G.notifications"), 0)
end

T["with a server"]["root"] = MiniTest.new_set({
  parametrize = {
    { "sigil.yaml", vim.fs.joinpath("tests", "fixtures", "workspace", "oncall", "routing.sigil"), H.workspace },
    { ".git", vim.fs.joinpath("tests", "fixtures", "loose.sigil"), H.root },
  },
})
T["with a server"]["root"]["found by"] = function(_, file, want)
  child.cmd("edit " .. vim.fs.joinpath(H.root, file))
  H.eq(attached(), true)
  H.eq(child.lua_get("vim.lsp.get_clients({ bufnr = 0, name = 'sigil' })[1].root_dir"), want)
end

T["with a server"]["runs without a root outside a project"] = function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  child.cmd("edit " .. vim.fs.joinpath(dir, "scratch.sigil"))
  H.eq(attached(), true)
  H.eq(child.lua_get("vim.lsp.get_clients({ bufnr = 0, name = 'sigil' })[1].root_dir"), vim.NIL)
end

T["with a server"]["completes through the client"] = function()
  child.cmd("edit " .. policy)
  H.eq(attached(), true)
  local labels = child.lua([[
    local params = vim.lsp.util.make_position_params(0, "utf-16")
    local res = vim.lsp.buf_request_sync(0, "textDocument/completion", params, 3000)
    local labels = {}
    for _, r in pairs(res or {}) do
      for _, item in ipairs(r.result or {}) do
        labels[#labels + 1] = item.label
      end
    end
    return labels
  ]])
  H.eq(labels, { "fake_completion" })
end

T["with a server"][":Sigil restart starts a new client"] = function()
  child.cmd("edit " .. policy)
  H.eq(attached(), true)
  local before = child.lua_get("vim.lsp.get_clients({ bufnr = 0, name = 'sigil' })[1].id")
  child.cmd("Sigil restart")
  H.eq(
    H.wait(
      child,
      ("(vim.lsp.get_clients({ bufnr = 0, name = 'sigil' })[1] or {}).id ~= nil and vim.lsp.get_clients({ bufnr = 0, name = 'sigil' })[1].id ~= %d"):format(
        before
      )
    ),
    true
  )
end

T["with a server"]["setup() with lsp.enabled = false stops it"] = function()
  child.cmd("edit " .. policy)
  H.eq(attached(), true)
  child.lua([[require("sigil").setup({ lsp = { enabled = false } })]])
  H.eq(H.wait(child, "#vim.lsp.get_clients({ name = 'sigil' }) == 0"), true)
end

T["probe()"] = MiniTest.new_set({
  parametrize = {
    { "a server", { vim.fs.joinpath(H.fake_bin("working"), "sigil"), "lsp", "--stdio" }, "fake-sigil", vim.NIL },
    {
      "a release before sigil lsp",
      { vim.fs.joinpath(H.fake_bin("placeholder"), "sigil"), "lsp", "--stdio" },
      vim.NIL,
      'exited with status 1: Error: "sigil lsp" is not implemented yet',
    },
  },
})
T["probe()"]["answers for"] = function(_, cmd, name, err)
  local got = child.lua(
    [[
    local result, err = require("sigil.lsp").probe(..., { timeout = 5000 })
    return { result and result.server_info.name or vim.NIL, err or vim.NIL }
  ]],
    { cmd }
  )
  H.eq(got, { name, err })
end

T["probe()"]["reports a binary that isn't there"] = function()
  local err = child.lua([[return select(2, require("sigil.lsp").probe({ "/nonexistent/sigil", "lsp" }))]])
  H.eq(type(err), "string")
  H.eq(err:find("nonexistent", 1, true) ~= nil or err:find("ENOENT", 1, true) ~= nil, true)
end

return T
