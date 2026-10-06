-- Shared pieces of the test files: a child Neovim with the plugin loaded,
-- and paths to the fixtures.

local MiniTest = require("mini.test")

local H = {}

H.root = vim.env.SIGIL_NVIM_ROOT
H.fixtures = vim.fs.joinpath(H.root, "tests", "fixtures")
H.workspace = vim.fs.joinpath(H.fixtures, "workspace")
H.deps = vim.fs.joinpath(H.root, ".tests", "deps")
H.eq = MiniTest.expect.equality
H.neq = MiniTest.expect.no_equality

-- The fake binaries call back into this Neovim to run the fake server.
vim.env.SIGIL_TEST_NVIM = vim.v.progpath

--- A child Neovim. child.boot(pre) (re)starts it with the plugin loaded; pre
--- is Lua that runs before any plugin, e.g. to set vim.g.sigil.
---@return table child
function H.new_child()
  local child = MiniTest.new_child_neovim() --[[@as table]]
  -- mini.test quits the child and then waits up to a second for its pty to
  -- close; stopping the job first makes that wait return at once.
  local stop = child.stop
  function child.stop()
    if child.is_running() then
      pcall(vim.fn.jobstop, child.job.id)
    end
    stop()
  end
  ---@param pre? string
  ---@param path? string directories prepended to $PATH, e.g. a fake sigil
  function child.boot(pre, path)
    -- The child inherits this process's environment when it starts.
    local saved_path = vim.env.PATH
    vim.env.PATH = path and (path .. ":" .. H.clean_path()) or H.clean_path()
    vim.env.SIGIL_TEST_PRE = pre or ""
    child.restart({ "-u", vim.fs.joinpath(H.root, "tests", "minimal_init.lua") })
    -- The child answers RPC before its startup is done, so poll for VimEnter.
    -- Not with vim.wait: it would run the next scheduled test case meanwhile.
    for _ = 1, 1000 do
      if child.lua_get("vim.v.vim_did_enter") == 1 then
        break
      end
      vim.uv.sleep(10)
    end
    vim.env.PATH = saved_path
    vim.env.SIGIL_TEST_PRE = nil
  end
  return child
end

--- $PATH without the directories that hold a sigil binary or the tree-sitter
--- CLI, so a test sees only the ones it puts there.
---@return string
function H.clean_path()
  local dirs = {}
  for dir in (vim.env.PATH or ""):gmatch("[^:]+") do
    local sigil = vim.fn.executable(vim.fs.joinpath(dir, "sigil")) == 1
    local ts = vim.fn.executable(vim.fs.joinpath(dir, "tree-sitter")) == 1
    if not sigil and not ts then
      dirs[#dirs + 1] = dir
    end
  end
  return table.concat(dirs, ":")
end

--- The directory of a fake sigil binary: "working" runs the fake language
--- server, "placeholder" exits like a release from before `sigil lsp`.
---@param name "working"|"placeholder"
---@return string
function H.fake_bin(name)
  return vim.fs.joinpath(H.fixtures, "bin", name)
end

--- A case set that boots a fresh child before each case and stops it after
--- the last.
---@param child table
---@param opts? table extra MiniTest.new_set options
function H.set(child, opts)
  return MiniTest.new_set(vim.tbl_deep_extend("force", {
    hooks = {
      pre_case = function()
        child.boot()
      end,
      post_once = child.stop,
    },
  }, opts or {}))
end

--- Waits in the child until the Lua expression expr is truthy. Wait in the
--- child, never in the test process: vim.wait there runs the next test case.
---@param child table
---@param expr string
---@param timeout? integer milliseconds
---@return boolean
function H.wait(child, expr, timeout)
  return child.lua(("return vim.wait(%d, function() return %s end, 20)"):format(timeout or 5000, expr))
end

return H
