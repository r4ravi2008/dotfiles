-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
--
local map = vim.api.nvim_set_keymap
local opts = { noremap = true, silent = true }

-- Disable LazyVim's default Alt+j/k move-line mappings
-- so smart-splits.nvim can use Alt+hjkl for pane/split navigation
vim.keymap.del({ "n", "i", "v" }, "<A-j>")
vim.keymap.del({ "n", "i", "v" }, "<A-k>")

-- smart-splits.nvim keymaps (set here in VeryLazy so they load AFTER LazyVim defaults)
local ss = require("smart-splits")

-- Navigate between splits/panes (matches tilish Alt+hjkl)
vim.keymap.set({ "n", "t" }, "<A-h>", ss.move_cursor_left, { desc = "Move to left split/pane" })
vim.keymap.set({ "n", "t" }, "<A-j>", ss.move_cursor_down, { desc = "Move to below split/pane" })
vim.keymap.set({ "n", "t" }, "<A-k>", ss.move_cursor_up, { desc = "Move to above split/pane" })
vim.keymap.set({ "n", "t" }, "<A-l>", ss.move_cursor_right, { desc = "Move to right split/pane" })

-- Resize splits
vim.keymap.set("n", "<C-h>", ss.resize_left, { desc = "Resize split left" })
vim.keymap.set("n", "<C-j>", ss.resize_down, { desc = "Resize split down" })
vim.keymap.set("n", "<C-k>", ss.resize_up, { desc = "Resize split up" })
vim.keymap.set("n", "<C-l>", ss.resize_right, { desc = "Resize split right" })

-- Swap buffers between windows
vim.keymap.set("n", "<leader><leader>h", ss.swap_buf_left, { desc = "Swap buffer left" })
vim.keymap.set("n", "<leader><leader>j", ss.swap_buf_down, { desc = "Swap buffer down" })
vim.keymap.set("n", "<leader><leader>k", ss.swap_buf_up, { desc = "Swap buffer up" })
vim.keymap.set("n", "<leader><leader>l", ss.swap_buf_right, { desc = "Swap buffer right" })

map("n", "<leader>as", "<cmd>CopilotChatSaveWithInput<CR>", opts)
map("n", "<leader>gil", "<cmd>Octo issue list<CR>", opts)
map("n", "<leader>gic", "<cmd>Octo issue create<CR>", opts)
map("n", "<leader>gpc", "<cmd>Octo pr create<CR>", opts)
map("n", "<leader>gpl", "<cmd>Octo pr list<CR>", opts)
map("n", "<leader>gps", "<cmd>Octo pr search<CR>", opts)

map("n", "<Leader>gr", ":OpenInGHRepo <CR>", { silent = true, noremap = true })
map("n", "<Leader>gf", ":OpenInGHFile <CR>", { silent = true, noremap = true })
map("v", "<Leader>gf", ":OpenInGHFileLines <CR>", { silent = true, noremap = true })
