local M = {}

---@class sigil.LspConfig: vim.lsp.Config
---@field enabled? boolean Start the language server in sigil buffers.

---@class sigil.TreesitterConfig
---@field enabled? boolean Register the parser with nvim-treesitter.
---@field ensure_installed? boolean Install the parser on the first sigil buffer when it's missing.
---@field highlight? boolean Start tree-sitter highlighting in sigil buffers.
---@field indent? boolean Indent with the tree-sitter indents query.
---@field fold? boolean Fold with the tree-sitter folds query.
---@field url? string Repository that holds the grammar.
---@field location? string Directory of the grammar inside the repository.
---@field revision? string Commit or tag of `url` to build. A branch works only without a `/` in its name.
---@field path? string Local checkout of the grammar directory; overrides url and revision.

---@class sigil.Config
---@field path? string The sigil binary: a name looked up in $PATH, or a path.
---@field lsp? sigil.LspConfig
---@field treesitter? sigil.TreesitterConfig

-- The options after merging: every field set but lsp.cmd and treesitter.path.
---@class sigil.Options: sigil.Config
---@field path string
---@field lsp sigil.LspOptions
---@field treesitter sigil.TreesitterOptions

---@class sigil.LspOptions: sigil.LspConfig
---@field enabled boolean

---@class sigil.TreesitterOptions: sigil.TreesitterConfig
---@field enabled boolean
---@field ensure_installed boolean
---@field highlight boolean
---@field indent boolean
---@field fold boolean
---@field url string
---@field location string
---@field revision string

-- The grammar revision the queries in queries/sigil/ were copied from: a
-- commit on sigil's main or a release tag. Move it with
-- `mise run queries -- --ref <tag or commit>`, which rewrites this line and
-- the queries together (README, "Moving the grammar pin").
M.grammar_revision = "b13b0507dd978c86139a56a160ba65de3a896fa5"

---@type sigil.Options
M.defaults = {
  path = "sigil",
  lsp = {
    enabled = true,
    -- nil runs `<path> lsp --stdio`.
    cmd = nil,
    root_markers = { "sigil.yaml", ".sigil.yaml", "sigil.json", ".sigil.json", "sigil.toml", ".sigil.toml", ".git" },
    settings = {},
  },
  treesitter = {
    enabled = true,
    ensure_installed = true,
    highlight = true,
    indent = true,
    fold = false,
    url = "https://github.com/SpechtLabs/sigil",
    location = "editors/tree-sitter-sigil",
    revision = M.grammar_revision,
    path = nil,
  },
}

---@type sigil.Options
M.options = vim.deepcopy(M.defaults)

-- An empty table is a list to vim.islist(), and `treesitter = {}` must keep
-- the defaults.
local function is_list(t)
  return type(t) == "table" and next(t) ~= nil and vim.islist(t)
end

-- Lists replace the default instead of merging into it index by index, so
-- `root_markers = { "sigil.yaml" }` drops `.git`.
---@param base table
---@param over table
---@return table
local function merge(base, over)
  local out = vim.deepcopy(base)
  for k, v in pairs(over) do
    if type(v) == "table" and type(out[k]) == "table" and not is_list(v) and not is_list(out[k]) then
      out[k] = merge(out[k], v)
    else
      out[k] = vim.deepcopy(v)
    end
  end
  return out
end

-- The checks reject what would otherwise fail later, far from the cause: a
-- misspelled key is silently ignored, a wrong type fails in the first sigil
-- buffer.
local schema = {
  [""] = { path = "string", lsp = "table", treesitter = "table" },
  lsp = { enabled = "boolean", cmd = { "table", "function" }, root_markers = "table", settings = "table" },
  treesitter = {
    enabled = "boolean",
    ensure_installed = "boolean",
    highlight = "boolean",
    indent = "boolean",
    fold = "boolean",
    url = "string",
    location = "string",
    revision = "string",
    path = "string",
  },
}

---@param opts table
---@return string? error
local function validate(opts)
  for section, fields in pairs(schema) do
    local tbl = section == "" and opts or opts[section]
    if type(tbl) == "table" then
      for key, value in pairs(tbl) do
        local want = fields[key]
        local prefix = section == "" and "" or section .. "."
        if want == nil then
          -- lsp takes any vim.lsp.Config field (capabilities, on_attach, ...).
          if section ~= "lsp" then
            return ("sigil.nvim: unknown option `%s%s`"):format(prefix, key)
          end
        else
          local types = type(want) == "table" and want or { want }
          if not vim.tbl_contains(types, type(value)) then
            return ("sigil.nvim: option `%s%s` must be a %s, got %s"):format(
              prefix,
              key,
              table.concat(types, " or "),
              type(value)
            )
          end
        end
      end
    end
  end
end

--- Merges the defaults, `vim.g.sigil` and `opts`, in that order, into
--- `M.options`. An invalid option keeps the previous options and returns the
--- error.
---@param opts? sigil.Config
---@return sigil.Options options
---@return string? error
function M.set(opts)
  local layers = { vim.g.sigil or {}, opts or {} }
  for _, layer in ipairs(layers) do
    if type(layer) ~= "table" then
      return M.options, "sigil.nvim: options must be a table, got " .. type(layer)
    end
    local err = validate(layer)
    if err then
      return M.options, err
    end
  end
  local options = M.defaults
  for _, layer in ipairs(layers) do
    options = merge(options, layer)
  end
  M.options = options
  return M.options
end

--- The command that starts the language server.
---@param options? sigil.Options
---@return string[]|fun(...): vim.lsp.rpc.PublicClient
function M.lsp_cmd(options)
  options = options or M.options
  return options.lsp.cmd or { options.path, "lsp", "--stdio" }
end

return M
