local MiniTest = require("mini.test")
local H = require("tests.helpers")

local child = H.new_child()
local T = H.set(child)

local policy = vim.fs.joinpath(H.workspace, "oncall", "routing.sigil")

T["detection"] = MiniTest.new_set({
  parametrize = {
    { "policy.sigil", "sigil" },
    { "/abs/path/kind_file.sigil", "sigil" },
    { "sigil.yaml", "yaml" },
    { "policy.sigl", vim.NIL },
  },
})
T["detection"]["of"] = function(name, want)
  H.eq(child.lua_get(("vim.filetype.match({ filename = %q })"):format(name)), want)
end

T["opening a .sigil file sets the filetype"] = function()
  child.cmd("edit " .. policy)
  H.eq(child.bo.filetype, "sigil")
end

T["buffer options"] = MiniTest.new_set({
  parametrize = {
    { "commentstring", "// %s" },
    { "comments", "://" },
    { "expandtab", true },
    { "shiftwidth", 2 },
    { "softtabstop", 2 },
    { "tabstop", 2 },
    { "suffixesadd", ".sigil" },
  },
})
T["buffer options"]["set"] = function(name, want)
  child.cmd("edit " .. policy)
  H.eq(child.bo[name], want)
end

T["formatoptions continue comments and don't wrap code"] = function()
  child.cmd("edit " .. policy)
  local fo = child.bo.formatoptions
  for _, flag in ipairs({ "c", "r", "o", "q", "l" }) do
    H.eq(fo:find(flag, 1, true) ~= nil, true)
  end
  H.eq(fo:find("t", 1, true), nil)
end

T["sigil_recommended_style = false keeps indentation settings"] = function()
  child.boot("vim.g.sigil_recommended_style = false")
  child.cmd("edit " .. policy)
  H.eq({ child.bo.shiftwidth, child.bo.expandtab, child.bo.commentstring }, { 8, false, "// %s" })
end

T["changing the filetype undoes the settings"] = function()
  child.cmd("edit " .. policy)
  child.cmd("setfiletype text | set filetype=text")
  H.eq({ child.bo.shiftwidth, child.bo.suffixesadd }, { 8, "" })
end

T["gcc comments a line with //"] = function()
  child.cmd("edit " .. policy)
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.cmd("normal gcc")
  H.eq(child.api.nvim_buf_get_lines(0, 2, 3, true), { "// when alert.severity == critical {" })
end

T["syntax fallback"] = MiniTest.new_set({
  parametrize = {
    { "when x {", 1, "sigilConditional" },
    { "use deploy.common", 1, "sigilImport" },
    { "use deploy.common", 5, "sigilNamespace" },
    { "let a = service.type == other", 17, "" },
    { "type Release {", 1, "sigilTypeDecl" },
    { "type Release {", 6, "sigilTypeName" },
    { "x in [a] and 30m > 5s", 3, "sigilWordOperator" },
    { "x in [a] and 30m > 5s", 14, "sigilDuration" },
    { 'x like "a\\n"', 10, "sigilEscape" },
    { "x matches `^a$`", 11, "sigilRawString" },
    { "count(x) // why", 1, "sigilCall" },
    { "count(x) // why", 13, "sigilComment" },
    { "duration: duration", 11, "sigilBuiltinType" },
  },
})
T["syntax fallback"]["highlights"] = function(line, col, group)
  child.cmd("enew | set filetype=sigil")
  child.api.nvim_buf_set_lines(0, 0, -1, true, { line })
  H.eq(child.b.current_syntax, "sigil")
  H.eq(child.lua_get(("vim.fn.synIDattr(vim.fn.synID(1, %d, 1), 'name')"):format(col)), group)
end

T["startup loads no module"] = function()
  H.eq(child.lua_get("vim.g.loaded_sigil"), true)
  local loaded = child.lua_get([[vim.tbl_filter(function(name)
    return name == "sigil" or vim.startswith(name, "sigil.")
  end, vim.tbl_keys(package.loaded))]])
  H.eq(loaded, {})
end

T["startup defines the command and autocommands"] = function()
  H.eq(child.fn.exists(":Sigil"), 2)
  H.eq(child.fn.exists("#sigil#FileType#sigil"), 1)
  H.eq(child.fn.exists("#sigil#User#TSUpdate"), 1)
end

T["the first sigil buffer applies vim.g.sigil"] = function()
  child.boot("vim.g.sigil = { lsp = { enabled = false } }")
  H.eq(child.lua_get("package.loaded.sigil == nil"), true)
  child.cmd("edit " .. policy)
  H.eq(child.lua_get("require('sigil').is_configured()"), true)
  H.eq(child.lua_get("require('sigil.config').options.lsp.enabled"), false)
end

return T
