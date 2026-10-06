-- Buffer settings for sigil files. Set vim.g.sigil_recommended_style = false
-- to keep your own indentation settings.

if vim.b.did_ftplugin then
  return
end
vim.b.did_ftplugin = 1

-- `//` line comments are the only kind Sigil has.
vim.bo.commentstring = "// %s"
vim.bo.comments = "://"
vim.opt_local.formatoptions:remove("t")
vim.opt_local.formatoptions:append("croql")
vim.bo.suffixesadd = ".sigil"

local undo = "setlocal commentstring< comments< formatoptions< suffixesadd<"

if vim.g.sigil_recommended_style ~= false and vim.g.sigil_recommended_style ~= 0 then
  -- sigil fmt indents with two spaces. smartindent covers braces until the
  -- tree-sitter indents query takes over through indentexpr.
  vim.bo.expandtab = true
  vim.bo.shiftwidth = 2
  vim.bo.softtabstop = 2
  vim.bo.tabstop = 2
  vim.bo.autoindent = true
  vim.bo.smartindent = true
  undo = undo .. " expandtab< shiftwidth< softtabstop< tabstop< autoindent< smartindent<"
end

vim.b.undo_ftplugin = undo
