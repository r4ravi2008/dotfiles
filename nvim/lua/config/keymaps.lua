-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
--
local map = vim.api.nvim_set_keymap
local opts = { noremap = true, silent = true }

map("n", "<leader>as", "<cmd>CopilotChatSaveWithInput<CR>", opts)
map("n", "<leader>gil", "<cmd>Octo issue list<CR>", opts)
map("n", "<leader>gic", "<cmd>Octo issue create<CR>", opts)
map("n", "<leader>gpc", "<cmd>Octo pr create<CR>", opts)
map("n", "<leader>gpl", "<cmd>Octo pr list<CR>", opts)
map("n", "<leader>gps", "<cmd>Octo pr search<CR>", opts)

map("n", "<Leader>gr", ":OpenInGHRepo <CR>", { silent = true, noremap = true })
map("n", "<Leader>gf", ":OpenInGHFile <CR>", { silent = true, noremap = true })
map("v", "<Leader>gf", ":OpenInGHFileLines <CR>", { silent = true, noremap = true })
