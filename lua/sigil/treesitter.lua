-- Tree-sitter: registers the sigil parser with nvim-treesitter and turns on
-- highlighting, indentation and folding in sigil buffers. Everything here
-- degrades to a no-op when nvim-treesitter or the parser is missing.

local config = require("sigil.config")

local M = {}

local install_started = false

--- Which nvim-treesitter is on the runtimepath: "main" (the rewrite, Neovim
--- 0.12), "master" (the frozen branch) or nil. It looks at loaded modules
--- first and only then requires one, so the check doesn't load
--- nvim-treesitter early by itself unless the caller wants it to.
---@param load? boolean require nvim-treesitter.parsers when it isn't loaded yet
---@return "main"|"master"|nil
function M.flavor(load)
  local parsers = package.loaded["nvim-treesitter.parsers"]
  if parsers == nil and load then
    local ok, mod = pcall(require, "nvim-treesitter.parsers")
    parsers = ok and mod or nil
  end
  if type(parsers) ~= "table" then
    return nil
  end
  if type(parsers.get_parser_configs) == "function" then
    return "master"
  end
  return "main"
end

--- The install_info table nvim-treesitter's `main` branch reads. It installs the
--- grammar's own queries next to the parser, where they come first on the
--- runtimepath, so the queries always match the parser that was built, even
--- before `:TSUpdate` catches up with a new pin. queries/sigil/ in the plugin
--- serves everyone else.
---@param opts? sigil.TreesitterOptions
---@return table
function M.install_info(opts)
  opts = opts or config.options.treesitter
  if opts.path then
    return { path = opts.path, queries = "queries" }
  end
  return {
    url = opts.url,
    location = opts.location,
    revision = opts.revision,
    queries = opts.location .. "/queries",
  }
end

--- The install_info table nvim-treesitter's `master` branch reads.
---@param opts? sigil.TreesitterOptions
---@return table
function M.master_install_info(opts)
  opts = opts or config.options.treesitter
  local info = {
    url = opts.path or opts.url,
    files = { "src/parser.c" },
    revision = not opts.path and opts.revision or nil,
    requires_generate_from_grammar = false,
  }
  if not opts.path then
    info.location = opts.location
  end
  return info
end

--- Adds sigil to nvim-treesitter's parser table. The `main` branch calls this
--- from its `User TSUpdate` event, which it fires whenever it reloads the
--- table; on `master` it runs on the first sigil buffer and from setup().
---@return boolean registered
function M.register()
  local opts = config.options.treesitter
  if not opts.enabled then
    return false
  end
  local flavor = M.flavor(true)
  local parsers = package.loaded["nvim-treesitter.parsers"]
  if flavor == "main" then
    parsers.sigil = {
      install_info = M.install_info(opts),
      maintainers = { "@SpechtLabs" },
      tier = 2,
    }
    return true
  elseif flavor == "master" then
    parsers.get_parser_configs().sigil = {
      install_info = M.master_install_info(opts),
      filetype = "sigil",
      maintainers = { "@SpechtLabs" },
    }
    return true
  end
  return false
end

--- Whether Neovim can load the sigil parser.
---@return boolean
function M.has_parser()
  local ok, loaded = pcall(vim.treesitter.language.add, "sigil")
  return ok and loaded == true
end

--- Whether a query for the sigil language exists on the runtimepath.
---@param name string such as "highlights" or "indents"
---@return boolean
function M.has_query(name)
  return #vim.treesitter.query.get_files("sigil", name) > 0
end

---@param buf integer
local function start(buf)
  local opts = config.options.treesitter
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "sigil" then
    return
  end
  if opts.highlight and M.has_query("highlights") and not vim.treesitter.highlighter.active[buf] then
    pcall(vim.treesitter.start, buf, "sigil")
  end
  if opts.indent and M.has_query("indents") then
    local flavor = M.flavor()
    if flavor == "main" then
      vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    elseif flavor == "master" then
      vim.bo[buf].indentexpr = "nvim_treesitter#indent()"
    end
  end
  if opts.fold and M.has_query("folds") then
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      vim.wo[win][0].foldmethod = "expr"
      vim.wo[win][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
    end
  end
end

-- Builds the parser with nvim-treesitter's `main` branch, once a session, and
-- starts tree-sitter in every sigil buffer when it's done. `master` builds
-- with its own compiler setup and has `:TSInstall sigil` for that.
local function install()
  if install_started or M.flavor(true) ~= "main" or vim.fn.executable("tree-sitter") == 0 then
    return
  end
  install_started = true
  local ok, ts = pcall(require, "nvim-treesitter")
  if not ok or type(ts.install) ~= "function" then
    return
  end
  ts.install({ "sigil" }):await(function()
    vim.schedule(function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buf].filetype == "sigil" then
          start(buf)
        end
      end
    end)
  end)
end

--- Sets up tree-sitter for a sigil buffer: highlighting, indentation and
--- folding when the parser is installed, otherwise an install when
--- `ensure_installed` is on.
---@param buf integer
function M.attach(buf)
  local opts = config.options.treesitter
  if not opts.enabled then
    return
  end
  if M.flavor(true) == "master" then
    M.register()
  end
  if M.has_parser() then
    start(buf)
  elseif opts.ensure_installed then
    install()
  end
end

return M
