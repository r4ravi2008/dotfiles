return {
  "lmilojevicc/herdr-splits.nvim",
  commit = "107273e004e4f7ef07f13c83164d2cb2c51df65d",
  cond = vim.env.HERDR_ENV == "1",
  lazy = false,
  opts = {
    default_amount = 0.03,
    neovim_amount = 3,
    at_edge = "wrap",
    nav_at_edge = "wrap",
    unzoom_on_nav = true,
    auto_sync_herdr = false,
    nav_keys = {
      left = "<M-h>",
      down = "<M-j>",
      up = "<M-k>",
      right = "<M-l>",
    },
    resize_keys = {
      left = "<C-h>",
      down = "<C-j>",
      up = "<C-k>",
      right = "<C-l>",
    },
  },
}
