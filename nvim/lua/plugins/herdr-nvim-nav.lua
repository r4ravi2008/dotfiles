-- Fast Alt+hjkl navigation across Herdr panes and Neovim splits.
-- Uses a C herdr action + marker file (~10ms) instead of herdr-splits' bash
-- scripts that shell out to the herdr CLI multiple times per keypress (~300ms).
return {
  dir = vim.fn.expand("~/.dotfiles/herdr/nvim-nav"),
  name = "herdr-nvim-nav",
  cond = vim.env.HERDR_ENV == "1",
  lazy = false,
  opts = {
    with_tmux = false,
    keymaps = {
      left = { "<M-h>" },
      down = { "<M-j>" },
      up = { "<M-k>" },
      right = { "<M-l>" },
    },
  },
  config = function(_, opts)
    require("herdr-nvim-nav").setup(opts)
  end,
}
