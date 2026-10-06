-- The Sigil language server, for vim.lsp.enable("sigil") on Neovim 0.11+.
-- require("sigil").setup() layers the plugin's options over this.

---@type vim.lsp.Config
return {
  cmd = { "sigil", "lsp", "--stdio" },
  filetypes = { "sigil" },
  root_markers = { "sigil.yaml", ".sigil.yaml", "sigil.json", ".sigil.json", "sigil.toml", ".sigil.toml", ".git" },
}
