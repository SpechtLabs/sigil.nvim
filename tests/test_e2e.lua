-- Against a real sigil: SIGIL_TEST_BIN, or sigil in $PATH. Skips when there
-- is none, or when it predates the language server.

local MiniTest = require("mini.test")
local H = require("tests.helpers")

local child = H.new_child()
local bin = vim.env.SIGIL_TEST_BIN
if not bin or bin == "" then
  bin = vim.fn.exepath("sigil")
end

local policy = vim.fs.joinpath(H.workspace, "oncall", "routing.sigil")

-- Boots a child attached to the fixture policy, or skips the case. Each
-- case calls it: MiniTest.skip() in a hook wouldn't stop the case.
local function start()
  if bin == "" or vim.fn.executable(bin) == 0 then
    MiniTest.skip("no sigil binary; set SIGIL_TEST_BIN or put sigil in $PATH")
  end
  child.boot()
  local err = child.lua(
    "local _, err = require('sigil.lsp').probe({ ..., 'lsp', '--stdio' }, { timeout = 10000 }); return err or vim.NIL",
    { bin }
  )
  if err ~= vim.NIL then
    MiniTest.skip(("%s has no working language server: %s"):format(bin, err))
  end
  child.lua("require('sigil').setup({ path = ... })", { bin })
  child.cmd("edit " .. policy)
  H.eq(H.wait(child, "#vim.lsp.get_clients({ bufnr = 0, name = 'sigil' }) > 0", 10000), true)
end

local T = MiniTest.new_set({ hooks = { post_once = child.stop } })

local function set_lines(lines)
  child.api.nvim_buf_set_lines(0, 0, -1, true, lines)
end

T["attaches with the workspace as root"] = function()
  start()
  H.eq(child.lua_get("vim.lsp.get_clients({ bufnr = 0, name = 'sigil' })[1].root_dir"), H.workspace)
end

T["reports a misspelled field"] = function()
  start()
  set_lines({
    "policy oncall.routing: AlertRouting@1",
    "",
    "when alert.severty == critical {",
    "  page(reason: critical_alert, target: team.oncall)",
    "}",
  })
  H.eq(H.wait(child, "#vim.diagnostic.get(0) > 0", 10000), true)
  local diag = child.lua_get("vim.diagnostic.get(0)[1]")
  H.eq(diag.lnum, 2)
  H.eq(diag.message:find("severty", 1, true) ~= nil, true)
end

T["completes the fields of an input"] = function()
  start()
  set_lines({ "policy oncall.routing: AlertRouting@1", "", "when alert. {", "}" })
  local labels = child.lua([[
    vim.api.nvim_win_set_cursor(0, { 3, 11 })
    local params = vim.lsp.util.make_position_params(0, "utf-16")
    local res = vim.lsp.buf_request_sync(0, "textDocument/completion", params, 10000) or {}
    local labels = {}
    for _, r in pairs(res) do
      local items = r.result and (r.result.items or r.result) or {}
      for _, item in ipairs(items) do
        labels[#labels + 1] = item.label
      end
    end
    return labels
  ]])
  for _, field in ipairs({ "name", "severity", "labels", "firing_for" }) do
    H.eq({ field, vim.tbl_contains(labels, field) }, { field, true })
  end
end

T["formats like sigil fmt"] = function()
  start()
  set_lines({
    "policy oncall.routing: AlertRouting@1",
    "when alert.severity==critical {",
    "    page(reason: critical_alert, target: team.oncall)",
    "}",
  })
  child.lua("vim.lsp.buf.format({ name = 'sigil', timeout_ms = 10000 })")
  H.eq(child.api.nvim_buf_get_lines(0, 0, -1, true), {
    "policy oncall.routing: AlertRouting@1",
    "",
    "when alert.severity == critical {",
    "  page(reason: critical_alert, target: team.oncall)",
    "}",
  })
end

return T
