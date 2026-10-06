-- Installing the plugin the way the README says, with lazy.nvim and with
-- Neovim's own vim.pack.

local MiniTest = require("mini.test")
local H = require("tests.helpers")

local child = H.new_child()
local T = H.set(child)

local policy = vim.fs.joinpath(H.workspace, "oncall", "routing.sigil")

-- Boots a child whose init sets up lazy.nvim with spec, the way a user's
-- init.lua does, with LazyVim's `defaults.lazy = true`.
local function lazy(spec)
  local state = vim.fn.tempname()
  child.boot(
    ([[
    vim.opt.rtp:remove(vim.env.SIGIL_NVIM_ROOT)
    vim.opt.rtp:prepend(%q)
    require("lazy").setup({
      spec = { %s },
      defaults = { lazy = true },
      install = { missing = false },
      rocks = { enabled = false },
      change_detection = { enabled = false },
      checker = { enabled = false },
      pkg = { cache = %q },
      state = %q,
      lockfile = %q,
    })
  ]]):format(
      vim.fs.joinpath(H.deps, "lazy.nvim"),
      spec,
      state .. "/pkg-cache.lua",
      state .. "/state.json",
      state .. "/lock.json"
    )
  )
end

local spec = ("{ dir = %q }"):format(H.root)

T["lazy.nvim"] = MiniTest.new_set()

T["lazy.nvim"]["loads the one-line spec at startup despite defaults.lazy"] = function()
  lazy(spec)
  H.eq(child.lua_get("vim.g.loaded_sigil"), true)
  H.eq(child.lua_get("require('sigil').is_configured()"), true)
end

T["lazy.nvim"]["passes opts to setup()"] = function()
  lazy(("{ dir = %q, opts = { lsp = { enabled = false } } }"):format(H.root))
  H.eq(child.lua_get("require('sigil.config').options.lsp.enabled"), false)
end

T["lazy.nvim"]["sets up sigil buffers"] = function()
  lazy(spec)
  child.cmd("edit " .. policy)
  H.eq({ child.bo.filetype, child.bo.commentstring }, { "sigil", "// %s" })
  H.eq(child.lua_get("vim.lsp.config.sigil.filetypes"), { "sigil" })
end

T["vim.pack"] = function()
  if child.lua_get("vim.pack == nil") then
    MiniTest.skip("vim.pack needs Neovim 0.12")
  end
  if vim.system({ "git", "-C", H.root, "rev-parse", "--verify", "-q", "HEAD" }):wait().code ~= 0 then
    MiniTest.skip("vim.pack installs a git commit, and the checkout has none")
  end
  local head = vim.trim(vim.system({ "git", "-C", H.root, "rev-parse", "HEAD" }, { text = true }):wait().stdout)
  -- vim.pack reads its clone's origin/HEAD, which a clone of a detached HEAD
  -- doesn't have, and CI checks out a pull request as a detached merge
  -- commit. So it installs from a scratch repository with HEAD on a branch.
  local repo = vim.fn.tempname()
  for _, cmd in ipairs({
    { "git", "init", "-q", "-b", "main", repo },
    { "git", "-C", repo, "fetch", "-q", "--depth", "1", H.root, "HEAD" },
    { "git", "-C", repo, "reset", "-q", "--hard", "FETCH_HEAD" },
  }) do
    local res = vim.system(cmd, { text = true }):wait()
    H.eq({ table.concat(cmd, " "), res.code }, { table.concat(cmd, " "), 0 })
  end
  child.boot("vim.opt.rtp:remove(vim.env.SIGIL_NVIM_ROOT)")
  -- The commit, not the branch, so the test installs what it checks.
  child.lua(
    [[
    local src, version = ...
    -- A fresh install each run, not the commit an earlier run installed.
    vim.fn.delete(vim.fn.stdpath("data") .. "/site/pack/core", "rf")
    vim.fn.delete(vim.fn.stdpath("config") .. "/nvim-pack-lock.json")
    -- --clean leaves the data directory out of 'packpath'; a normal start has it.
    vim.opt.packpath:prepend(vim.fn.stdpath("data") .. "/site")
    vim.pack.add({ { src = src, name = "sigil.nvim", version = version } }, { confirm = false })
    require("sigil").setup()
  ]],
    { "file://" .. repo, head }
  )
  child.cmd("edit " .. policy)
  H.eq({ child.bo.filetype, child.lua_get("vim.g.loaded_sigil") }, { "sigil", true })
end

return T
