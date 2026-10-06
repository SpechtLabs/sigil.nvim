-- The docs list every option, and the help file builds.

local MiniTest = require("mini.test")
local H = require("tests.helpers")

local child = H.new_child()
local T = H.set(child)

local function read(path)
  return table.concat(vim.fn.readfile(vim.fs.joinpath(H.root, path)), "\n")
end

-- Every option path in the defaults, such as "lsp.root_markers".
local function option_paths()
  return child.lua([[
    local paths = {}
    local function walk(prefix, tbl)
      for k, v in pairs(tbl) do
        local path = prefix .. k
        paths[#paths + 1] = path
        if type(v) == "table" and not vim.islist(v) and next(v) ~= nil and k ~= "settings" then
          walk(path .. ".", v)
        end
      end
    end
    walk("", require("sigil.config").defaults)
    -- Options whose default is nil.
    vim.list_extend(paths, { "lsp.cmd", "treesitter.path" })
    table.sort(paths)
    return paths
  ]])
end

T["every option is documented in"] = MiniTest.new_set({
  parametrize = { { "doc/sigil.txt" }, { "README.md" } },
})
T["every option is documented in"]["the file"] = function(file)
  local text = read(file)
  local missing = {}
  for _, path in ipairs(option_paths()) do
    local leaf = path:match("[^.]+$")
    if not text:find(leaf, 1, true) then
      missing[#missing + 1] = path
    end
  end
  H.eq(missing, {})
end

T["the help file has tags and builds"] = function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile(vim.fn.readfile(vim.fs.joinpath(H.root, "doc", "sigil.txt")), vim.fs.joinpath(dir, "sigil.txt"))
  child.cmd("helptags " .. dir)
  local tags = vim.fn.readfile(vim.fs.joinpath(dir, "tags"))
  local names = vim.tbl_map(function(line)
    return line:match("^[^\t]+")
  end, tags)
  for _, tag in ipairs({ "sigil.nvim", "sigil-setup", "sigil-config", ":Sigil", "sigil-health", "sigil-treesitter" }) do
    H.eq({ tag, vim.tbl_contains(names, tag) }, { tag, true })
  end
end

T[":help sigil opens the plugin's help"] = function()
  child.cmd("helptags " .. vim.fs.joinpath(H.root, "doc"))
  child.cmd("help sigil.nvim")
  H.eq(vim.fs.basename(child.api.nvim_buf_get_name(0)), "sigil.txt")
end

return T
