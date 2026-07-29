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

-- Use smart-splits under tmux and herdr-splits inside a Herdr pane.
local pane_navigation = require("config.pane-navigation")

-- Navigate between splits/panes (matches tilish Alt+hjkl)
vim.keymap.set({ "n", "t" }, "<A-h>", function() pane_navigation.move("h") end, { desc = "Move to left split/pane" })
vim.keymap.set({ "n", "t" }, "<A-j>", function() pane_navigation.move("j") end, { desc = "Move to below split/pane" })
vim.keymap.set({ "n", "t" }, "<A-k>", function() pane_navigation.move("k") end, { desc = "Move to above split/pane" })
vim.keymap.set({ "n", "t" }, "<A-l>", function() pane_navigation.move("l") end, { desc = "Move to right split/pane" })

-- Resize splits
vim.keymap.set("n", "<C-h>", function() pane_navigation.resize("h") end, { desc = "Resize split left" })
vim.keymap.set("n", "<C-j>", function() pane_navigation.resize("j") end, { desc = "Resize split down" })
vim.keymap.set("n", "<C-k>", function() pane_navigation.resize("k") end, { desc = "Resize split up" })
vim.keymap.set("n", "<C-l>", function() pane_navigation.resize("l") end, { desc = "Resize split right" })

-- Swap buffers between windows
vim.keymap.set("n", "<leader><leader>h", function() pane_navigation.swap("h") end, { desc = "Swap buffer left" })
vim.keymap.set("n", "<leader><leader>j", function() pane_navigation.swap("j") end, { desc = "Swap buffer down" })
vim.keymap.set("n", "<leader><leader>k", function() pane_navigation.swap("k") end, { desc = "Swap buffer up" })
vim.keymap.set("n", "<leader><leader>l", function() pane_navigation.swap("l") end, { desc = "Swap buffer right" })

map("n", "<leader>as", "<cmd>CopilotChatSaveWithInput<CR>", opts)
map("n", "<leader>gil", "<cmd>Octo issue list<CR>", opts)
map("n", "<leader>gic", "<cmd>Octo issue create<CR>", opts)
map("n", "<leader>gpc", "<cmd>Octo pr create<CR>", opts)
map("n", "<leader>gpl", "<cmd>Octo pr list<CR>", opts)
map("n", "<leader>gps", "<cmd>Octo pr search<CR>", opts)

map("n", "<Leader>gr", ":OpenInGHRepo <CR>", { silent = true, noremap = true })
map("n", "<Leader>gf", ":OpenInGHFile <CR>", { silent = true, noremap = true })
map("v", "<Leader>gf", ":OpenInGHFileLines <CR>", { silent = true, noremap = true })
