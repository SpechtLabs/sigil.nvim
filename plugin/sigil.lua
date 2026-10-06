-- Loaded at startup, so it only defines autocommands and a command; the
-- modules under lua/sigil load in the first sigil buffer.

if vim.g.loaded_sigil then
  return
end
vim.g.loaded_sigil = true

if vim.fn.has("nvim-0.11") == 0 then
  vim.notify_once("sigil.nvim needs Neovim 0.11 or later", vim.log.levels.WARN)
  return
end

local group = vim.api.nvim_create_augroup("sigil", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "sigil",
  desc = "sigil.nvim: set up the buffer",
  callback = function(ev)
    require("sigil").attach(ev.buf)
  end,
})

-- nvim-treesitter's main branch fires this whenever it reloads its parser
-- table, before it installs or updates anything.
vim.api.nvim_create_autocmd("User", {
  group = group,
  pattern = "TSUpdate",
  desc = "sigil.nvim: register the sigil parser",
  callback = function()
    require("sigil.treesitter").register()
  end,
})

vim.api.nvim_create_user_command("Sigil", function(cmd)
  require("sigil").command(cmd.args)
end, {
  nargs = "?",
  desc = "sigil.nvim: info, restart or log",
  complete = function(lead)
    return require("sigil").complete(lead)
  end,
})
