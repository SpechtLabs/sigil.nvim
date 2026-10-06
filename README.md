# sigil.nvim

Neovim support for [Sigil](https://sigil.specht-labs.de), the policy language: the `sigil` filetype for `*.sigil` policy and kind files, the Sigil language server (`sigil lsp`) for diagnostics, completion, hover, go-to-definition and formatting, and the Sigil tree-sitter parser and queries for nvim-treesitter.

Each part degrades on its own. Without nvim-treesitter or the parser, sigil buffers keep regex highlighting, `//` comments and the language server. Without the `sigil` binary, they keep highlighting and comments, and `:checkhealth sigil` says how to install it.

- [Requirements](#requirements)
- [Install the sigil binary](#install-the-sigil-binary)
- [Install the plugin](#install-the-plugin)
- [Tree-sitter](#tree-sitter)
- [Configuration](#configuration)
- [Language server](#language-server)
- [Commands](#commands)
- [Health check](#health-check)
- [Troubleshooting](#troubleshooting)
- [How it relates to the sigil repository](#how-it-relates-to-the-sigil-repository)
- [Development](#development)

## Requirements

| Needs | For |
| --- | --- |
| Neovim 0.11 or later | Everything. The plugin ships `lsp/sigil.lua` for `vim.lsp.config`/`vim.lsp.enable`, which 0.11 introduced |
| `sigil` in `$PATH`, from a release with `sigil lsp` | The language server and `:checkhealth sigil`'s version check |
| [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) `main` and Neovim 0.12, or `master` | Installing the tree-sitter parser (optional) |
| [tree-sitter CLI](https://github.com/tree-sitter/tree-sitter/blob/master/crates/cli/README.md) 0.26.1+, `curl`, `tar`, a C compiler | nvim-treesitter `main` building the parser |

No package manager is required, and lazy.nvim isn't a dependency.

## Install the sigil binary

The plugin uses the `sigil` in `$PATH` and never downloads one. Install it with Homebrew:

```sh
brew install --cask spechtlabs/tap/sigil
```

or with [mise](https://mise.jdx.dev):

```sh
mise use -g github:SpechtLabs/sigil
```

or download a signed archive from the [releases](https://github.com/SpechtLabs/sigil/releases). To use a binary outside `$PATH`, set [`path`](#configuration).

## Install the plugin

### lazy.nvim and LazyVim

```lua
{ "SpechtLabs/sigil.nvim" }
```

That's the whole spec, also under LazyVim with `defaults.lazy = true`. The plugin's [`lazy.lua`](lazy.lua) loads it at startup (its `plugin/` file only defines two autocommands and a command; the Lua modules load in the first sigil buffer) and calls `setup()`. Add `opts` to change [options](#configuration), and `version = "*"` to follow the plugin's releases instead of its default branch:

```lua
{ "SpechtLabs/sigil.nvim", version = "*", opts = { treesitter = { fold = true } } }
```

A LazyVim user who wants the parser in nvim-treesitter's `ensure_installed` list, the way LazyVim's language extras do it, can put this in `lua/plugins/sigil.lua`:

```lua
return {
  { "SpechtLabs/sigil.nvim", version = "*", opts = {} },
  { "nvim-treesitter/nvim-treesitter", opts = { ensure_installed = { "sigil" } } },
}
```

LazyVim's nvim-lspconfig, mason, blink.cmp and conform.nvim need nothing: the plugin enables the server itself, mason isn't involved because the binary comes from `$PATH`, blink.cmp adds its capabilities to every server, and LazyVim's conform falls back to LSP formatting.

### vim.pack (Neovim 0.12)

```lua
vim.pack.add({ "https://github.com/SpechtLabs/sigil.nvim" })
```

### vim-plug

```vim
Plug 'SpechtLabs/sigil.nvim'
```

### mini.deps

```lua
MiniDeps.add({ source = "SpechtLabs/sigil.nvim" })
```

### packer.nvim

```lua
use("SpechtLabs/sigil.nvim")
```

With any manager but lazy.nvim, `setup()` is optional. The first sigil buffer applies the defaults and `vim.g.sigil`, so either of these configures the plugin:

```lua
require("sigil").setup({ path = "/opt/sigil/bin/sigil" })
-- or, before the first sigil buffer opens:
vim.g.sigil = { path = "/opt/sigil/bin/sigil" }
```

## Tree-sitter

The grammar is `sigil`, in [`editors/tree-sitter-sigil`](https://github.com/SpechtLabs/sigil/tree/main/editors/tree-sitter-sigil) of the Sigil repository. The plugin carries its highlights, locals, folds, indents, injections and textobjects queries in `queries/sigil/`, copied from the grammar revision it pins.

### nvim-treesitter `main`

The plugin adds `sigil` to nvim-treesitter's parser table every time nvim-treesitter fires its `User TSUpdate` event, so `:TSInstall sigil`, `:TSUpdate sigil` and `require("nvim-treesitter").install({ "sigil" })` work. The entry it adds is:

```lua
require("nvim-treesitter.parsers").sigil = {
  install_info = {
    url = "https://github.com/SpechtLabs/sigil",
    location = "editors/tree-sitter-sigil",
    revision = "<the commit this release of sigil.nvim pins>",
    queries = "editors/tree-sitter-sigil/queries",
  },
  tier = 2,
}
```

With `treesitter.ensure_installed` on, the default, the first sigil buffer of a session installs the parser when it's missing and the tree-sitter CLI is in `$PATH`. Then the plugin starts highlighting (`vim.treesitter.start()`), sets `indentexpr` to nvim-treesitter's, and, with `treesitter.fold = true`, sets tree-sitter folding. LazyVim does the same for every installed parser, which does no harm.

`queries` makes nvim-treesitter install the grammar's queries next to the parser, ahead of the plugin on the runtimepath, so the queries in use always match the parser that was built. The copies in `queries/sigil/` serve `master` and setups without nvim-treesitter.

After updating the plugin, run `:TSUpdate sigil` to build the grammar revision the new release pins. Until then, the parser and its queries stay at the old revision together.

### nvim-treesitter `master`

The frozen `master` branch, for Neovim 0.11, doesn't have the `TSUpdate` event. The plugin registers the parser in the first sigil buffer, and in `setup()` when nvim-treesitter is already loaded; then run `:TSInstall sigil`.

### Without nvim-treesitter

Build the parser yourself (`tree-sitter build` in `editors/tree-sitter-sigil`) and put it at `parser/sigil.so` on the runtimepath. Until a parser is there, `syntax/sigil.vim` highlights keywords, literals, comments and declarations with regular expressions.

## Configuration

`setup()`, lazy.nvim's `opts` and `vim.g.sigil` take the same table. These are the defaults:

```lua
require("sigil").setup({
  -- The sigil binary: a name looked up in $PATH, or a path.
  path = "sigil",
  lsp = {
    -- Start the language server in sigil buffers.
    enabled = true,
    -- The whole server command; nil runs `<path> lsp --stdio`.
    cmd = nil,
    -- A sigil configuration file marks the workspace, in this order, then .git.
    root_markers = { "sigil.yaml", ".sigil.yaml", "sigil.json", ".sigil.json", "sigil.toml", ".sigil.toml", ".git" },
    -- Sent to the server as its configuration; sigil lsp reads none today.
    settings = {},
    -- Any other vim.lsp.Config field (capabilities, on_attach, init_options,
    -- handlers, ...) is passed to vim.lsp.config("sigil", ...).
  },
  treesitter = {
    -- false leaves tree-sitter alone: no parser registration, install,
    -- highlighting, indentation or folding.
    enabled = true,
    -- Install the parser in the first sigil buffer when it's missing
    -- (nvim-treesitter main and the tree-sitter CLI).
    ensure_installed = true,
    -- Start tree-sitter highlighting once the parser is installed.
    highlight = true,
    -- Indent with the tree-sitter indents query.
    indent = true,
    -- Fold with the tree-sitter folds query.
    fold = false,
    -- Where nvim-treesitter gets the grammar.
    url = "https://github.com/SpechtLabs/sigil",
    location = "editors/tree-sitter-sigil",
    revision = "<pinned commit>",
    -- A local checkout of the grammar directory, built as it is.
    -- Overrides url and revision.
    path = nil,
  },
})
```

A table merges into the default; a list such as `root_markers` replaces it. An unknown option or a value of the wrong type fails `setup()` with a message naming it, and the previous options stay.

`ftplugin/sigil.lua` sets `commentstring` to `// %s` (so `gc` comments lines), `comments` to `://`, and the indentation `sigil fmt` uses: `expandtab`, `shiftwidth=2`, `softtabstop=2`, `tabstop=2`. Set `vim.g.sigil_recommended_style = false` to keep your own indentation options.

## Language server

`lsp/sigil.lua` is on the runtimepath, so on Neovim 0.11+ `vim.lsp.config.sigil` exists and `vim.lsp.enable("sigil")` works without the rest of the plugin:

```lua
return {
  cmd = { "sigil", "lsp", "--stdio" },
  filetypes = { "sigil" },
  root_markers = { "sigil.yaml", ".sigil.yaml", "sigil.json", ".sigil.json", "sigil.toml", ".sigil.toml", ".git" },
}
```

`setup()` layers the options over it and enables it when the binary is executable. When it isn't, the first sigil buffer shows one warning and the server stays off.

The server reads the kinds named in the nearest sigil configuration file (`sigil.yaml`, `.sigil.toml` or another name `sigil` reads), and offers diagnostics, completion of inputs, fields, functions and decision payload keys, hover with a decision's signature, go-to-definition for lets and `use` targets, and formatting in `sigil fmt`'s style. Use them through Neovim's LSP mappings: `K` hovers, `CTRL-]` (or LazyVim's `gd`) jumps to a definition, `gq` and `vim.lsp.buf.format()` format.

**Completion.** blink.cmp registers its capabilities for every server on Neovim 0.11+. For nvim-cmp, the plugin merges `cmp_nvim_lsp`'s capabilities when that module is installed. Neither needs configuration.

**Formatting with conform.nvim.** With `lsp_format = "fallback"`, which LazyVim sets, conform formats sigil buffers through the server. To have conform run `sigil fmt` itself:

```lua
require("conform").setup({
  formatters_by_ft = { sigil = { "sigil_fmt" } },
  formatters = {
    sigil_fmt = { command = "sigil", args = { "fmt", "-" }, stdin = true },
  },
})
```

## Commands

| Command | Does |
| --- | --- |
| `:Sigil` or `:Sigil info` | Shows the binary, the server command, the client attached to the current buffer and its root, and the tree-sitter state |
| `:Sigil restart` | Stops the sigil clients and starts them again, e.g. after upgrading sigil or editing `sigil.yaml` |
| `:Sigil log` | Opens the LSP log in a new tab |

`:help sigil` has the same reference as this README.

## Health check

`:checkhealth sigil` reports the Neovim version and filetype detection; the binary, its `sigil version`, and whether `sigil lsp --stdio` answers `initialize`; the LSP config and the running clients with their roots; and nvim-treesitter, the tree-sitter CLI, the parser and each query. For a sigil from before the language server it shows:

```text
sigil binary ~
- ✅ OK found /opt/homebrew/bin/sigil, version v0.7.3
- ❌ ERROR `sigil lsp --stdio` doesn't start a language server: exited with status 1: Error: "sigil lsp" is not implemented yet
  - ADVICE:
    - sigil releases before the language server exit with `"sigil lsp" is not implemented yet`; upgrade sigil.
    - brew upgrade --cask spechtlabs/tap/sigil, or mise up github:SpechtLabs/sigil
```

## Troubleshooting

**No diagnostics or completion.** Run `:checkhealth sigil`. "isn't executable" means `sigil` isn't in the `$PATH` Neovim sees; a GUI Neovim on macOS often doesn't get your shell's `$PATH`, so set `path`. "not implemented yet" means your sigil predates the language server; upgrade it. `:Sigil log` shows what the server wrote.

**The server picked the wrong workspace.** `:Sigil info` shows the root. The server reads the kinds named in the nearest configuration file above the file; put a `sigil.yaml` next to your policies, or set `lsp.root_markers`.

**sigil comes from mise in one project only.** Point the server at mise: `lsp = { cmd = { "mise", "exec", "--", "sigil", "lsp", "--stdio" } }`. mise picks the version for Neovim's working directory, so start Neovim inside the project.

**No tree-sitter highlighting.** `:checkhealth sigil` says whether nvim-treesitter, the tree-sitter CLI, the parser and the highlights query are there. `:TSLog` shows why a build failed.

**Highlighting looks old after an update.** Run `:TSUpdate sigil` to build the grammar revision the new release pins.

## How it relates to the sigil repository

The [sigil repository](https://github.com/SpechtLabs/sigil) holds the language, the `sigil` CLI with its language server, and the tree-sitter grammar in `editors/tree-sitter-sigil`. This repository holds only the Neovim side:

- The language server is `sigil lsp`, from the binary in `$PATH`. A sigil release and a sigil.nvim release don't need to match; `:checkhealth sigil` tells you when your sigil predates the server.
- The grammar is built by nvim-treesitter from the sigil repository at the commit `lua/sigil/config.lua` pins (`grammar_revision`). `queries/sigil/` is a copy of the grammar's `queries/` at that commit, and CI fails when they differ.
- The [Neovim guide](https://sigil.specht-labs.de/guides/editors/neovim/) on the Sigil site covers the same setup.

## Development

Every tool is pinned in `.mise.toml`:

```sh
mise install
mise run test                       # the test suite, headless
mise run test tests/test_lsp.lua    # one file
mise run lint                       # StyLua, lua-language-server, actionlint
mise run queries-check              # queries/sigil/ against the pinned grammar
```

The tests use [mini.test](https://github.com/nvim-mini/mini.test), which `tests/run.lua` clones with lazy.nvim and both nvim-treesitter branches into `.tests/deps` at pinned commits. Each case runs in a fresh child Neovim whose XDG directories point into `.tests/`, so nothing reads or writes your own config. Two optional suites need more than Neovim:

- `SIGIL_TEST_BIN=/path/to/sigil mise run test tests/test_e2e.lua` runs the plugin against a real `sigil lsp`: diagnostics, completion and formatting in `tests/fixtures/workspace`. Without the variable it uses the `sigil` in `$PATH`, and skips when there's none or when it predates the server.
- `SIGIL_TEST_INSTALL=1` builds the parser from the pinned revision with nvim-treesitter `main`; `SIGIL_TEST_PARSER=/path/to/sigil.so` runs the highlighting tests and parses every query against a parser you built.

### Moving the grammar pin

The pin is one line, `M.grammar_revision` in `lua/sigil/config.lua`, and it must be a commit on sigil's `main` or a release tag. Each file in `queries/sigil/` starts with `; Code generated by scripts/sync-grammar.lua from SpechtLabs/sigil@<commit>. DO NOT EDIT.`; `.gitattributes` marks them generated, so GitHub folds them in diffs. Change the grammar in the sigil repository, never here.

- **By hand:** `mise run queries -- --ref <tag or commit>` copies the queries from that commit, with the header, and rewrites the pin to the commit it resolved to. Commit both.
- **In CI:** the Sync grammar workflow runs every Monday against sigil's latest release, or by hand with any ref, and opens a pull request when the queries or the pin change.

`mise run queries-check`, which CI runs on every pull request, fails when a copy differs from the pinned commit, header included. `--source <sigil checkout>` copies from a local checkout for grammar work and leaves the pin alone, so that check fails until you sync with `--ref`.

## License

[Apache 2.0](LICENSE), like Sigil.
