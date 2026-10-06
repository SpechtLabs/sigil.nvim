-- :checkhealth sigil

local M = {}

local health = vim.health

--- The version `sigil version -o json` reports, or nil and why not.
---@param path string
---@return string? version
---@return string? error
function M.binary_version(path)
  local ok, proc = pcall(vim.system, { path, "version", "-o", "json" }, { text = true })
  if not ok then
    return nil, tostring(proc)
  end
  local out = proc:wait(5000)
  if out.code ~= 0 then
    return nil, ("`%s version` exited with status %d: %s"):format(path, out.code, vim.trim(out.stderr or ""))
  end
  local decoded, info = pcall(vim.json.decode, out.stdout or "")
  if decoded and type(info) == "table" and type(info.version) == "string" then
    return info.version
  end
  return nil, ("`%s version -o json` printed something else: %s"):format(path, vim.trim(out.stdout or ""))
end

local function check_neovim()
  health.start("sigil.nvim")
  local v = vim.version()
  local version = ("%d.%d.%d"):format(v.major, v.minor, v.patch)
  if vim.fn.has("nvim-0.11") == 1 then
    health.ok("Neovim " .. version)
  else
    health.error("Neovim " .. version .. " is too old", "sigil.nvim needs Neovim 0.11 or later")
  end
  local ft = vim.filetype.match({ filename = "policy.sigil" })
  if ft == "sigil" then
    health.ok("`*.sigil` files get the `sigil` filetype")
  else
    health.error(
      ("`*.sigil` files get the filetype %s, not `sigil`"):format(ft and ("`" .. ft .. "`") or "none"),
      "Another plugin or your config overrides the detection; check vim.filetype.add calls for `sigil`."
    )
  end
  if require("sigil").is_configured() then
    health.ok("setup() ran")
  else
    health.info("setup() hasn't run yet; it runs with the defaults and vim.g.sigil in the first sigil buffer")
  end
end

---@param options sigil.Options
local function check_binary(options)
  local lsp = require("sigil.lsp")
  local config = require("sigil.config")
  health.start("sigil binary")
  local bin = vim.fn.exepath(options.path)
  if bin ~= "" then
    local version, err = M.binary_version(bin)
    if version then
      health.ok(("found %s, version %s"):format(bin, version))
    else
      health.warn(("found %s, but couldn't read its version"):format(bin), err)
    end
  elseif options.lsp.cmd then
    health.info(("`%s` isn't in $PATH, so its version is unknown; `lsp.cmd` starts the server"):format(options.path))
  else
    health.error(("`%s` isn't executable or isn't in $PATH"):format(options.path), {
      "Install it with Homebrew: brew install --cask spechtlabs/tap/sigil",
      "or with mise: mise use -g github:SpechtLabs/sigil",
      "or point the plugin at it: require('sigil').setup({ path = '/path/to/sigil' })",
    })
    return
  end
  if not options.lsp.enabled then
    return
  end
  local path, checkable = lsp.executable(options)
  if not checkable then
    health.info("`lsp.cmd` is a function, so there's no command to probe")
    return
  end
  local cmd = config.lsp_cmd(options) --[[@as string[] ]]
  if not path then
    health.error(("`lsp.cmd` runs `%s`, which isn't executable or isn't in $PATH"):format(cmd[1]))
    return
  end
  local result, probe_err = lsp.probe(cmd, { timeout = 5000 })
  if result then
    local info = result.server_info or {}
    health.ok(
      ("`%s` answers initialize%s"):format(
        table.concat(cmd, " "),
        info.name and (" as " .. info.name .. (info.version and (" " .. info.version) or "")) or ""
      )
    )
  else
    health.error(("`%s` doesn't start a language server: %s"):format(table.concat(cmd, " "), probe_err), {
      'sigil releases before the language server exit with `"sigil lsp" is not implemented yet`; upgrade sigil.',
      "brew upgrade --cask spechtlabs/tap/sigil, or mise up github:SpechtLabs/sigil",
    })
  end
end

---@param options sigil.Options
local function check_lsp(options)
  local lsp = require("sigil.lsp")
  health.start("language server")
  if not options.lsp.enabled then
    health.info("disabled with `lsp.enabled = false`")
    return
  end
  local conf = vim.lsp.config[lsp.name]
  if not conf then
    health.error("no `sigil` LSP config", "lsp/sigil.lua isn't on the runtimepath; check how the plugin is installed")
    return
  end
  local cmd = conf.cmd
  health.ok(
    ("config: cmd %s, root markers %s"):format(
      type(cmd) == "table" and table.concat(cmd, " ") or "function",
      table.concat(
        vim.tbl_map(function(m)
          return type(m) == "table" and table.concat(m, "|") or m
        end, conf.root_markers or {}),
        ", "
      )
    )
  )
  if vim.lsp.is_enabled == nil or vim.lsp.is_enabled(lsp.name) then
    health.ok("enabled for sigil buffers")
  elseif not require("sigil").is_configured() then
    health.info("enabled in the first sigil buffer, when setup() runs")
  else
    health.warn("not enabled", "It's enabled once the binary is found; see `sigil binary` above.")
  end
  local clients = vim.lsp.get_clients({ name = lsp.name })
  if #clients == 0 then
    health.info("no client running; open a .sigil file to start one")
  end
  for _, client in ipairs(clients) do
    health.ok(
      ("client %d running, root %s, %d buffer(s)"):format(
        client.id,
        client.root_dir or "none (single file)",
        vim.tbl_count(client.attached_buffers)
      )
    )
  end
end

---@param options sigil.Options
local function check_treesitter(options)
  local ts = require("sigil.treesitter")
  health.start("tree-sitter")
  if not options.treesitter.enabled then
    health.info("disabled with `treesitter.enabled = false`")
    return
  end
  local flavor = ts.flavor(true)
  if flavor == "main" then
    health.ok("nvim-treesitter `main` found")
    if ts.register() then
      local info = ts.install_info(options.treesitter)
      health.ok(
        ("parser registered: %s"):format(
          info.path and ("local checkout " .. info.path)
            or ("%s, %s, revision %s"):format(info.url, info.location, info.revision)
        )
      )
    end
    if vim.fn.executable("tree-sitter") == 1 then
      health.ok("tree-sitter CLI found; nvim-treesitter builds the parser with it")
    else
      health.warn(
        "tree-sitter CLI not found",
        "nvim-treesitter `main` needs tree-sitter-cli 0.26.1 or later to build parsers, e.g. mise use -g tree-sitter"
      )
    end
  elseif flavor == "master" then
    health.ok("nvim-treesitter `master` found")
    ts.register()
  else
    health.info("nvim-treesitter not found; install the parser yourself or keep the regex highlighting")
  end
  if ts.has_parser() then
    local files = vim.api.nvim_get_runtime_file("parser/sigil.*", false)
    health.ok("parser installed" .. (files[1] and (": " .. files[1]) or ""))
  elseif flavor then
    health.warn(
      "parser not installed",
      "Run :TSInstall sigil, or open a .sigil file with `treesitter.ensure_installed` on"
    )
  else
    health.warn("parser not installed", "Without it, sigil buffers use the regex highlighting in syntax/sigil.vim")
  end
  for _, query in ipairs({ "highlights", "locals", "folds", "indents", "injections", "textobjects" }) do
    local files = vim.treesitter.query.get_files("sigil", query)
    if #files > 0 then
      health.ok(("query %s: %s"):format(query, files[1]))
    else
      health.info(("no %s query"):format(query))
    end
  end
end

function M.check()
  local config = require("sigil.config")
  if not require("sigil").is_configured() then
    -- The options the first sigil buffer will apply, without applying them.
    config.set()
  end
  local options = config.options
  check_neovim()
  check_binary(options)
  check_lsp(options)
  check_treesitter(options)
end

return M
