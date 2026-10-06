-- A language server just good enough for the tests: it answers initialize,
-- completion and shutdown. `nvim -l tests/fixtures/fake_server.lua`.

local function read()
  local length
  while true do
    local line = io.stdin:read("*l")
    if not line then
      os.exit(0)
    end
    line = line:gsub("\r$", "")
    if line == "" then
      break
    end
    length = tonumber(line:match("^[Cc]ontent%-[Ll]ength: *(%d+)")) or length
  end
  return vim.json.decode(io.stdin:read(length))
end

local function send(msg)
  msg.jsonrpc = "2.0"
  local body = vim.json.encode(msg)
  io.stdout:write(("Content-Length: %d\r\n\r\n%s"):format(#body, body))
  io.stdout:flush()
end

while true do
  local msg = read()
  if msg.method == "initialize" then
    send({
      id = msg.id,
      result = {
        capabilities = { textDocumentSync = 1, completionProvider = { triggerCharacters = { "." } } },
        serverInfo = { name = "fake-sigil", version = "0.0.0" },
      },
    })
  elseif msg.method == "textDocument/completion" then
    send({ id = msg.id, result = { { label = "fake_completion" } } })
  elseif msg.method == "exit" then
    os.exit(0)
  elseif msg.id ~= nil and msg.method ~= nil then
    send({ id = msg.id, result = vim.NIL })
  end
end
