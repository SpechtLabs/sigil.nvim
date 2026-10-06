-- Runs the test suite headless:
--
--   nvim -l tests/run.lua                    every tests/test_*.lua
--   nvim -l tests/run.lua tests/test_lsp.lua one file
--
-- It clones the pinned test dependencies into .tests/deps, points every XDG
-- directory and NVIM_APPNAME at .tests/, so no test reads or writes your own
-- Neovim config or data, and exits non-zero when a case fails.
--
-- Optional environment:
--   SIGIL_TEST_BIN=/path/to/sigil  binary for the end-to-end test (default: sigil in $PATH)
--   SIGIL_TEST_INSTALL=1           build the parser with nvim-treesitter main (needs network,
--                                  the tree-sitter CLI and a C compiler)

local root =
  vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))))
local deps = vim.fs.joinpath(root, ".tests", "deps")

-- Renovate doesn't see these; bump them by hand.
local pins = {
  ["mini.test"] = { "https://github.com/nvim-mini/mini.test", "a9e23fd2033ada30a53a32d1c73629351c2750f3" }, -- v0.9.0
  ["lazy.nvim"] = { "https://github.com/folke/lazy.nvim", "85c7ff3711b730b4030d03144f6db6375044ae82" }, -- v11.17.5
  ["nvim-treesitter"] = {
    "https://github.com/nvim-treesitter/nvim-treesitter",
    "e289100ff98969e118c702199d88b764ce9e7fdf",
  }, -- main
  ["nvim-treesitter-master"] = {
    "https://github.com/nvim-treesitter/nvim-treesitter",
    "cf12346a3414fa1b06af75c79faebe7f76df080a",
  }, -- master
}

local function git(args, cwd, may_fail)
  local out = vim.system(vim.list_extend({ "git" }, args), { cwd = cwd, text = true }):wait()
  if out.code ~= 0 and may_fail then
    return ""
  elseif out.code ~= 0 then
    io.stderr:write(("git %s failed: %s\n"):format(table.concat(args, " "), out.stderr))
    os.exit(2)
  end
  return vim.trim(out.stdout)
end

for name, pin in pairs(pins) do
  local dir = vim.fs.joinpath(deps, name)
  if not vim.uv.fs_stat(dir) then
    vim.fn.mkdir(dir, "p")
    git({ "init", "-q" }, dir)
    git({ "remote", "add", "origin", pin[1] }, dir)
  end
  if git({ "rev-parse", "--verify", "-q", "HEAD" }, dir, true) ~= pin[2] then
    io.stdout:write(("fetching %s at %s\n"):format(name, pin[2]:sub(1, 12)))
    git({ "fetch", "-q", "--depth", "1", "origin", pin[2] }, dir)
    git({ "checkout", "-q", "--force", "FETCH_HEAD" }, dir)
  end
end

local home = vim.fs.joinpath(root, ".tests", "home")
for _, var in ipairs({ "CONFIG", "DATA", "STATE", "CACHE" }) do
  local dir = vim.fs.joinpath(home, var:lower())
  vim.fn.mkdir(dir, "p")
  vim.env["XDG_" .. var .. "_HOME"] = dir
end
vim.env.NVIM_APPNAME = "sigil-nvim-test"
vim.env.NVIM_LISTEN_ADDRESS = nil
vim.env.SIGIL_NVIM_ROOT = root

vim.opt.rtp:prepend(vim.fs.joinpath(deps, "mini.test"))
local MiniTest = require("mini.test")

local files = {}
for i = 1, #(_G.arg or {}) do
  files[#files + 1] = vim.fn.fnamemodify(_G.arg[i], ":p")
end
if #files == 0 then
  files = vim.fn.globpath(vim.fs.joinpath(root, "tests"), "test_*.lua", false, true)
  table.sort(files)
end

MiniTest.run({
  collect = {
    find_files = function()
      return files
    end,
  },
  execute = { reporter = MiniTest.gen_reporter.stdout({ group_depth = 2, quit_on_finish = false }) },
})
vim.wait(30 * 60 * 1000, function()
  return not MiniTest.is_executing()
end, 50)

local failed = 0
for _, case in ipairs(MiniTest.current.all_cases or {}) do
  local state = case.exec and case.exec.state or ""
  if state:find("Fail") then
    failed = failed + 1
  end
end
os.exit(failed > 0 and 1 or 0)
