-- The language server: configures and enables the `sigil` config that
-- lsp/sigil.lua puts on the runtimepath, warns once when the binary is
-- missing, and restarts and probes the server.

local config = require("sigil.config")

local M = {}

M.name = "sigil"

M.install_hint = "brew install --cask spechtlabs/tap/sigil, or mise use -g github:SpechtLabs/sigil"

local warned = false

--- The absolute path of the binary the language server command runs, or nil
--- when it isn't executable. A function `cmd` can't be checked and counts as
--- found.
---@param options? sigil.Options
---@return string? path
---@return boolean checkable
function M.executable(options)
  local cmd = config.lsp_cmd(options)
  if type(cmd) == "function" then
    return nil, false
  end
  local path = vim.fn.exepath(cmd[1])
  return path ~= "" and path or nil, true
end

-- Capabilities a completion plugin adds. blink.cmp registers its own through
-- vim.lsp.config("*") on Neovim 0.11+, so only nvim-cmp needs this.
---@return lsp.ClientCapabilities?
local function completion_capabilities()
  local ok, cmp = pcall(require, "cmp_nvim_lsp")
  if ok and type(cmp.default_capabilities) == "function" then
    return cmp.default_capabilities()
  end
end

--- The vim.lsp.Config the plugin layers over lsp/sigil.lua.
---@param options? sigil.Options
---@return vim.lsp.Config
function M.client_config(options)
  options = options or config.options
  local conf = vim.deepcopy(options.lsp) --[[@as vim.lsp.Config]]
  conf.enabled = nil ---@diagnostic disable-line: inject-field
  conf.cmd = config.lsp_cmd(options)
  local caps = completion_capabilities()
  if caps then
    conf.capabilities = vim.tbl_deep_extend("force", caps, conf.capabilities or {})
  end
  return conf
end

--- Configures the `sigil` server and enables it when its binary is found.
--- Disabling stops running clients.
---@param options? sigil.Options
function M.setup(options)
  options = options or config.options
  if not options.lsp.enabled then
    vim.lsp.enable(M.name, false)
    return
  end
  vim.lsp.config(M.name, M.client_config(options))
  local path, checkable = M.executable(options)
  if checkable and not path then
    return
  end
  vim.lsp.enable(M.name)
end

--- Warns once a session, in the first sigil buffer, when the language server
--- is on but its binary isn't there.
---@param options? sigil.Options
---@return boolean warned
function M.warn_missing(options)
  options = options or config.options
  if warned or not options.lsp.enabled then
    return false
  end
  local path, checkable = M.executable(options)
  if path or not checkable then
    return false
  end
  warned = true
  local cmd = config.lsp_cmd(options) --[[@as string[] ]]
  vim.notify(
    ("sigil.nvim: `%s` isn't executable, so the language server is off.\nInstall it with %s, then run :checkhealth sigil."):format(
      cmd[1],
      M.install_hint
    ),
    vim.log.levels.WARN,
    { title = "sigil.nvim" }
  )
  return true
end

--- Stops every sigil client and starts them again for the buffers they had.
---@param timeout? integer milliseconds to wait for a clean stop before forcing it
function M.restart(timeout)
  local clients = vim.lsp.get_clients({ name = M.name })
  for _, client in ipairs(clients) do
    client:stop()
  end
  local stopped = vim.wait(timeout or 3000, function()
    for _, client in ipairs(clients) do
      if not client:is_stopped() then
        return false
      end
    end
    return true
  end, 20)
  if not stopped then
    for _, client in ipairs(clients) do
      client:stop(true)
    end
  end
  M.setup()
end

-- Splits complete LSP messages off the front of buf.
---@param buf string
---@return table[] messages
---@return string rest
local function decode(buf)
  local messages = {}
  while true do
    local header_end = buf:find("\r\n\r\n", 1, true)
    if not header_end then
      break
    end
    local length = tonumber(buf:sub(1, header_end):match("[Cc]ontent%-[Ll]ength: *(%d+)"))
    if not length or #buf < header_end + 3 + length then
      break
    end
    local body = buf:sub(header_end + 4, header_end + 3 + length)
    buf = buf:sub(header_end + 4 + length)
    local ok, msg = pcall(vim.json.decode, body)
    if ok and type(msg) == "table" then
      messages[#messages + 1] = msg
    end
  end
  return messages, buf
end

---@class sigil.ProbeResult
---@field server_info? { name: string, version?: string }
---@field capabilities table

--- Starts the language server on its own, sends `initialize` and returns what
--- it answered. This tells a working server from a binary that predates
--- `sigil lsp`, which exits with an error instead.
---@param cmd string[]
---@param opts? { timeout?: integer, root?: string }
---@return sigil.ProbeResult? result
---@return string? error
function M.probe(cmd, opts)
  opts = opts or {}
  local stdout, stderr = "", ""
  local response, exit_code
  local ok, proc = pcall(vim.system, cmd, {
    stdin = true,
    cwd = opts.root,
    stdout = function(_, data)
      if data then
        stdout = stdout .. data
      end
    end,
    stderr = function(_, data)
      if data then
        stderr = stderr .. data
      end
    end,
  }, function(out)
    exit_code = out.code
  end)
  if not ok then
    return nil, tostring(proc)
  end
  local body = vim.json.encode({
    jsonrpc = "2.0",
    id = 1,
    method = "initialize",
    params = {
      processId = vim.NIL,
      rootUri = opts.root and vim.uri_from_fname(opts.root) or vim.NIL,
      capabilities = vim.empty_dict(),
    },
  })
  pcall(proc.write, proc, ("Content-Length: %d\r\n\r\n%s"):format(#body, body))
  vim.wait(opts.timeout or 5000, function()
    local messages
    messages, stdout = decode(stdout)
    for _, msg in ipairs(messages) do
      if msg.id == 1 then
        response = msg
      end
    end
    return response ~= nil or exit_code ~= nil
  end, 10)
  pcall(proc.kill, proc, "sigterm")
  if response and response.result then
    return { server_info = response.result.serverInfo, capabilities = response.result.capabilities or {} }
  elseif response and response.error then
    return nil, ("initialize failed: %s"):format(response.error.message or vim.inspect(response.error))
  elseif exit_code then
    local first = vim.trim(stderr):match("[^\n]+") or ""
    return nil, ("exited with status %d%s"):format(exit_code, first ~= "" and (": " .. first) or "")
  end
  return nil, "no answer to initialize"
end

return M
