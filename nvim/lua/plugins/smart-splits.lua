-- smart-splits.nvim: navigation and resizing across Neovim splits outside Herdr.
-- Under Herdr, herdr-nvim-nav and herdr-splits own these chords instead.
--
-- Keybinding scheme:
--   Alt+hjkl          - Move between splits
--   Ctrl+hjkl         - Resize splits
--   <leader><leader>hjkl - Swap buffers between Neovim windows
return {
  "mrjones2014/smart-splits.nvim",
  cond = vim.env.HERDR_ENV ~= "1",
  lazy = false,
  opts = {
    at_edge = "wrap",
  },
  config = function(_, opts)
    require("smart-splits").setup(opts)
    -- Keymaps are set in config/keymaps.lua (VeryLazy) to ensure they load
    -- AFTER LazyVim's default keymaps and can override <A-j>/<A-k> move-line bindings.
  end,
}
