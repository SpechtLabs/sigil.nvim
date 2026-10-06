-- The init file of every child Neovim the tests start: the plugin and
-- mini.test on the runtimepath, nothing from your own config.

local root = vim.env.SIGIL_NVIM_ROOT
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fs.joinpath(root, ".tests", "deps", "mini.test"))
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"

-- A test sets up what has to exist before plugin/sigil.lua runs, such as
-- vim.g.sigil, as Lua in SIGIL_TEST_PRE; see child.boot() in helpers.lua.
if (vim.env.SIGIL_TEST_PRE or "") ~= "" then
  assert(loadstring(vim.env.SIGIL_TEST_PRE))()
end

-- Notifications go to a list the tests read, not to a hit-enter prompt that
-- would block the child.
_G.notifications = {}
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(msg, level)
  table.insert(_G.notifications, { msg = msg, level = level })
end
