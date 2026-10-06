-- sigil.nvim: Neovim support for the Sigil policy language.
--
-- plugin/sigil.lua calls attach() in every sigil buffer, which applies the
-- defaults and vim.g.sigil the first time unless setup() ran before.

local config = require("sigil.config")

local M = {}

local configured = false

--- Applies the options: merges them over the defaults and `vim.g.sigil`,
--- configures the language server and registers the tree-sitter parser.
--- Calling it again replaces the options. Optional: without it the plugin
--- runs with the defaults and `vim.g.sigil`.
---@param opts? sigil.Config
function M.setup(opts)
  local options, err = config.set(opts)
  if err then
    vim.notify(err, vim.log.levels.ERROR, { title = "sigil.nvim" })
    return
  end
  configured = true
  require("sigil.lsp").setup(options)
  -- Only when nvim-treesitter is loaded already; `main` asks for the parser
  -- through its TSUpdate event anyway, so setup never loads it early.
  if package.loaded["nvim-treesitter.parsers"] then
    require("sigil.treesitter").register()
  end
end

--- Whether setup() ran, directly or through the first sigil buffer.
---@return boolean
function M.is_configured()
  return configured
end

--- Sets up a sigil buffer: the language server's missing-binary warning and
--- tree-sitter. Runs from the FileType autocommand in plugin/sigil.lua.
---@param buf integer
function M.attach(buf)
  if not configured then
    M.setup()
  end
  require("sigil.lsp").warn_missing()
  require("sigil.treesitter").attach(buf)
end

---@param buf integer
---@return string[] lines
function M.info(buf)
  local lsp = require("sigil.lsp")
  local ts = require("sigil.treesitter")
  local options = config.options
  local cmd = config.lsp_cmd(options)
  local path, checkable = lsp.executable(options)
  local lines = {
    "sigil.nvim",
    ("  binary:      %s"):format(
      (not checkable and "custom cmd function") or path or ("not found (" .. lsp.install_hint .. ")")
    ),
    ("  lsp:         %s"):format(
      options.lsp.enabled and (type(cmd) == "table" and table.concat(cmd, " ") or "custom cmd") or "disabled"
    ),
  }
  local clients = vim.lsp.get_clients({ name = lsp.name, bufnr = buf })
  if #clients == 0 then
    lines[#lines + 1] = "  client:      not attached to this buffer"
  end
  for _, client in ipairs(clients) do
    lines[#lines + 1] = ("  client:      id %d, root %s"):format(client.id, client.root_dir or "none (single file)")
  end
  lines[#lines + 1] = ("  tree-sitter: parser %s, nvim-treesitter %s, highlighting %s"):format(
    ts.has_parser() and "installed" or "missing",
    ts.flavor() or "not loaded",
    vim.treesitter.highlighter.active[buf] and "on" or "off"
  )
  lines[#lines + 1] = "Run :checkhealth sigil for the full report."
  return lines
end

local subcommands = {
  info = function()
    local chunks = {}
    for _, line in ipairs(M.info(vim.api.nvim_get_current_buf())) do
      chunks[#chunks + 1] = { line .. "\n" }
    end
    vim.api.nvim_echo(chunks, false, {})
  end,
  restart = function()
    require("sigil.lsp").restart()
  end,
  log = function()
    vim.cmd.tabnew(vim.lsp.log.get_filename())
  end,
}

--- Runs a `:Sigil` subcommand.
---@param args string
function M.command(args)
  local name = vim.trim(args)
  if name == "" then
    name = "info"
  end
  local run = subcommands[name]
  if not run then
    vim.notify(
      ("sigil.nvim: unknown subcommand %q; use one of: %s"):format(name, table.concat(M.complete(""), ", ")),
      vim.log.levels.ERROR
    )
    return
  end
  if not configured then
    M.setup()
  end
  run()
end

--- Completes `:Sigil` subcommands.
---@param lead string
---@return string[]
function M.complete(lead)
  local names = vim.tbl_keys(subcommands)
  table.sort(names)
  return vim.tbl_filter(function(name)
    return vim.startswith(name, lead)
  end, names)
end

return M
