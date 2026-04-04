-- Minimal init for running tests
local plenary_path = vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
local nui_path = vim.fn.expand("~/.local/share/nvim/lazy/nui.nvim")
local plugin_path = vim.fn.expand("~/.local/share/nvim/lazy/db-cli-adapter.nvim")

vim.opt.rtp:prepend(plenary_path)
vim.opt.rtp:prepend(nui_path)
vim.opt.rtp:prepend(plugin_path)

vim.cmd("runtime plugin/plenary.vim")
