return {
  "christoomey/vim-tmux-navigator",
  init = function()
    vim.g.tmux_navigator_preserve_zoom = 1
  end,
  keys = {
    { "<C-CR>", "<cmd>TmuxNavigatePrevious<cr>", mode = "n", desc = "Go to the previous pane" },
    { "<C-h>", "<cmd>TmuxNavigateLeft<cr>", mode = "n", desc = "Go to the left pane" },
    { "<C-j>", "<cmd>TmuxNavigateDown<cr>", mode = "n", desc = "Go to the down pane" },
    { "<C-k>", "<cmd>TmuxNavigateUp<cr>", mode = "n", desc = "Go to the up pane" },
    { "<C-l>", "<cmd>TmuxNavigateRight<cr>", mode = "n", desc = "Go to the right pane" },
    -- Terminal mode mappings
    { "<C-h>", "<C-\\><C-n><C-w>h", mode = "t", desc = "Go to the left pane" },
    { "<C-j>", "<C-\\><C-n><C-w>j", mode = "t", desc = "Go to the down pane" },
    { "<C-k>", "<C-\\><C-n><C-w>k", mode = "t", desc = "Go to the up pane" },
    { "<C-l>", "<C-\\><C-n><C-w>l", mode = "t", desc = "Go to the right pane" },
  },
}
