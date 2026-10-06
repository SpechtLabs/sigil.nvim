-- Copies the tree-sitter queries from the sigil repository into
-- queries/sigil/, or checks that they match.
--
--   nvim -l scripts/sync-grammar.lua                 copy from the pinned revision
--   nvim -l scripts/sync-grammar.lua --ref v0.8.0    move the pin to a tag or commit, then copy
--   nvim -l scripts/sync-grammar.lua --source DIR    copy from a local sigil checkout (pin unchanged)
--   nvim -l scripts/sync-grammar.lua --check         fail if queries/sigil/ differs from the pin
--
-- The pin is M.grammar_revision in lua/sigil/config.lua. --check combines
-- with --ref and --source.
--
-- Each copy starts with a "Code generated ... DO NOT EDIT." line naming the
-- commit it came from; --check compares the copies with that line included.

local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(debug.getinfo(1, "S").source:sub(2))))
local config_file = vim.fs.joinpath(root, "lua", "sigil", "config.lua")
local queries_dir = vim.fs.joinpath(root, "queries", "sigil")
local url = "https://github.com/SpechtLabs/sigil"
local grammar = "editors/tree-sitter-sigil"

local function fail(msg, ...)
  io.stderr:write(("sync-grammar: " .. msg .. "\n"):format(...))
  os.exit(1)
end

local function say(msg, ...)
  io.stdout:write((msg .. "\n"):format(...))
end

---@param cmd string[]
---@param cwd? string
---@return string stdout
local function run(cmd, cwd)
  local out = vim.system(cmd, { cwd = cwd, text = true }):wait()
  if out.code ~= 0 then
    fail("`%s` failed (%d): %s", table.concat(cmd, " "), out.code, vim.trim(out.stderr or ""))
  end
  return vim.trim(out.stdout or "")
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return data
end

local function write(path, data)
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
end

-- The .scm files in dir, by name.
---@return table<string, string>
local function scm_files(dir)
  local files = {}
  if vim.uv.fs_stat(dir) then
    for name, kind in vim.fs.dir(dir) do
      if kind == "file" and name:match("%.scm$") then
        files[name] = read(vim.fs.joinpath(dir, name))
      end
    end
  end
  return files
end

local function pinned()
  local src = read(config_file)
  if not src then
    fail("can't read %s", config_file)
    return ""
  end
  return src:match('M%.grammar_revision = "([^"]*)"') or fail("no M.grammar_revision line in %s", config_file)
end

local function pin(revision)
  local src = read(config_file) or ""
  local new, n = src:gsub('(M%.grammar_revision = ")[^"]*(")', "%1" .. revision .. "%2")
  if n ~= 1 then
    fail("expected one M.grammar_revision line in %s, found %d", config_file, n)
  end
  write(config_file, new)
end

-- Fetches only the queries directory at ref, and returns it with the commit
-- the ref resolved to.
---@return string dir, string sha
local function fetch(ref)
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  run({ "git", "init", "-q" }, tmp)
  run({ "git", "remote", "add", "origin", url }, tmp)
  run({ "git", "config", "remote.origin.promisor", "true" }, tmp)
  run({ "git", "config", "remote.origin.partialclonefilter", "blob:none" }, tmp)
  run({ "git", "fetch", "-q", "--depth", "1", "--filter=blob:none", "origin", ref }, tmp)
  local sha = run({ "git", "rev-parse", "FETCH_HEAD" }, tmp)
  run({ "git", "checkout", "-q", "FETCH_HEAD", "--", grammar .. "/queries" }, tmp)
  return vim.fs.joinpath(tmp, grammar, "queries"), sha
end

---@type { check: boolean, ref?: string, source?: string }
local opts = { check = false }
local args = _G.arg or {}
local i = 1
while i <= #args do
  local a = args[i]
  if a == "--check" then
    opts.check = true
  elseif a == "--ref" or a == "--source" then
    opts[a:sub(3)] = args[i + 1] or fail("%s needs a value", a)
    i = i + 1
  elseif a == "-h" or a == "--help" then
    say("usage: nvim -l scripts/sync-grammar.lua [--check] [--ref REF | --source DIR]")
    os.exit(0)
  else
    fail("unknown argument %q; see --help", a)
  end
  i = i + 1
end
if opts.ref and opts.source then
  fail("--ref and --source can't be combined")
end

local src, label, sha
if opts.source then
  local dir = vim.fs.normalize(opts.source)
  -- Either a sigil checkout or the grammar directory itself.
  for _, candidate in ipairs({ vim.fs.joinpath(dir, grammar, "queries"), vim.fs.joinpath(dir, "queries") }) do
    if vim.uv.fs_stat(candidate) then
      src = candidate
      break
    end
  end
  src = src or fail("no queries directory under %s", dir)
  label = src
  local out = vim.system({ "git", "-C", src, "rev-parse", "HEAD" }, { text = true }):wait()
  sha = out.code == 0 and vim.trim(out.stdout) or "local"
else
  local ref = opts.ref or pinned()
  src, sha = fetch(ref)
  label = ("%s at %s (%s)"):format(url, ref, sha:sub(1, 12))
end

local want = scm_files(src)
if next(want) == nil then
  fail("%s has no .scm files", label)
end
-- Every copy says where it came from, and that it isn't edited here. The
-- header is a comment, so Neovim still reads `; inherits:` lines below it.
for name, data in pairs(want) do
  want[name] = ("; Code generated by scripts/sync-grammar.lua from SpechtLabs/sigil@%s. DO NOT EDIT.\n%s"):format(
    sha,
    data
  )
end
local have = scm_files(queries_dir)

local names = {}
for name in pairs(want) do
  names[name] = true
end
for name in pairs(have) do
  names[name] = true
end
local sorted = vim.tbl_keys(names)
table.sort(sorted)

local diffs = {}
for _, name in ipairs(sorted) do
  if want[name] == nil then
    diffs[#diffs + 1] = { name, "only in queries/sigil/", "removed" }
  elseif have[name] == nil then
    diffs[#diffs + 1] = { name, "missing from queries/sigil/", "added" }
  elseif want[name] ~= have[name] then
    diffs[#diffs + 1] = { name, "differs", "updated" }
  end
end

if opts.check then
  if opts.ref and sha ~= pinned() then
    diffs[#diffs + 1] = { "lua/sigil/config.lua", ("pins %s, not %s"):format(pinned(), sha) }
  end
  if #diffs == 0 then
    say("queries/sigil/ matches %s", label)
    os.exit(0)
  end
  for _, d in ipairs(diffs) do
    say("  %-28s %s", d[1], d[2])
  end
  fail("queries/sigil/ doesn't match %s; run nvim -l scripts/sync-grammar.lua", label)
end

vim.fn.mkdir(queries_dir, "p")
for name in pairs(have) do
  if want[name] == nil then
    os.remove(vim.fs.joinpath(queries_dir, name))
  end
end
for name, data in pairs(want) do
  write(vim.fs.joinpath(queries_dir, name), data)
end
if sha and opts.ref then
  pin(sha)
  say("pinned %s", sha)
end
for _, d in ipairs(diffs) do
  say("  %-28s %s", d[1], d[3])
end
say("copied %d queries from %s", vim.tbl_count(want), label)
if opts.source then
  say("note: the pin is unchanged, so the CI check fails until you sync with --ref")
end
