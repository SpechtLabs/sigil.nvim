local MiniTest = require("mini.test")
local H = require("tests.helpers")

local child = H.new_child()
local T = H.set(child)

local main = vim.fs.joinpath(H.deps, "nvim-treesitter")

-- The lines of :checkhealth sigil, after booting with the given $PATH
-- prefix, setup() options and runtimepath additions.
local function health(path, opts, rtp)
  child.boot(nil, path)
  if rtp then
    child.lua("vim.opt.rtp:prepend(...)", { rtp })
  end
  if opts then
    child.lua("require('sigil').setup(...)", { opts })
  end
  child.cmd("checkhealth sigil")
  return table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

local function has(text, want)
  if not text:find(want, 1, true) then
    error(("checkhealth output lacks %q:\n%s"):format(want, text), 2)
  end
end

local function lacks(text, unwanted)
  if text:find(unwanted, 1, true) then
    error(("checkhealth output has %q:\n%s"):format(unwanted, text), 2)
  end
end

T["reports"] = MiniTest.new_set({
  parametrize = {
    { "the Neovim version", false, false, false, { "OK Neovim " .. tostring(vim.version()):match("^%d+%.%d+%.%d+") } },
    { "the filetype", false, false, false, { "OK `*.sigil` files get the `sigil` filetype" } },
    { "setup() not run", false, false, false, { "setup() hasn't run yet" } },
    {
      "a missing binary",
      false,
      false,
      false,
      {
        "ERROR `sigil` isn't executable or isn't in $PATH",
        "brew install --cask spechtlabs/tap/sigil",
        "mise use -g github:SpechtLabs/sigil",
      },
    },
    {
      "a working binary",
      "working",
      false,
      false,
      {
        "OK found " .. H.fake_bin("working") .. "/sigil, version v9.9.9-test",
        "answers initialize as fake-sigil 0.0.0",
      },
    },
    {
      "a binary from before sigil lsp",
      "placeholder",
      false,
      false,
      {
        "OK found " .. H.fake_bin("placeholder") .. "/sigil, version v0.7.3",
        'doesn\'t start a language server: exited with status 1: Error: "sigil lsp" is not implemented yet',
        "upgrade sigil",
      },
    },
    { "a disabled server", false, { lsp = { enabled = false } }, false, { "disabled with `lsp.enabled = false`" } },
    {
      "an lsp.cmd that works",
      false,
      {
        path = "/nowhere/sigil",
        lsp = { cmd = { vim.fs.joinpath(H.fake_bin("working"), "sigil"), "lsp", "--stdio" } },
      },
      false,
      { "`/nowhere/sigil` isn't in $PATH, so its version is unknown", "answers initialize as fake-sigil" },
    },
    {
      "an lsp.cmd that isn't there",
      false,
      { lsp = { cmd = { "/nope/sigil", "lsp" } } },
      false,
      { "`lsp.cmd` runs `/nope/sigil`, which isn't executable" },
    },
    {
      "the LSP config",
      false,
      {},
      false,
      {
        "OK config: cmd sigil lsp --stdio, root markers sigil.yaml, .sigil.yaml, sigil.json, .sigil.json, sigil.toml, .sigil.toml, .git",
      },
    },
    { "a missing nvim-treesitter", false, false, false, { "nvim-treesitter not found" } },
    {
      "nvim-treesitter main",
      false,
      false,
      main,
      {
        "OK nvim-treesitter `main` found",
        "OK parser registered: https://github.com/SpechtLabs/sigil, editors/tree-sitter-sigil, revision",
        "WARNING tree-sitter CLI not found",
        "WARNING parser not installed",
      },
    },
    {
      "disabled tree-sitter",
      false,
      { treesitter = { enabled = false } },
      false,
      { "disabled with `treesitter.enabled = false`" },
    },
  },
})
T["reports"]["on"] = function(_, bin, opts, rtp, wants)
  local text = health(bin and H.fake_bin(bin) or nil, opts or nil, rtp or nil)
  for _, want in ipairs(wants) do
    has(text, want)
  end
end

T["doesn't probe a disabled server"] = function()
  local text = health(H.fake_bin("placeholder"), { lsp = { enabled = false } })
  lacks(text, "doesn't start a language server")
end

T["sees vim.g.sigil before setup() runs"] = function()
  child.boot("vim.g.sigil = { path = '/nowhere/sigil' }")
  child.cmd("checkhealth sigil")
  has(table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n"), "`/nowhere/sigil` isn't executable")
end

return T
