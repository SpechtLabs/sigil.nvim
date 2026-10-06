local MiniTest = require("mini.test")
local H = require("tests.helpers")

local child = H.new_child()
local T = H.set(child)

-- Applies vim.g.sigil = g and config.set(opts) in the child, then evaluates
-- expr with `options` and `err` in scope. vim.NIL stands for nil, which a
-- parametrize row can't hold.
local function set(g, opts, expr)
  return child.lua(
    [[
    local args = ...
    vim.g.sigil = args.g ~= vim.NIL and args.g or nil
    local options, err = require("sigil.config").set(args.opts ~= vim.NIL and args.opts or nil)
    return loadstring("local options, err = ...; return " .. args.expr)(options, err)
  ]],
    { { g = g, opts = opts, expr = expr } }
  )
end

local none = vim.NIL

T["set() merges"] = MiniTest.new_set({
  parametrize = {
    { "defaults", none, none, "vim.deep_equal(options, require('sigil.config').defaults)", true },
    { "path", none, { path = "/opt/bin/sigil" }, "options.path", "/opt/bin/sigil" },
    {
      "a nested option",
      none,
      { treesitter = { fold = true } },
      "{ options.treesitter.fold, options.treesitter.highlight }",
      { true, true },
    },
    { "vim.g.sigil", { lsp = { enabled = false } }, none, "options.lsp.enabled", false },
    { "opts over vim.g.sigil", { path = "from-g" }, { path = "from-opts" }, "options.path", "from-opts" },
    {
      "vim.g.sigil and opts",
      { path = "from-g" },
      { treesitter = { indent = false } },
      "{ options.path, options.treesitter.indent }",
      { "from-g", false },
    },
    {
      "a list over the default list",
      none,
      { lsp = { root_markers = { "sigil.yaml" } } },
      "options.lsp.root_markers",
      { "sigil.yaml" },
    },
    {
      "any vim.lsp.Config field",
      none,
      { lsp = { init_options = { trace = true } } },
      "options.lsp.init_options",
      { trace = true },
    },
    {
      "an empty section",
      none,
      { treesitter = {} },
      "vim.deep_equal(options.treesitter, require('sigil.config').defaults.treesitter)",
      true,
    },
    { "a revision", none, { treesitter = { revision = "v1.2.3" } }, "options.treesitter.revision", "v1.2.3" },
    {
      "the pinned revision by default",
      none,
      none,
      "options.treesitter.revision == require('sigil.config').grammar_revision",
      true,
    },
    { "without an error", none, { path = "x" }, "err == nil", true },
  },
})
T["set() merges"]["into options"] = function(_, g, opts, expr, want)
  H.eq(set(g, opts, expr), want)
end

T["set() rejects"] = MiniTest.new_set({
  parametrize = {
    { "an unknown key", none, { tresitter = {} }, "sigil.nvim: unknown option `tresitter`" },
    {
      "an unknown nested key",
      none,
      { treesitter = { hightlight = true } },
      "sigil.nvim: unknown option `treesitter.hightlight`",
    },
    { "a wrong type", none, { path = 1 }, "sigil.nvim: option `path` must be a string, got number" },
    {
      "a wrong nested type",
      none,
      { lsp = { enabled = "yes" } },
      "sigil.nvim: option `lsp.enabled` must be a boolean, got string",
    },
    {
      "a cmd string",
      none,
      { lsp = { cmd = "sigil lsp" } },
      "sigil.nvim: option `lsp.cmd` must be a table or function, got string",
    },
    { "a bad vim.g.sigil", { path = false }, none, "sigil.nvim: option `path` must be a string, got boolean" },
    { "options that aren't a table", none, "sigil", "sigil.nvim: options must be a table, got string" },
  },
})
T["set() rejects"]["with an error"] = function(_, g, opts, want)
  H.eq(set(g, opts, "err"), want)
end

T["set() keeps the previous options on an error"] = function()
  child.lua([[require("sigil.config").set({ path = "/first" })]])
  H.eq(set(none, { path = 2 }, "options.path"), "/first")
end

T["lsp_cmd() resolves"] = MiniTest.new_set({
  parametrize = {
    { "the default", none, { "sigil", "lsp", "--stdio" } },
    { "path", { path = "/opt/sigil" }, { "/opt/sigil", "lsp", "--stdio" } },
    {
      "cmd over path",
      { path = "/opt/sigil", lsp = { cmd = { "mise", "x", "--", "sigil", "lsp" } } },
      { "mise", "x", "--", "sigil", "lsp" },
    },
  },
})
T["lsp_cmd() resolves"]["the command"] = function(_, opts, want)
  H.eq(set(none, opts, "require('sigil.config').lsp_cmd()"), want)
end

return T
