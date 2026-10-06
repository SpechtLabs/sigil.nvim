local MiniTest = require("mini.test")
local H = require("tests.helpers")

local child = H.new_child()
local T = H.set(child)

local policy = vim.fs.joinpath(H.workspace, "oncall", "routing.sigil")

T[":Sigil completes"] = MiniTest.new_set({
  parametrize = { { "", { "info", "log", "restart" } }, { "re", { "restart" } }, { "x", {} } },
})
T[":Sigil completes"]["subcommands"] = function(lead, want)
  H.eq(child.fn.getcompletion("Sigil " .. lead, "cmdline"), want)
end

T[":Sigil info"] = MiniTest.new_set()

T[":Sigil info"]["without a binary"] = function()
  child.cmd("edit " .. policy)
  local out = child.cmd_capture("Sigil info")
  H.eq(out:find("binary:      not found (brew install --cask spechtlabs/tap/sigil", 1, true) ~= nil, true)
  H.eq(out:find("client:      not attached to this buffer", 1, true) ~= nil, true)
  H.eq(out:find("tree-sitter: parser missing, nvim-treesitter not loaded, highlighting off", 1, true) ~= nil, true)
end

T[":Sigil info"]["with a server"] = function()
  child.boot(nil, H.fake_bin("working"))
  child.cmd("edit " .. policy)
  H.eq(H.wait(child, "#vim.lsp.get_clients({ bufnr = 0, name = 'sigil' }) > 0"), true)
  local out = child.cmd_capture("Sigil")
  H.eq(out:find("binary:      " .. H.fake_bin("working") .. "/sigil", 1, true) ~= nil, true)
  H.eq(out:find("root " .. H.workspace, 1, true) ~= nil, true)
end

T[":Sigil log opens the LSP log"] = function()
  child.cmd("Sigil log")
  H.eq(child.api.nvim_buf_get_name(0), child.lua_get("vim.lsp.log.get_filename()"))
end

T[":Sigil rejects an unknown subcommand"] = function()
  child.cmd("Sigil nope")
  local notes = child.lua_get("_G.notifications")
  H.eq(#notes, 1)
  H.eq(notes[1].msg, 'sigil.nvim: unknown subcommand "nope"; use one of: info, log, restart')
end

T["setup() reports a bad option"] = function()
  child.lua("require('sigil').setup({ pth = 'x' })")
  H.eq(child.lua_get("_G.notifications[1].msg"), "sigil.nvim: unknown option `pth`")
  H.eq(child.lua_get("require('sigil').is_configured()"), false)
end

return T
