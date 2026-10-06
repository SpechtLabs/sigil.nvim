-- The spec lazy.nvim merges into `{ "SpechtLabs/sigil.nvim" }`. Not lazy:
-- plugin/sigil.lua costs next to nothing at startup, and the parser has to be
-- registered before nvim-treesitter installs anything.
return {
  "SpechtLabs/sigil.nvim",
  lazy = false,
  opts = {},
}
